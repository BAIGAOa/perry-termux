# Third-party components

The release tarball redistributes the components below. They are unmodified
upstream artifacts; this repository only supplies the scripts that fetch,
assemble and install them.

## Perry — the compiler

`bin/perry.real` is the unmodified `@perryts/perry-linux-arm64-musl` binary.

- Project: https://github.com/PerryTS/perry
- Version: 0.5.1220
- License: MIT

## Alpine Linux packages — the linker sysroot

`musl-sysroot/` is assembled from these aarch64 packages of the Alpine
`v3.23` release branch (`https://dl-cdn.alpinelinux.org/alpine/v3.23/main/aarch64/`).
Only `lib/`, `usr/lib/` and `usr/include/` members are extracted: gcc's driver
binaries, `usr/libexec` and its plugin directory are omitted.

| Package | Version | Provides | License |
|---|---|---|---|
| `musl` | 1.2.5-r23 | `lib/ld-musl-aarch64.so.1` | MIT |
| `musl-dev` | 1.2.5-r23 | `libc.a`, crt objects, headers | MIT |
| `gcc` | 15.2.0-r2 | `crtbeginT.o`, `crtend.o`, `libgcc.a`, `libgcc_eh.a` | GPL-3.0-or-later **with GCC Runtime Library Exception 3.1** |
| `openssl-libs-static` | 3.5.8-r0 | `libssl.a`, `libcrypto.a` | Apache-2.0 |
| `zlib-static` | 1.3.2-r0 | `libz.a` | Zlib |
| `zstd-static` | 1.5.7-r2 | `libzstd.a` | BSD-3-Clause |

The GCC Runtime Library Exception is what makes redistribution of the crt
objects and `libgcc.a` in a package that is not itself GPL permissible: it
explicitly allows linking those files into independent programs.

`libgcc.a` is the one component that is not always taken from Alpine. Some
builds of Alpine's `gcc` package omit it; `build.sh` then substitutes
Termux's `libclang_rt.builtins-aarch64-android.a`, which is the same set of
aarch64 compiler support routines and is Apache-2.0 WITH LLVM-exception. The
build log states which one was used.

Full license texts ship with the upstream sources; consult each project for
the authoritative text.
