#!/usr/bin/env bash
# check-archive.sh <build-dir>
#
# Checks the module archive that the target package made in <build-dir>/package/, as a runtime
# distribution would receive it:
#   1. it unpacks into a directory of the archive's name, holding exactly one module in
#      lib/praenora/modules/<name>/ with its manifest <name>.pmm.json;
#   2. each library under lib/ needs only the system's libraries and the archive's own, listed
#      with readelf -d (Linux), otool -L (macOS) or dumpbin -dependents (Windows, from Visual
#      Studio 2022, found with vswhere);
#   3. the runtime's contract checks pass on the packaged manifest, with the packaged catalog
#      entries (share/praenora/module-catalog) when there are any, run with the praenora tool that
#      the build used (PRAENORA_EXECUTABLE in <build-dir>/CMakeCache.txt).
# It prints ::error:: lines (GitHub Actions annotations) and exits with 1 on any problem. It runs
# on CI's runners and on a developer's machine (Linux, macOS, or Git Bash on Windows); it unpacks
# into $RUNNER_TEMP, else $TMPDIR, else /tmp.
set -euo pipefail
shopt -s nullglob

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <build-dir>" >&2
  exit 2
fi
build=$1

case "${RUNNER_OS:-$(uname -s)}" in
  Linux) os=Linux ;;
  macOS | Darwin) os=macOS ;;
  Windows | MINGW* | MSYS* | CYGWIN*) os=Windows ;;
  *) echo "::error::No check for the operating system ${RUNNER_OS:-$(uname -s)}"; exit 1 ;;
esac

# unix_path <path>: a path that this shell can use (cygpath on Windows).
unix_path() {
  if [ "$os" = Windows ]; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
}

archives=("$build"/package/*.tar.xz "$build"/package/*.zip)
if [ "${#archives[@]}" -ne 1 ]; then
  echo "::error::$build/package holds ${#archives[@]} archives, not one"
  exit 1
fi
archive="$(cd "$(dirname "${archives[0]}")" && pwd)/$(basename "${archives[0]}")"
name=$(basename "$archive")
name=${name%.tar.xz}
name=${name%.zip}

# CMakeCache.txt has CRLF line endings on Windows; sed keeps the CR.
praenora=$(sed -n 's/^PRAENORA_EXECUTABLE:FILEPATH=//p' "$build/CMakeCache.txt" | tr -d '\r')
if [ -z "$praenora" ] || [ "$praenora" = PRAENORA_EXECUTABLE-NOTFOUND ]; then
  echo "::error::$build/CMakeCache.txt names no praenora tool (PRAENORA_EXECUTABLE)"
  exit 1
fi
praenora=$(unix_path "$praenora")

if [ "$os" = Windows ]; then
  programs=$(cygpath -u "$(printenv 'ProgramFiles(x86)')")
  vswhere="$programs/Microsoft Visual Studio/Installer/vswhere.exe"
  dumpbin=$("$vswhere" -latest -products '*' -version '[17.0,18.0)' \
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
      -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' | tr -d '\r' | sed -n 1p)
  if [ -z "$dumpbin" ]; then
    echo "::error::$vswhere found no dumpbin.exe of Visual Studio 2022"
    exit 1
  fi
  dumpbin=$(cygpath -u "$dumpbin")
  system32=$(cygpath -u -S)
fi

work="$(unix_path "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")/archive-check"
rm -rf "$work"
mkdir -p "$work"
(cd "$work" && cmake -E tar xf "$archive")
if [ ! -d "$work/$name" ]; then
  echo "::error::$name does not unpack into a directory $name"
  exit 1
fi
cd "$work/$name"

# 1. One module, with its manifest.
modules=(lib/praenora/modules/*/)
if [ "${#modules[@]}" -ne 1 ]; then
  echo "::error::$name holds ${#modules[@]} modules in lib/praenora/modules/, not one"
  exit 1
