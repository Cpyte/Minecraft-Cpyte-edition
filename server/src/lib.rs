//! A C ABI over an embedded Pumpkin server.
//!
//! The Cpyte client links this static library only in the single-player
//! bundle. `pk_host_start` brings a server up inside this process with no
//! listener, and `pk_host_connect` attaches the client to it through an
//! in-memory pipe, so the Login, Configuration and Play exchange runs over two
//! byte queues instead of TCP. The server ticks on the threads tokio and
//! Pumpkin create; nothing here polls, and no packet leaves the process.
//!
//! Every entry point catches panics: a Rust panic unwinding into C is
//! undefined behaviour, and a session that stops is a better outcome than a
//! crashed client.

mod pipe;

use std::num::NonZeroU8;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use pumpkin_config::PumpkinConfig;
use pumpkin_core::data::VanillaData;
use pumpkin_core::net::java::pending::PendingConnection;
use pumpkin_core::net::java::{JavaReadHalf, JavaWriteHalf};
use pumpkin_core::net::PacketRateLimiter;
use pumpkin_core::plugin::loader::PluginLoader;
use pumpkin_core::server::Server;
use pumpkin_core::PumpkinServer;
use pumpkin_util::world_seed::Seed;
use tokio::runtime::{Builder, Runtime};
use tokio::task::JoinHandle;

use crate::pipe::{Channel, ServerStream};

/// Handles are negative so `src/network.c` can tell them from a socket
/// descriptor, and `-1` in particular means "no transport installed".
const FIRST_HANDLE: i64 = -1000;
/// How much the server may have in flight before it waits for the client to
/// read. A view distance's worth of chunk data is a few megabytes.
const OUTGOING_CAPACITY: usize = 64 * 1024 * 1024;
/// The address a socket would have used. An embedded connection has no peer,
/// but the server logs and rate limits by address.
const LOCAL_ADDRESS: std::net::SocketAddr = std::net::SocketAddr::new(
    std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
    25565,
);

struct Host {
    runtime: Runtime,
    server: Arc<Server>,
    /// `PumpkinServer::start` runs here and performs the shutdown saves; the
    /// handle is kept so stopping waits for it instead of dropping the world.
    _startup: JoinHandle<()>,
}

static HOST: Mutex<Option<Host>> = Mutex::new(None);
static LOGGED: OnceLock<()> = OnceLock::new();
static PIPES: Mutex<Vec<(i64, Arc<Channel>)>> = Mutex::new(Vec::new());
static NEXT_HANDLE: AtomicI64 = AtomicI64::new(FIRST_HANDLE);

/// Run one FFI body, turning a panic into a failure code rather than an
/// unwind through the C frame that called it.
fn guarded<T>(name: &str, failure: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or_else(|_| {
        eprintln!("embedded server: {name} panicked");
        failure
    })
}

fn pipe_for(handle: i64) -> Option<Arc<Channel>> {
    let pipes = PIPES.lock().ok()?;
    pipes
        .iter()
        .find(|(id, _)| *id == handle)
        .map(|(_, channel)| channel.clone())
}

fn start_inner(seed: i64, view_distance: i64, tps: i64) -> i64 {
    let mut slot = match HOST.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    if slot.is_some() {
        // One world per process: a second start is the same request.
        return 0;
    }

    let mut config = PumpkinConfig::default();
    // No listener: the only client lives in this process and arrives through
    // pk_host_connect instead of an accept.
    config.advanced.networking.java.enabled = false;
    // Local accounts only, so neither online-mode authentication nor RSA
    // encryption is part of the login sequence this client then runs.
    config.advanced.networking.java.online_mode = false;
    config.advanced.networking.java.encryption = false;
    // The client owns the terminal, including its own command line. Pumpkin's
    // console must not take stdin even when it is a TTY.
    config.advanced.commands.use_console = false;
    config.advanced.commands.use_tty = false;
    config.basic.seed = Seed(seed as u64);
    config.basic.tps = if tps > 0 { tps as f32 } else { 20.0 };
    if let Some(distance) = NonZeroU8::new(view_distance.clamp(2, 32) as u8) {
        config.advanced.networking.java.view_distance = distance;
    }

    if LOGGED.set(()).is_ok() {
        // Setting the global subscriber twice panics, so it happens once.
        pumpkin_core::init_logger(&config.advanced);
    }

    let runtime = match Builder::new_multi_thread().worker_threads(4).enable_all().build() {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("embedded server: cannot build the runtime: {error}");
            return -2;
        }
    };

    let PumpkinConfig {
        basic,
        advanced,
        telemetry,
    } = config;
    let loaders: Vec<Arc<dyn PluginLoader>> = Vec::new();
    let pumpkin = match runtime.block_on(async move {
        PumpkinServer::new(
            basic,
            advanced,
            telemetry,
            VanillaData::load(),
            loaders,
            false,
        )
        .await
    }) {
        Ok(pumpkin) => pumpkin,
        Err(error) => {
            eprintln!("embedded server: cannot boot: {error}");
            return -3;
        }
    };

    let server = pumpkin.server.clone();
    let startup = runtime.spawn(async move {
        // With no listener this task waits on the stop token and then saves
        // every player and world, which is what an embedded server wants.
        pumpkin.start().await;
    });
    *slot = Some(Host {
        runtime,
        server,
        _startup: startup,
    });
    0
}

