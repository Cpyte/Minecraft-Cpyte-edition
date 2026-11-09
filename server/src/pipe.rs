//! The in-memory half of an integrated connection.
//!
//! Pumpkin takes any `AsyncRead + AsyncWrite` for a Java connection, so an
//! embedded server needs no socket at all: the two queues below are the wire.
//! The server end implements the async interface tokio expects, the client end
//! is plain lock-and-copy C, and a blocked side is woken by the other's
//! movement rather than polled. The only latency is a mutex.

use std::collections::VecDeque;
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::task::{Context, Poll, Waker};

/// The bytes of one direction and the waiters that move with them.
struct QueueState {
    bytes: VecDeque<u8>,
    capacity: usize,
    /// Set when the writing side is finished. A reader that finds the queue
    /// empty and the pipe closed sees EOF, exactly as on a socket.
    closed: bool,
    /// Task blocked waiting for bytes.
    reader: Option<Waker>,
    /// Task blocked because the queue was full.
    writer: Option<Waker>,
}

/// One direction of the pipe.
///
/// `capacity` bounds the queue so a client that stops reading applies
/// backpressure to the server instead of letting the world's outgoing bytes
/// pile up without limit. A capacity of `usize::MAX` means unbounded, which is
/// used for the client-to-server direction: a client writes packets that are
/// small and few, and must never block inside a send.
///
/// The condvar sits beside the mutex rather than inside it: waiting hands the
/// guard to `wait_timeout` by value, and a condvar reached through that guard
/// cannot also be borrowed in the same expression.
struct Queue {
    state: Mutex<QueueState>,
    filled: Condvar,
}

impl Queue {
    fn new(capacity: usize) -> Self {
        Self {
            state: Mutex::new(QueueState {
                bytes: VecDeque::new(),
                capacity,
                closed: false,
                reader: None,
                writer: None,
            }),
            filled: Condvar::new(),
        }
    }

    fn poison() -> io::Error {
        io::Error::other("the embedded pipe was poisoned")
    }

    fn lock(&self) -> io::Result<MutexGuard<'_, QueueState>> {
        self.state.lock().map_err(|_| Queue::poison())
    }

    /// Append what fits. Returns how many bytes were taken.
    fn put(&self, src: &[u8], cx: Option<&mut Context>) -> Poll<io::Result<usize>> {
        let mut queue = match self.lock() {
            Ok(queue) => queue,
            Err(error) => return Poll::Ready(Err(error)),
        };
        if queue.closed {
            return Poll::Ready(Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "client end closed",
            )));
        }
        let space = queue.capacity.saturating_sub(queue.bytes.len());
        if space == 0 {
            if let Some(context) = cx {
                queue.writer = Some(context.waker().clone());
            }
            return Poll::Pending;
        }
        let taken = if src.len() <= space { src.len() } else { space };
        queue.bytes.extend(src[..taken].iter().copied());
        if let Some(waker) = queue.reader.take() {
            waker.wake();
        }
        drop(queue);
        self.filled.notify_all();
        Poll::Ready(Ok(taken))
    }

    /// Take what is available. `Ok(0)` with the pipe closed means EOF.
    fn get(&self, dst: &mut [u8], cx: Option<&mut Context>) -> Poll<io::Result<usize>> {
        let mut queue = match self.lock() {
            Ok(queue) => queue,
            Err(error) => return Poll::Ready(Err(error)),
        };
        if queue.bytes.is_empty() {
            if queue.closed {
                return Poll::Ready(Ok(0));
            }
            if let Some(context) = cx {
                queue.reader = Some(context.waker().clone());
            }
            return Poll::Pending;
        }
        let taken = if dst.len() <= queue.bytes.len() {
            dst.len()
        } else {
            queue.bytes.len()
        };
        for (slot, byte) in dst[..taken].iter_mut().zip(queue.bytes.drain(..taken)) {
            *slot = byte;
        }
        if let Some(waker) = queue.writer.take() {
            waker.wake();
        }
        drop(queue);
        // Space appeared, so a writer stopped by a full queue can run.
        self.filled.notify_all();
        Poll::Ready(Ok(taken))
    }

    fn close(&self) {
        if let Ok(mut queue) = self.lock() {
            queue.closed = true;
            if let Some(waker) = queue.reader.take() {
                waker.wake();
            }
            if let Some(waker) = queue.writer.take() {
                waker.wake();
            }
        }
        self.filled.notify_all();
    }
}

