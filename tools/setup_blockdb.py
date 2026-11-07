#!/usr/bin/env python3
"""Discover a local Minecraft installation and build Vortex's block database.

The vanilla block-state report is produced by the data generator that ships in
the Minecraft jar. This tool finds an installation on the machine, locates a
jar for the client's protocol, runs the generator, and feeds the resulting
reports/blocks.json + reports/registries.json to tools/gen_blockdb.py. The
output is generated/blockdb.bin.

A bundled server jar is self-contained:

    java -DbundlerMainClass=net.minecraft.data.Main -jar server.jar \
         --reports --output <scratch>

A client jar (official launcher, Prism, MultiMC, ...) has the generator class
at its root but needs the version's libraries on the classpath, taken from the
sibling version JSON next to the jar:

    java -cp <client.jar><pathsep><libraries...> net.minecraft.data.Main \
         --reports --output <scratch>

Nothing is downloaded by default. Pass --download-server to fetch a bundled
server jar from Mojang's version manifest when the installation has no usable
jar. The generated reports and database stay below generated/ (git-ignored):
they are Mojang-derived data and must not be committed.

Cross-platform: official launcher, PrismLauncher, MultiMC, ATLauncher and
Flatpak paths on macOS, Windows and Linux are scanned. Use --root or
MINECRAFT_HOME to add a location, or --server-jar to bypass discovery.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "generated" / "blockdb.bin"
DEFAULT_REPORTS = REPO_ROOT / "generated" / "reports"
SCRATCH = REPO_ROOT / "generated" / ".blockdb-work"
CACHE = REPO_ROOT / "generated" / ".cache"

TARGET_PROTOCOL = 777
TARGET_VERSION = "26.3"
MANIFEST_URL = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
DATA_GENERATOR_CLASS = "net/minecraft/data/Main.class"
DATA_GENERATOR_MAIN = "net.minecraft.data.Main"

SKIP_DIRS = {
    "assets",
    "libraries",
    "logs",
    "mods",
    "resourcepacks",
    "saves",
    "screenshots",
    "shaderpacks",
    "crash-reports",
    "runtime",
    "natives",
    "downloads",
    "webcache",
    "server-resource-packs",
}


@dataclass
class JarInfo:
    path: Path
    version_id: str | None = None
    protocol: int | None = None
    has_generator: bool = False
    bundler: bool = False
    client_generator: bool = False
    root: Path | None = None
    notes: list[str] = field(default_factory=list)

    @property
    def label(self) -> str:
        version = self.version_id or "unknown version"
        protocol = f"protocol {self.protocol}" if self.protocol is not None else "protocol unknown"
        if self.bundler:
            kind = "server bundler"
        elif self.client_generator:
            kind = "client jar"
        else:
            kind = "other"
        return f"{self.path} [{version}, {protocol}, {kind}]"


# Trees the launcher keeps next to versions/ and libraries/ that never hold a
# runnable jar we care about.
def find_install_root(path: Path) -> Path | None:
    """The directory holding the launcher's libraries/ folder, if any."""
    for depth, directory in enumerate(path.parents):
        if depth > 8:
            break
        if (directory / "libraries").is_dir():
            return directory
    return None


def _version_from_json(raw: bytes) -> tuple[str | None, int | None]:
    try:
        data = json.loads(raw.decode("utf-8", "replace"))
    except (ValueError, UnicodeDecodeError):
        return None, None
    version_id = data.get("id") or data.get("name")
    protocol = data.get("protocol_version")
    try:
        protocol = int(protocol) if protocol is not None else None
    except (TypeError, ValueError):
        protocol = None
    return (str(version_id) if version_id else None, protocol)


def _read_nested_jar(zf: zipfile.ZipFile, entry: str) -> zipfile.ZipFile | None:
    try:
        raw = zf.read(entry)
    except (KeyError, OSError, zipfile.BadZipFile):
        return None
    try:
        return zipfile.ZipFile(io.BytesIO(raw))
    except zipfile.BadZipFile:
        return None


