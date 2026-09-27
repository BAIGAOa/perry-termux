#!/data/data/com.termux/files/usr/bin/bash
# Install Perry into the Termux prefix by symlinking the launcher onto PATH.
#
# The package is relocatable: nothing is copied, so it can live anywhere and
# still work. Run with --uninstall to remove the symlink.
set -euo pipefail

root="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
prefix="${PREFIX:-/data/data/com.termux/files/usr}"
target="$prefix/bin/perry"

if [ ! -d "$prefix/bin" ]; then
  echo "error: $prefix/bin not found — is this Termux?" >&2
  exit 1
fi

if [ "${1:-}" = "--uninstall" ]; then
  if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$root/bin/perry" ]; then
    rm -f "$target"
    echo "removed $target"
  else
    echo "nothing to do: $target is not a link to this package"
  fi
  exit 0
fi

for tool in clang ld.lld; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' is required. Install it with:" >&2
    echo "  pkg install clang lld" >&2
    exit 1
  fi
done

if [ -e "$target" ] && [ ! -L "$target" ]; then
  echo "error: $target already exists and is not a symlink; move it aside first" >&2
  exit 1
fi

ln -sfn "$root/bin/perry" "$target"
echo "installed: $target -> $root/bin/perry"
echo "try: perry --version"