fi
module=$(basename "${modules[0]}")
manifest="lib/praenora/modules/$module/$module.pmm.json"
if [ ! -f "$manifest" ]; then
  echo "::error::$name holds no manifest $manifest"
  exit 1
fi

# 2. The libraries' dependencies.
# libraries <file>: the libraries that <file> names, one per line.
libraries() {
  case "$os" in
    Linux) readelf -d "$1" | sed -n 's/^.*(NEEDED).*\[\(.*\)\]$/\1/p' ;;
    macOS) otool -L "$1" | sed -n 's/^[[:space:]]*\(.*\) (compatibility version .*$/\1/p' ;;
    Windows)
      "$dumpbin" -nologo -dependents "$1" | tr -d '\r' \
          | sed -n 's/^[[:space:]][[:space:]]*\([^[:space:]]*\.[Dd][Ll][Ll]\)$/\1/p' ;;
  esac
}
# in_archive <name>: whether the archive holds a file or link of that name.
in_archive() {
  [ -n "$(find . -name "$1" -print)" ]
}
# allowed <library>: whether <library> is the system's or in the archive.
allowed() {
  case "$os" in
    Linux)
      case "$1" in
        # glibc's libraries, and GCC's C++ and support libraries.
        libc.so.6 | libm.so.6 | libdl.so.2 | libpthread.so.0 | librt.so.1) return 0 ;;
        libutil.so.1 | libresolv.so.2 | ld-linux-x86-64.so.2) return 0 ;;
        libstdc++.so.6 | libgcc_s.so.1) return 0 ;;
        */*) return 1 ;;
        *) in_archive "$1" ;;
      esac ;;
    macOS)
      case "$1" in
        /usr/lib/* | /System/*) return 0 ;;
        @rpath/* | @loader_path/* | @executable_path/*) in_archive "${1##*/}" ;;
        *) return 1 ;;
      esac ;;
    Windows)
      case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        # The API sets, and the Visual C++ runtime (with its debug libraries).
        api-ms-win-* | ext-ms-*) return 0 ;;
        msvcp140*.dll | vcruntime140*.dll | concrt140*.dll | ucrtbase*.dll) return 0 ;;
        */* | *\\*) return 1 ;;
        *) [ -f "$system32/$1" ] || in_archive "$1" ;;
      esac ;;
  esac
}

if [ "$os" = Windows ]; then
  files=$(find lib -type f -iname '*.dll' | sort)
else
  files=$(find lib -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \) | sort)
fi
if [ -z "$files" ]; then
  echo "::error::$name holds no library under lib/"
  exit 1
fi
checked=0
problems=0
while IFS= read -r file; do
  checked=$((checked + 1))
  if ! names=$(libraries "$file"); then
    echo "::error::$file: its libraries could not be listed"
    problems=$((problems + 1))
    continue
  fi
  # Each library names at least the system's C library, so an empty list was not read.
  if [ -z "$names" ]; then
    echo "::error::$file: no library was listed, so the list was not read"
    problems=$((problems + 1))
    continue
  fi
  echo "$file: $(printf '%s' "$names" | tr '\n' ' ')"
  while IFS= read -r library; do
    if ! allowed "$library"; then
      echo "::error::$file needs $library, which is neither the system's nor in the archive"
      problems=$((problems + 1))
    fi
  done <<< "$names"
done <<< "$files"
if [ "$problems" -gt 0 ]; then
  echo "::error::$name: $problems problem(s) in the $checked libraries checked"
  exit 1
fi
echo "$name: $checked libraries checked, each needs only the system's libraries and the archive's own"

# 3. The contract checks of the packaged module.
catalog=()
if [ -d share/praenora/module-catalog ]; then
  catalog=(--catalog-path share/praenora/module-catalog)
fi
if ! "$praenora" modules check "$manifest" ${catalog[@]+"${catalog[@]}"}; then
  echo "::error::$name: the contract checks of $manifest failed"
  exit 1
fi
echo "$name: the packaged module passes the contract checks"