def inspect_jar(path: Path, root: Path | None = None) -> JarInfo | None:
    """Read version metadata and detect the bundled data generator."""
    info = JarInfo(path=path, root=root)
    try:
        with zipfile.ZipFile(path) as zf:
            names = set(zf.namelist())
            if "version.json" in names:
                info.version_id, info.protocol = _version_from_json(zf.read("version.json"))
            if DATA_GENERATOR_CLASS in names:
                info.has_generator = True
                info.client_generator = True
            if "META-INF/main-class" in names:
                try:
                    main_class = zf.read("META-INF/main-class").decode("utf-8", "replace").strip()
                except (KeyError, OSError):
                    main_class = ""
                if main_class == DATA_GENERATOR_MAIN:
                    info.has_generator = True
            if "META-INF/versions.list" in names:
                info.bundler = True
                try:
                    listing = zf.read("META-INF/versions.list").decode("utf-8", "replace")
                except (KeyError, OSError):
                    listing = ""
                for line in listing.splitlines():
                    fields = line.split("\t")
                    if len(fields) < 3:
                        continue
                    nested = _read_nested_jar(zf, fields[2].strip())
                    if nested is None:
                        continue
                    with nested:
                        nested_names = set(nested.namelist())
                        if DATA_GENERATOR_CLASS in nested_names:
                            info.has_generator = True
                        if info.version_id is None and "version.json" in nested_names:
                            info.version_id, info.protocol = _version_from_json(
                                nested.read("version.json")
                            )
                    break
                # A server bundler always carries the integrated server and its
                # data generator; keep it a candidate even if the nested jar
                # could not be inspected.
                info.has_generator = True
    except (OSError, zipfile.BadZipFile):
        return None
    if info.version_id is None and not info.has_generator:
        return None
    return info


def launcher_roots() -> list[Path]:
    roots: list[Path] = []
    override = os.environ.get("MINECRAFT_HOME")
    if override:
        roots.append(Path(override).expanduser())
    home = Path.home()
    if sys.platform == "darwin":
        support = home / "Library" / "Application Support"
        roots += [
            support / "minecraft",
            support / "PrismLauncher" / "instances",
            support / "MultiMC" / "instances",
            support / "ATLauncher" / "instances",
        ]
    elif os.name == "nt":
        appdata = Path(os.environ.get("APPDATA", home / "AppData" / "Roaming"))
        local = Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local"))
        roots += [
            appdata / ".minecraft",
            appdata / "PrismLauncher" / "instances",
            appdata / "MultiMC" / "instances",
            appdata / "ATLauncher" / "instances",
            local / "Programs" / "PrismLauncher" / "instances",
        ]
    else:
        roots += [
            home / ".minecraft",
            home / ".local" / "share" / "PrismLauncher" / "instances",
            home / ".local" / "share" / "multimc" / "instances",
            home / ".var" / "app" / "org.prismlauncher.PrismLauncher"
            / "data" / "PrismLauncher" / "instances",
        ]
    seen: set[Path] = set()
    unique: list[Path] = []
    for root in roots:
        try:
            resolved = root.resolve()
        except OSError:
            continue
        if resolved not in seen:
            seen.add(resolved)
            unique.append(root)
    return unique


def iter_jars(root: Path):
    if not root.is_dir():
        return
    direct = root / "server.jar"
    if direct.is_file():
        yield direct
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)
        try:
            depth = len(current.relative_to(root).parts)
        except ValueError:
            depth = 0
        if depth >= 7:
            dirnames[:] = []
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIRS]
        in_versions = "versions" in current.parts
        for name in filenames:
            lower = name.lower()
            if not lower.endswith(".jar"):
                continue
            if (
                lower == "server.jar"
                or lower.startswith("minecraft_server")
                or in_versions
            ):
                yield current / name


def discover(roots: list[Path], extra_jars: list[Path]) -> list[JarInfo]:
    paths: list[Path] = []
    for jar in extra_jars:
        if jar.is_file():
            paths.append(jar)
    for root in roots:
        paths.extend(iter_jars(root))
    seen: set[Path] = set()
    found: list[JarInfo] = []
    for path in paths:
        try:
            resolved = path.resolve()
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        info = inspect_jar(path, find_install_root(path))
        if info is not None:
            found.append(info)
    return found


def choose(candidates: list[JarInfo], protocol: int, allow_mismatch: bool) -> JarInfo:
    usable = [c for c in candidates if c.has_generator]
    if not usable:
        raise SystemExit(
            "No Minecraft installation with the data generator was found.\n"
            "Install or run a vanilla client/server jar, pass --server-jar PATH, "
            "or use --download-server."
        )
    exact = [c for c in usable if c.protocol == protocol]
    if exact:
        return max(exact, key=lambda c: c.path.stat().st_mtime)
    known = [c for c in usable if c.protocol is not None]
    if known and not allow_mismatch:
        listing = "\n".join(f"  {c.label}" for c in known)
        raise SystemExit(
            f"No Minecraft jar matches protocol {protocol}.\n{listing}\n"
            "The packet tables and block states are version specific. Pass "
            "--allow-version-mismatch to build from a different version anyway."
        )
    return max(usable, key=lambda c: c.path.stat().st_mtime)