/// A connected pair of queues: the client writes into `to_server` and reads
/// from `from_server`, the embedded server does the opposite.
pub struct Channel {
    to_server: Queue,
    from_server: Queue,
}

impl Channel {
    /// `outgoing` bounds how much the server can have in flight before it
    /// waits for the client to read.
    pub fn new(outgoing_capacity: usize) -> Arc<Self> {
        Arc::new(Self {
            to_server: Queue::new(usize::MAX),
            from_server: Queue::new(outgoing_capacity),
        })
    }

    /// Bytes a client thread hands to the server. Always accepts everything.
    pub fn client_write(&self, data: &[u8]) -> usize {
        match self.to_server.put(data, None) {
            Poll::Ready(Ok(taken)) => taken,
            _ => 0,
        }
    }

    /// Bytes the server produced, copied into `dst`. Returns the count, `-1`
    /// when nothing has arrived yet, or `-2` once the server closed and the
    /// queue drained.
    pub fn client_read(&self, dst: &mut [u8]) -> isize {
        let queue = match self.from_server.lock() {
            Ok(queue) => queue,
            Err(_) => return -2,
        };
        if queue.bytes.is_empty() {
            return if queue.closed { -2 } else { -1 };
        }
        drop(queue);
        match self.from_server.get(dst, None) {
            Poll::Ready(Ok(taken)) => taken as isize,
            _ => -1,
        }
    }

    /// Whether a poll should report the connection readable.
    pub fn client_ready(&self) -> bool {
        let queue = match self.from_server.lock() {
            Ok(queue) => queue,
            Err(_) => return true,
        };
        // EOF is readable too: the loop has to notice the server went away.
        !queue.bytes.is_empty() || queue.closed
    }

    /// Block until at least one byte is available, the pipe closes, or the
    /// timeout expires. Mirrors a blocking socket read well enough for the
    /// client's byte-at-a-time loop without spinning a core.
    pub fn client_wait(&self, timeout_ms: u64) {
        let Ok(queue) = self.from_server.lock() else {
            return;
        };
        if !queue.bytes.is_empty() || queue.closed {
            return;
        }
        let _ = self
            .from_server
            .filled
            .wait_timeout(queue, std::time::Duration::from_millis(timeout_ms));
    }

    pub fn client_close(&self) {
        self.to_server.close();
        self.from_server.close();
    }
}

/// The server's view of the channel, handed to Pumpkin as the connection's
/// read and write halves.
pub struct ServerStream {
    channel: Arc<Channel>,
    /// `AsyncWrite::poll_shutdown` may only be honoured once.
    finished: AtomicBool,
}

impl ServerStream {
    pub fn new(channel: Arc<Channel>) -> Self {
        Self {
            channel,
            finished: AtomicBool::new(false),
        }
    }
}

impl tokio::io::AsyncRead for ServerStream {
    fn poll_read(
        self: std::pin::Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut tokio::io::ReadBuf,
    ) -> Poll<io::Result<()>> {
        let target = buf.initialize_unfilled();
        match self.channel.to_server.get(target, Some(cx)) {
            Poll::Ready(Ok(taken)) => {
                buf.advance(taken);
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(error)) => Poll::Ready(Err(error)),
            Poll::Pending => Poll::Pending,
        }
    }
}

impl tokio::io::AsyncWrite for ServerStream {
    fn poll_write(
        self: std::pin::Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        self.channel.from_server.put(buf, Some(cx))
    }

    fn poll_flush(self: std::pin::Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        // The queue *is* the buffer; there is nothing left to push.
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(
        self: std::pin::Pin<&mut Self>,
        _cx: &mut Context<'_>,
    ) -> Poll<io::Result<()>> {
        if !self.finished.swap(true, Ordering::AcqRel) {
            self.channel.from_server.close();
        }
        Poll::Ready(Ok(()))
    }
}
