# Perry for Termux

A [Perry](https://github.com/PerryTS/perry) TypeScript compiler that runs
natively on Termux — no proot, no chroot. It compiles `.ts` to a
self-contained aarch64 ELF executable with no runtime dependencies.

```
$ perry --version
perry 0.5.1220
$ perry app.ts -o app && ./app
```

Perry does not publish a Termux or Android-host build. This repository is the
packaging that makes the existing prebuilt compiler usable there. It is not
affiliated with upstream.

## Install

**From a release** — download the tarball attached to the
[latest release](https://github.com/BAIGAOa/perry-termux/releases/latest),
then install:

```bash
curl -LO https://github.com/BAIGAOa/perry-termux/releases/latest/download/perry-0.5.1220-aarch64.tar.gz
tar xzf perry-0.5.1220-aarch64.tar.gz
cd perry-termux && bash install.sh
perry --version
```

**From source** — the tarball is exactly what `build.sh` produces, so you can
rebuild it yourself:

```bash
git clone https://github.com/BAIGAOa/perry-termux
cd perry-termux
./build.sh            # downloads ~110 MB of pinned upstream artifacts
bash install.sh
```

`pkg install clang lld zstd binutils` is required for the build and for
compiling; `curl` for the download.

`install.sh` only creates the symlink `$PREFIX/bin/perry`. The package is
relocatable — the launcher finds the rest relative to itself, so it can live
anywhere. Undo with `bash install.sh --uninstall`.

## How it works

Neither off-the-shelf Perry binary runs on Termux as shipped:

- **The glibc builds** (GitHub releases) need a glibc dynamic loader, which
  Android does not have.
- **The musl builds** do run — the compiler is fully static — but Perry's
  runtime archives are also built against musl, while Termux's own `cc`
  targets bionic. The link step then fails on musl-only symbols: `bcmp`,
  `__errno_location`, `__xpg_strerror_r`, and the `_Unwind_*` family.

So the package pairs the static musl compiler with a musl linking
environment:

| Path | What it is |
|---|---|
| `bin/perry.real` | Upstream static musl aarch64 compiler, unmodified |
| `bin/perry` | Launcher — puts `bin/` first on `PATH`, ensures `TMPDIR` exists |
| `bin/cc` | Link shim that points clang at the musl sysroot instead of bionic |
| `lib/*.a` | Perry's runtime archives, pre-decompressed |
| `lib/libperry_ext_http_stubs.a` | Symbols upstream does not ship for musl (see below) |
| `musl-sysroot/` | Alpine musl libc, crt objects, and static OpenSSL/zlib/zstd |

Two details are load-bearing:

**`-static` is not optional.** Termux has no `/lib/ld-musl-aarch64.so.1`, so a
dynamically linked musl binary would not start. Output executables are fully
static — `readelf -d app` reports no `NEEDED` entries at all.

**The shim is not installed globally.** `bin/cc` lives inside the package's
private `bin/`, which the launcher prepends to `PATH` for the compiler process
only. Installing it as a global `cc` would shadow Termux's real compiler.

## Known limitation: no networking

`node:http`, `node:https`, `node:net`, `node:tls`, `node:ws` and `fetch()` do
not work. Programs using them compile and run, but the request fails:

```
Error: Fetch error: error sending request for url (https://example.com/)
```

This fails for bare IPs too, so it is not a name-resolution problem — the
implementation is genuinely absent.

The cause is a missing archive. Perry splits several surfaces into
`perry-ext-*` crates built as separate `libperry_ext_*.a` staticlibs that
upstream stages next to the compiler. The npm musl package does not include
them, and upstream stopped publishing musl packages after 0.5.1220, so there
is no musl build to take `libperry_ext_http.a` from.

That would normally be fatal far beyond networking: importing `node:crypto`,
`node:events` or `node:zlib` pulls the same stdlib codegen units, which
reference fourteen `js_ext_http_*` symbols, so **the link dies on an
undefined `js_ext_http_agent_is_handle` even though the program never touches
HTTP**. `src/ext_http_stubs.c` defines those fourteen symbols as
zero-returning stubs — `false` / `NULL` / `+0`, all falsy, so the event loop's
"pending HTTP work?" probe answers no and control flow stays on the
non-networking paths — and `bin/cc` appends the resulting archive to every
link, where the linker pulls it only if something still has those symbols
undefined.

The stubs must not abort: `js_http_has_pending` is consulted by the event loop
of every program linked against the full stdlib.

## What works

Classes, generics, async/await, closures, `Map`/`Set`, `JSON`, regex, and
these builtins, verified on-device:

| Module | Verified |
|---|---|
| `node:fs`, `node:path`, `node:os`, `node:process` | read/write, joins, platform info |
| `node:crypto` | `createHash`, `randomBytes` |
| `node:zlib` | `gzipSync` / `gunzipSync` |
| `node:events` | `EventEmitter` |
| `node:buffer`, `node:util`, `node:url`, `node:stream`, `node:assert` | import and load |

## Limitations that are inherent

- **Version 0.5.1220**, the last release published to npm with a musl
  artifact. Upstream's current releases are glibc-only, so newer versions are
  out of reach without building Perry from source — which needs LLVM 22 (Termux
  has 21) and Rust nightly.
- **aarch64 only.** The prebuilt binary is aarch64; other Termux
  architectures are not supported by this package.

## Layout

```
build.sh              assembles bin/, lib/ and musl-sysroot/ from pinned URLs
install.sh            symlinks $PREFIX/bin/perry
src/perry             launcher
src/cc                clang/musl link shim
src/ext_http_stubs.c  the fourteen missing symbols
THIRD_PARTY.md        licenses of everything the release redistributes
```

`bin/`, `lib/` and `musl-sysroot/` are generated and gitignored — a clone has
to run `build.sh` first.