def find_java(explicit: str | None) -> str:
    if explicit:
        return explicit
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        candidate = Path(java_home) / "bin" / ("java.exe" if os.name == "nt" else "java")
        if candidate.is_file():
            return str(candidate)
    found = shutil.which("java")
    if found:
        return found
    raise SystemExit(
        "Java was not found. Install a JDK/JRE or pass --java PATH "
        "(the data generator is a Java program)."
    )


# ---- client jar classpath ----------------------------------------------------

def _maven_path(name: str) -> Path | None:
    """group:artifact:version[:classifier] -> libraries/ relative jar path."""
    fields = name.split(":")
    if len(fields) < 3:
        return None
    group, artifact, version = fields[0], fields[1], fields[2]
    classifier = f"-{fields[3]}" if len(fields) > 3 and fields[3] else ""
    file = f"{artifact}-{version}{classifier}.jar"
    return Path(*group.split(".")) / artifact / version / file


def _version_json(info: JarInfo) -> Path | None:
    sibling = info.path.with_suffix(".json")
    if sibling.is_file():
        return sibling
    if info.root is not None and info.version_id:
        candidate = info.root / "versions" / info.version_id / f"{info.version_id}.json"
        if candidate.is_file():
            return candidate
        matches = list((info.root / "versions").glob(f"*/{info.version_id}.json"))
        if matches:
            return matches[0]
    return None


