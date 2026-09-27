#!/data/data/com.termux/files/usr/bin/bash
#
# Assemble the Perry-for-Termux package tree from pinned upstream artifacts.
#
# Produces, under this directory:
#   bin/perry.real   the upstream static musl aarch64 compiler
#   bin/perry        launcher (from src/perry)
#   bin/cc           musl link shim (from src/cc)
#   lib/*.a          Perry's runtime archives, decompressed
#   lib/libperry_ext_http_stubs.a   symbols upstream does not ship for musl
#   musl-sysroot/    Alpine musl libc, crt objects and static libs
#
# Nothing here is architecture-specific beyond the aarch64 pins below; every
# download URL carries an exact version so a rebuild is byte-reproducible.
#
# Usage:
#   ./build.sh              build (downloads are cached under .build/)
#   ./build.sh --clean      remove bin/, lib/, musl-sysroot/ first
#   ./build.sh --fetch-only download without assembling
set -euo pipefail

PERRY_VERSION=0.5.1220

# Alpine release branch, not edge: edge package versions are replaced in place
# when superseded, so their URLs rot. A release branch keeps its URLs.
ALPINE_BRANCH=v3.23
MUSL_VERSION=1.2.5-r23
GCC_VERSION=15.2.0-r2
OPENSSL_STATIC_VERSION=3.5.8-r0
ZLIB_STATIC_VERSION=1.3.2-r0
ZSTD_STATIC_VERSION=1.5.7-r2

root="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
work="$root/.build"
prefix="${PREFIX:-/data/data/com.termux/files/usr}"

die() { echo "build.sh: $*" >&2; exit 1; }
note() { echo "  $*"; }

clean=0
fetch_only=0
for arg in "$@"; do
  case "$arg" in
    --clean) clean=1 ;;
    --fetch-only) fetch_only=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

[ "$(uname -m)" = "aarch64" ] || die "aarch64 only (this host is $(uname -m))"
for tool in clang ld.lld zstd curl tar ar; do
  command -v "$tool" >/dev/null 2>&1 || die "missing '$tool' — pkg install clang lld zstd binutils"
done

if [ "$clean" = 1 ]; then
  rm -rf "$root/bin" "$root/lib" "$root/musl-sysroot"
fi

mkdir -p "$work" "$root/bin" "$root/lib" "$root/musl-sysroot"

# Cached download. A zero-length or partial file is never left in place, so a
# failed run is fixed by simply re-running.
fetch() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    note "cached $(basename "$dest")"
    return 0
  fi
  note "fetching $(basename "$dest")"
  curl -fsSL --retry 3 --connect-timeout 20 -o "$dest.part" "$url" \
    || die "download failed: $url"
  mv "$dest.part" "$dest"
}

# `tar xzf` on an .apk: the format is a gzipped tar, so tar skips the signed
# signature member by itself. .PKGINFO/.SIGN.* land in the sysroot root and are
# removed afterwards.
#
# `usr/bin` and `usr/share` are excluded. Alpine's gcc package hard-links its
# driver binaries into usr/bin, and hard links cannot be created on every
# Android filesystem — the single failed link aborts the whole extraction with
# a non-zero status. A sysroot needs libc, the crt objects and headers only;
# the caller verifies those individually rather than trusting tar's exit code.
#
# `usr/libexec` (gcc's cc1/collect2/lto1, ~75 MB) and the gcc plugin directory
# (~13 MB) are excluded as pure ballast — nothing links against them.
extract_apk() {
  local apk="$1" dest="$2"
  tar xzf "$apk" -C "$dest" \
    --exclude='usr/bin' --exclude='usr/bin/*' \
    --exclude='usr/share' --exclude='usr/share/*' \
    --exclude='usr/libexec' --exclude='usr/libexec/*' \
    --exclude='usr/lib/gcc/*/*/plugin' --exclude='usr/lib/gcc/*/*/plugin/*' \
    || die "not a readable apk: $apk"
}

alpine_url() { echo "https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/main/aarch64/$1"; }

NPM_URL="https://registry.npmjs.org/@perryts/perry-linux-arm64-musl/-/perry-linux-arm64-musl-$PERRY_VERSION.tgz"