fn connect_inner() -> i64 {
    let mut slot = match HOST.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    let host = match slot.as_mut() {
        Some(host) => host,
        None => {
            eprintln!("embedded server: connected before it was started");
            return -1;
        }
    };

    let channel = Channel::new(OUTGOING_CAPACITY);
    let handle = NEXT_HANDLE.fetch_sub(1, Ordering::AcqRel);
    let read_half: JavaReadHalf = Box::new(ServerStream::new(channel.clone()));
    let write_half: JavaWriteHalf = Box::new(ServerStream::new(channel.clone()));
    let server = host.server.clone();
    let limiter =
        PacketRateLimiter::from_config(&server.advanced_config.networking.java.packet_limiter);
    let pending = PendingConnection::from_transport(
        read_half,
        write_half,
        LOCAL_ADDRESS,
        handle as u64,
        limiter,
        Arc::downgrade(&server),
    );

    match PIPES.lock() {
        Ok(mut pipes) => pipes.push((handle, channel)),
        Err(_) => return -1,
    }
    host.runtime.spawn(async move {
        // Handshake, login, configuration and play, then the player's save on
        // the way out - the same path a networked client takes.
        pumpkin_core::serve_java_connection(server, pending).await;
    });
    handle
}

fn stop_inner() -> i64 {
    if let Ok(mut pipes) = PIPES.lock() {
        for (_, channel) in pipes.iter() {
            // EOF on both halves, which ends the serving task the way a
            // closed socket would.
            channel.client_close();
        }
        pipes.clear();
    }
    let mut slot = match HOST.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    let host = match slot.take() {
        Some(host) => host,
        None => return 0,
    };
    pumpkin_core::stop_server();
    let Host {
        runtime,
        _startup,
        server: _,
    } = host;
    // Waiting for the start task is what runs the shutdown saves.
    runtime.block_on(async {
        let _ = _startup.await;
    });
    runtime.shutdown_timeout(Duration::from_secs(5));
    0
}

/// Bring the embedded server up. `seed` is the world seed, `view_distance` the
/// maximum the client may ask for, `tps` the tick rate (0 uses 20). Returns 0
/// on success; a second call after a successful start does nothing and
/// succeeds.
///
/// # Safety
/// None: no pointers cross this boundary.
#[no_mangle]
pub extern "C" fn pk_host_start(seed: i64, view_distance: i64, tps: i64) -> i64 {
    guarded("pk_host_start", -9, || start_inner(seed, view_distance, tps))
}

/// Attach the client to the embedded server and return the negative handle the
/// transport dispatches on. The player's name is not passed: it arrives in the
/// client's own Login Start packet, and the offline UUID is derived from it.
///
/// # Safety
/// None: no pointers cross this boundary.
#[no_mangle]
pub extern "C" fn pk_host_connect() -> i64 {
    guarded("pk_host_connect", -9, || connect_inner())
}

/// Hand bytes to the server. Returns how many were taken, which for the
/// unbounded client-to-server direction is all of them, or a negative failure.
///
/// # Safety
/// `data` must address `length` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn pk_pipe_write(handle: i64, data: *const u8, length: i64) -> i64 {
    guarded("pk_pipe_write", -9, || {
        let channel = match pipe_for(handle) {
            Some(channel) => channel,
            None => return -1,
        };
        if data.is_null() || length < 0 {
            return -1;
        }
        if length == 0 {
            return 0;
        }
        let bytes = slice::from_raw_parts(data, length as usize);
        channel.client_write(bytes) as i64
    })
}

/// Copy bytes the server produced into `out`. Returns the count, `-1` when
/// nothing has arrived yet, or `-2` once the server has closed and the queue
/// has drained.
///
/// # Safety
/// `out` must address `capacity` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn pk_pipe_read(handle: i64, out: *mut u8, capacity: i64) -> i64 {
    guarded("pk_pipe_read", -9, || {
        let channel = match pipe_for(handle) {
            Some(channel) => channel,
            None => return -2,
        };
        if out.is_null() || capacity <= 0 {
            return -1;
        }
        let space = slice::from_raw_parts_mut(out, capacity as usize);
        channel.client_read(space) as i64
    })
}

/// Whether bytes are waiting or the pipe is closed, for the poll the Play loop
/// performs before it reads.
///
/// # Safety
/// None: no pointers cross this boundary.
#[no_mangle]
pub extern "C" fn pk_pipe_ready(handle: i64) -> i64 {
    guarded("pk_pipe_ready", 0, || match pipe_for(handle) {
        Some(channel) => channel.client_ready() as i64,
        None => 1,
    })
}

/// Wait up to `timeout_ms` for the server to produce a byte. Without this the
/// client's byte-at-a-time read would have to spin.
///
/// # Safety
/// None: no pointers cross this boundary.
#[no_mangle]
pub extern "C" fn pk_pipe_wait(handle: i64, timeout_ms: i64) -> i64 {
    guarded("pk_pipe_wait", -1, || match pipe_for(handle) {
        Some(channel) => {
            channel.client_wait(timeout_ms.max(0) as u64);
            0
        }
        None => -1,
    })
}

/// Close one pipe, so the server sees the client disconnect and saves it. The
/// handle is retired.
///
/// # Safety
/// None: no pointers cross this boundary.
#[no_mangle]
pub extern "C" fn pk_pipe_close(handle: i64) -> i64 {
    guarded("pk_pipe_close", -1, || {
        if let Ok(mut pipes) = PIPES.lock() {
            if let Some(index) = pipes.iter().position(|(id, _)| *id == handle) {
                let (_, channel) = pipes.remove(index);
                channel.client_close();
                return 0;
            }
        }
        -1
    })
}

/// Stop the embedded server: close every pipe, ask the server to stop, wait
/// for its shutdown saves and then end the runtime.
///
/// # Safety
/// None: no pointers cross this boundary.
#[no_mangle]
pub extern "C" fn pk_host_stop() -> i64 {
    guarded("pk_host_stop", -9, || stop_inner())
}