def _collect_library_jars(json_path: Path, lib_root: Path, jars: list[Path],
                          seen: set[str], depth: int = 0) -> None:
    if depth > 4 or not json_path.is_file():
        return
    try:
        data = json.loads(json_path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return
    parent = data.get("inheritsFrom")
    if parent and parent not in seen:
        seen.add(parent)
        parent_json = lib_root.parent / "versions" / str(parent) / f"{parent}.json"
        _collect_library_jars(parent_json, lib_root, jars, seen, depth + 1)
    for library in data.get("libraries", []):
        artifact = (library.get("downloads") or {}).get("artifact")
        relative = artifact.get("path") if isinstance(artifact, dict) else None
        if not relative:
            maven = _maven_path(str(library.get("name", "")))
            relative = str(maven) if maven is not None else None
        if not relative:
            continue
        path = lib_root / relative
        # Entries for other operating systems are simply absent on this one.
        if path.is_file() and str(path) not in seen:
            seen.add(str(path))
            jars.append(path)


def library_jars(info: JarInfo) -> list[Path]:
    """The version's libraries, resolved from the JSON next to the jar."""
    if info.root is None:
        return []
    lib_root = info.root / "libraries"
    if not lib_root.is_dir():
        return []
    json_path = _version_json(info)
    if json_path is None:
        return []
    jars: list[Path] = []
    seen: set[str] = {str(info.path)}
    _collect_library_jars(json_path, lib_root, jars, seen)
    return jars


def reports_ready(directory: Path) -> bool:
    return (directory / "blocks.json").is_file() and (directory / "registries.json").is_file()


def reports_protocol(directory: Path) -> int | None:
    try:
        meta = json.loads((directory / "meta.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    protocol = meta.get("protocol")
    try:
        return int(protocol) if protocol is not None else None
    except (TypeError, ValueError):
        return None


def locate_reports(explicit: Path | None, protocol: int,
                   allow_mismatch: bool) -> Path | None:
    if explicit is not None:
        return explicit if reports_ready(explicit) else None
    for candidate in (DEFAULT_REPORTS, REPO_ROOT / "generated"):
        if not reports_ready(candidate):
            continue
        cached = reports_protocol(candidate)
        if cached is not None and cached != protocol and not allow_mismatch:
            print(
                f"ignoring cached reports from protocol {cached} "
                f"(the client targets {protocol})"
            )
            continue
        return candidate
    return None


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": "Vortex-blockdb/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def download_server(version_id: str, protocol: int | None) -> Path:
    print(f"fetching Mojang version manifest for {version_id} ...")
    manifest = fetch_json(MANIFEST_URL)
    entry = next((v for v in manifest.get("versions", []) if v.get("id") == version_id), None)
    if entry is None:
        raise SystemExit(f"version {version_id!r} is not in Mojang's manifest")
    version = fetch_json(entry["url"])
    server = version.get("downloads", {}).get("server")
    if not server or not server.get("url"):
        raise SystemExit(f"version {version_id} has no server download")
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / f"server-{version_id}.jar"
    if target.is_file():
        print(f"using cached {target}")
        return target
    print(f"downloading {server['url']}")
    with urllib.request.urlopen(server["url"], timeout=120) as response:
        data = response.read()
    digest = hashlib.sha1(data).hexdigest()
    if server.get("sha1") and digest != server["sha1"]:
        raise SystemExit("server jar checksum mismatch; refusing to use it")
    target.write_bytes(data)
    print(f"saved {target} ({len(data)} bytes, sha1 {digest})")
    return target


def generator_command(info: JarInfo, java: str) -> list[str]:
    jar = info.path.resolve()
    tail = ["--reports", "--output", str(SCRATCH.resolve())]
    if info.bundler:
        return [java, f"-DbundlerMainClass={DATA_GENERATOR_MAIN}", "-jar", str(jar), *tail]
    libraries = library_jars(info)
    if not libraries:
        raise SystemExit(
            f"{jar} is a client jar, but its launcher libraries were not found.\n"
            "Pass --root with the installation directory, pass --server-jar, "
            "or use --download-server."
        )
    classpath = os.pathsep.join(
        [str(jar), *(str(path.resolve()) for path in libraries)]
    )
    return [java, "-cp", classpath, DATA_GENERATOR_MAIN, *tail]


def run_generator_process(command: list[str]) -> subprocess.CompletedProcess:
    # Windows caps the command line near 32 KiB and a client classpath can get
    # close; an argument file keeps Java from hitting that limit.
    if os.name == "nt" and len(subprocess.list2cmdline(command)) > 28000:
        argfile = SCRATCH / "generator.args"
        lines = []
        for argument in command[1:]:
            # Forward slashes avoid Java's backslash escaping inside quotes.
            argument = argument.replace("\\", "/")
            if any(character.isspace() for character in argument):
                argument = f'"{argument}"'
            lines.append(argument)
        argfile.write_text("\n".join(lines) + "\n", encoding="utf-8")
        command = [command[0], f"@{argfile}"]
    return subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)


def run_generator(info: JarInfo, java: str, keep_reports: bool) -> Path:
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.mkdir(parents=True)
    command = generator_command(info, java)
    mode = "bundled server" if info.bundler else "client classpath"
    print(f"running the vanilla data generator from {info.path.name} ({mode}) ...")
    result = run_generator_process(command)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-4000:])
        sys.stderr.write(result.stderr[-4000:])
        raise SystemExit(f"data generator failed with exit code {result.returncode}")
    source = SCRATCH / "reports"
    if not reports_ready(source):
        source = SCRATCH
    if not reports_ready(source):
        raise SystemExit("the data generator produced no blocks.json/registries.json")
    if keep_reports:
        DEFAULT_REPORTS.mkdir(parents=True, exist_ok=True)
        for name in ("blocks.json", "registries.json"):
            shutil.copy2(source / name, DEFAULT_REPORTS / name)
            print(f"kept {DEFAULT_REPORTS / name}")
        meta = {
            "version": info.version_id,
            "protocol": info.protocol,
            "source": info.path.name,
        }
        (DEFAULT_REPORTS / "meta.json").write_text(
            json.dumps(meta, indent=2) + "\n", encoding="utf-8"
        )
    return source


def build_from_reports(reports: Path, out: Path) -> tuple[int, int]:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import gen_blockdb

    records, state_count = gen_blockdb.load(
        reports / "blocks.json", reports / "registries.json"
    )
    gen_blockdb.write_binary(records, state_count, out)
    return len(records), state_count