echo "Perry $PERRY_VERSION for Termux — assembling into $root"

# ---------------------------------------------------------------- 1. compiler
fetch "$NPM_URL" "$work/perry.tgz"
rm -rf "$work/pkg"
mkdir -p "$work/pkg"
tar xzf "$work/perry.tgz" -C "$work/pkg"

install -m755 "$work/pkg/package/bin/perry" "$root/bin/perry.real"
for lib in libperry_runtime libperry_runtime_abort libperry_stdlib; do
  # Decompressed here rather than left as .a.zst: Perry would otherwise unpack
  # them into ~/.cache on first use, which is the same bytes on disk but
  # somewhere less obvious.
  zstd -d -q -f -o "$root/lib/$lib.a" "$work/pkg/package/lib/$lib.a.zst" \
    || die "missing bundled archive: $lib.a.zst"
  note "lib/$lib.a"
done

if [ "$fetch_only" = 1 ]; then
  echo "downloads cached under $work"
  exit 0
fi

# ----------------------------------------------------------------- 2. sysroot
for spec in "musl-$MUSL_VERSION" \
            "musl-dev-$MUSL_VERSION" \
            "gcc-$GCC_VERSION" \
            "openssl-libs-static-$OPENSSL_STATIC_VERSION" \
            "zlib-static-$ZLIB_STATIC_VERSION" \
            "zstd-static-$ZSTD_STATIC_VERSION"; do
  fetch "$(alpine_url "$spec.apk")" "$work/$spec.apk"
  extract_apk "$work/$spec.apk" "$root/musl-sysroot"
done
# apk metadata members, not part of a sysroot
rm -f "$root/musl-sysroot/.PKGINFO" "$root/musl-sysroot"/.SIGN.*

[ -s "$root/musl-sysroot/usr/lib/libc.a" ] || die "sysroot is missing usr/lib/libc.a"
[ -s "$root/musl-sysroot/usr/lib/crt1.o" ] || die "sysroot is missing usr/lib/crt1.o"
note "musl-sysroot/ ready"

# ------------------------------------------------- 3. clang's `-lgcc` wants it
# Alpine's gcc package ships crtbeginT.o, crtend.o, libgcc_eh.a and a static
# libgcc.a — the matched set, so clang's implicit -lgcc resolves normally.
# Some builds of the package omit libgcc.a; stand in Termux's compiler-rt
# builtins there, which are the same aarch64 support routines (integer
# division helpers, __clzdi2, …) under a C-ABI-compatible name.
gccdir=""
for d in "$root/musl-sysroot"/usr/lib/gcc/*/*/; do
  [ -e "$d/crtbeginT.o" ] && gccdir="${d%/}"
done
[ -n "$gccdir" ] || die "Alpine gcc support files not found under musl-sysroot/usr/lib/gcc"

if [ -s "$gccdir/libgcc.a" ]; then
  note "libgcc.a: Alpine's gcc package"
else
  builtins=""
  for candidate in "$prefix"/lib/clang/*/lib/linux/libclang_rt.builtins-aarch64-android.a; do
    [ -s "$candidate" ] && builtins="$candidate"
  done
  [ -n "$builtins" ] || die "no libgcc.a in the sysroot and no libclang_rt.builtins-aarch64-android.a under $prefix/lib/clang"
  install -m644 "$builtins" "$gccdir/libgcc.a"
  note "libgcc.a <- $(basename "$builtins") (Alpine's gcc package has none)"
fi

# ------------------------------------------------- 4. scripts + HTTP stubs
install -m755 "$root/src/perry" "$root/bin/perry"
install -m755 "$root/src/cc" "$root/bin/cc"

"$root/bin/cc" -c "$root/src/ext_http_stubs.c" -o "$work/ext_http_stubs.o" 2>/dev/null \
  || die "failed to compile src/ext_http_stubs.c"
ar rcs "$root/lib/libperry_ext_http_stubs.a" "$work/ext_http_stubs.o"
note "lib/libperry_ext_http_stubs.a"

echo
echo "done — install with: bash install.sh"
du -sh "$root/bin" "$root/lib" "$root/musl-sysroot" 2>/dev/null || true