def verify_binary(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 20 or data[:8] != b"VBLKDB01":
        raise SystemExit(f"{path} is not a Vortex block database")
    states, blocks, name_bytes = struct.unpack_from("<III", data, 8)
    if len(data) != 20 + blocks * 20 + name_bytes:
        raise SystemExit(f"{path} has an inconsistent size")
    expected = 0
    for index in range(blocks):
        _protocol, first, count, _flags, offset, length, _reserved = struct.unpack_from(
            "<IIHHIHH", data, 20 + index * 20
        )
        if count == 0 or first != expected:
            raise SystemExit(f"{path}: record {index} does not tile the state space")
        if offset + length > name_bytes:
            raise SystemExit(f"{path}: record {index} name is out of bounds")
        expected += count
    if expected != states:
        raise SystemExit(f"{path}: state count mismatch")
    return blocks, states


def print_candidates(candidates: list[JarInfo]) -> None:
    if not candidates:
        print("no Minecraft jars found")
        return
    for info in sorted(candidates, key=lambda c: str(c.path)):
        print(f"  {info.label}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", action="append", type=Path, default=[],
                        help="extra installation/instances directory (repeatable)")
    parser.add_argument("--server-jar", type=Path,
                        help="use this server jar instead of discovery")
    parser.add_argument("--reports", type=Path,
                        help="existing directory containing blocks.json and registries.json")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--protocol", type=int, default=TARGET_PROTOCOL)
    parser.add_argument("--version", default=TARGET_VERSION,
                        help="version to download with --download-server")
    parser.add_argument("--download-server", action="store_true",
                        help="download the matching server jar from Mojang")
    parser.add_argument("--java", help="java executable")
    parser.add_argument("--force", action="store_true", help="rebuild an existing database")
    parser.add_argument("--discard-reports", action="store_true",
                        help="do not keep reports under generated/reports")
    parser.add_argument("--list", action="store_true", help="list discovered jars and exit")
    parser.add_argument("--dry-run", action="store_true",
                        help="discover and print the plan without running anything")
    parser.add_argument("--allow-version-mismatch", action="store_true",
                        help="accept a server jar whose protocol differs from the client")
    parser.add_argument("--auto", action="store_true",
                        help="build only if the database is missing; never fail or download")
    args = parser.parse_args()

    out = args.out if args.out.is_absolute() else (REPO_ROOT / args.out)

    if out.exists() and not args.force and not args.list and not args.dry_run:
        blocks, states = verify_binary(out)
        print(f"{out} already exists ({blocks} blocks, {states} states); use --force to rebuild")
        return 0

    explicit_jars: list[Path] = []
    if args.server_jar is not None:
        explicit_jars.append(args.server_jar)
    roots = launcher_roots()
    roots.extend(args.root)
    candidates = discover(roots, explicit_jars)
    if args.list:
        print_candidates(candidates)
        return 0

    reports = locate_reports(args.reports, args.protocol, args.allow_version_mismatch)
    if reports is not None and args.reports is None and not args.force:
        # Cached reports are enough; no Java run is needed.
        blocks, states = build_from_reports(reports, out)
        print(
            f"wrote {out}: {blocks} blocks, {states} states, "
            f"{out.stat().st_size} bytes (from {reports})"
        )
        return 0

    server: JarInfo | None = None
    if explicit_jars:
        info = inspect_jar(explicit_jars[0], find_install_root(explicit_jars[0]))
        if info is None or not info.has_generator:
            raise SystemExit(f"{explicit_jars[0]} does not contain the vanilla data generator")
        server = info
    elif reports is None:
        try:
            server = choose(candidates, args.protocol, args.allow_version_mismatch)
        except SystemExit as error:
            if args.auto:
                print(str(error))
                print("continuing without a block database; the mesher will use its fallback")
                return 0
            if not args.download_server:
                raise
            server = None
        if server is not None and server.protocol is not None and server.protocol != args.protocol:
            if not args.allow_version_mismatch:
                message = (
                    f"server jar {server.path} is protocol {server.protocol}, "
                    f"but the client targets {args.protocol}"
                )
                if args.auto:
                    print(message + "; skipping block database")
                    return 0
                raise SystemExit(message + " (pass --allow-version-mismatch to override)")

    if reports is not None:
        source = reports
    elif server is not None:
        if args.dry_run:
            print(f"would run the data generator with {server.label}")
            print(f"would write {out}")
            return 0
        java = find_java(args.java)
        source = run_generator(server, java, not args.discard_reports)
    elif args.download_server:
        jar = download_server(args.version, args.protocol)
        info = inspect_jar(jar)
        if info is None or not info.has_generator:
            raise SystemExit("the downloaded jar does not contain the data generator")
        if info.protocol is not None and info.protocol != args.protocol and not args.allow_version_mismatch:
            raise SystemExit(
                f"downloaded {args.version} is protocol {info.protocol}, "
                f"expected {args.protocol}; pass --allow-version-mismatch to override"
            )
        if args.dry_run:
            print(f"would run the data generator with {info.label}")
            return 0
        java = find_java(args.java)
        source = run_generator(info, java, not args.discard_reports)
    else:
        raise SystemExit("no reports or server jar available")

    if args.dry_run:
        print(f"would build {out} from {source}")
        return 0

    blocks, states = build_from_reports(source, out)
    blocks, states = verify_binary(out)
    print(
        f"wrote {out}: {blocks} blocks, {states} states, "
        f"{out.stat().st_size} bytes"
    )
    if source != DEFAULT_REPORTS:
        print("tip: keep reports under generated/reports to rebuild without Java")
    return 0


if __name__ == "__main__":
    sys.exit(main())
