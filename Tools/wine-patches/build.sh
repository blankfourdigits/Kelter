#!/bin/bash
# Builds the Wine files Kelter changes for its graphics layers, from Wine plus
# all Wine Staging patches plus the *.patch files in this folder:
#
#   x86_64-unix/winemac.so    Wine's macOS driver with macdrv_functions
#                             (DXMT, D3DMetal)
#   x86_64-windows/ntdll.dll  ntdll with __wine_unix_call exported again
#                             (D3DMetal)
#   x86_64-unix/ntdll.so      ntdll's Unix side: direct syscalls of programs
#                             work on macOS, and programs can keep the Mac
#                             awake (DXMT, D3DMetal)
#
# They only go into Kelter's copies of Wine for these layers, never into the
# Wine all bottles use. The source matches the Gcenx "Wine Staging" build
# Kelter downloads. Gcenx's own change to ntdll.so (the Vulkan driver path,
# MoltenVK) is reproduced in 0004; ntdll.so must behave like his.
#
# Needs (Homebrew): bison >= 3 ("brew install bison") and MinGW
# ("brew install mingw-w64"). Builds for x86_64 under Rosetta 2, for
# macOS 10.15 like the Gcenx build.
#
# Wine version and revision come from "winePatches" in
# Resources/runtimes.json. The result goes where Kelter looks for it:
# ~/Library/Application Support/Kelter/Runtimes/wine-files/<wine>-<revision>/
#
# Usage: Tools/wine-patches/build.sh [output directory]
#   WORK  working folder, kept for faster rebuilds
#         (default ~/Library/Caches/Kelter/wine-patches-build)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HERE/../../Resources/runtimes.json"
read -r WINE_VERSION REVISION < <(python3 -I -c '
import json, sys
patches = json.load(open(sys.argv[1]))["winePatches"]
print(patches["wineVersion"], patches["version"])
' "$CONFIG")
WORK="${WORK:-$HOME/Library/Caches/Kelter/wine-patches-build}"
OUT="${1:-$HOME/Library/Application Support/Kelter/Runtimes/wine-files/$WINE_VERSION-$REVISION}"

BISON_DIR="$(brew --prefix bison 2>/dev/null)/bin"
[ -x "$BISON_DIR/bison" ] || { echo "bison >= 3 fehlt: brew install bison" >&2; exit 1; }
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "MinGW fehlt: brew install mingw-w64" >&2; exit 1; }
/usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || { echo "Rosetta 2 fehlt: softwareupdate --install-rosetta" >&2; exit 1; }

export PATH="$BISON_DIR:$PATH"
export MACOSX_DEPLOYMENT_TARGET=10.15

SRC="$WORK/src-$WINE_VERSION"
BUILD="$WORK/build-$WINE_VERSION"
PATCHES=("$HERE"/*.patch)
PATCH_SUM="$(cat "${PATCHES[@]}" | shasum -a 256 | cut -d' ' -f1)"
STAMP="$SRC/.kelter-patched-$PATCH_SUM"
mkdir -p "$WORK"

# 1. Source: Wine + Wine Staging + our patches. Prepared again whenever a
#    patch changes; the configured build folder is kept.
if [ ! -f "$STAMP" ]; then
    rm -rf "$SRC" "$WORK/staging-$WINE_VERSION"
    git clone -q -c advice.detachedHead=false --depth 1 --branch "wine-$WINE_VERSION" \
        https://gitlab.winehq.org/wine/wine.git "$SRC"
    git clone -q -c advice.detachedHead=false --depth 1 --branch "v$WINE_VERSION" \
        https://gitlab.winehq.org/wine/wine-staging.git "$WORK/staging-$WINE_VERSION"
    python3 -I "$WORK/staging-$WINE_VERSION/staging/patchinstall.py" DESTDIR="$SRC" \
        --all --no-autoconf --backend=git-apply >/dev/null
    (cd "$SRC" && perl tools/make_requests >/dev/null)
    for patch in "${PATCHES[@]}"; do
        git -C "$SRC" apply "$patch"
    done
    touch "$STAMP"
fi

# 2. Configure (again whenever these options change) and build only the
#    files Kelter replaces. A newer SDK than the deployment target declares
#    functions older macOS lacks; they are only weakly linked, so Wine would
#    call a null pointer there. Keep configure from using them.
CONFIGURE_ARGS=(
    --host=x86_64-apple-darwin
    CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64"
    --enable-archs=x86_64 --disable-tests
    --without-x --without-freetype --without-gnutls --without-gstreamer
    --without-sdl --without-vulkan --without-wayland --without-ffmpeg
    ac_cv_func_pipe2=no ac_cv_func_dup3=no   # macOS 27 and later
)
mkdir -p "$BUILD"
cd "$BUILD"
CONFIGURE_STAMP=".kelter-configure-$(printf '%s\n' "${CONFIGURE_ARGS[@]}" | shasum -a 256 | cut -c1-16)"
if [ ! -f Makefile ] || [ ! -f "$CONFIGURE_STAMP" ]; then
    rm -f .kelter-configure-*
    /usr/bin/arch -x86_64 "$SRC/configure" "${CONFIGURE_ARGS[@]}" \
        > configure.log 2>&1 || { tail -20 configure.log >&2; exit 1; }
    touch "$CONFIGURE_STAMP"
fi
/usr/bin/arch -x86_64 make -j"$(sysctl -n hw.ncpu)" \
    dlls/winemac.drv/winemac.so dlls/ntdll/x86_64-windows/ntdll.dll dlls/ntdll/ntdll.so \
    > make.log 2>&1 \
    || { tail -30 make.log >&2; exit 1; }

# 3. Check and hand out. The .so files are signed ad hoc like the Gcenx
#    build; ntdll.dll loses its debug information like Wine's release builds.
WINEMAC="$BUILD/dlls/winemac.drv/winemac.so"
NTDLL="$BUILD/dlls/ntdll/x86_64-windows/ntdll.dll"
NTDLL_SO="$BUILD/dlls/ntdll/ntdll.so"
# Read the whole listing first: grep -q stops early, and with pipefail the
# interrupted lister would count as a failure.
WINEMAC_EXPORTS="$(nm -gU "$WINEMAC")"
NTDLL_EXPORTS="$(x86_64-w64-mingw32-objdump -p "$NTDLL")"
grep -q ' _macdrv_functions$' <<<"$WINEMAC_EXPORTS" \
    || { echo "winemac.so exportiert macdrv_functions nicht" >&2; exit 1; }
grep -q ' __wine_unix_call$' <<<"$NTDLL_EXPORTS" \
    || { echo "ntdll.dll exportiert __wine_unix_call nicht" >&2; exit 1; }
for lib in "$WINEMAC" "$NTDLL_SO"; do
    if nm -u "$lib" | grep -qE '^_(pipe2|dup3)$'; then
        echo "$(basename "$lib") nutzt Funktionen, die es erst ab macOS 27 gibt" >&2; exit 1
    fi
done
# Like Gcenx's ntdll.so: without the Vulkan driver path Steam stays blank.
NTDLL_SO_STRINGS="$(strings "$NTDLL_SO")"
grep -q '/vulkan/icd\.d$' <<<"$NTDLL_SO_STRINGS" \
    || { echo "ntdll.so setzt den Vulkan-Treiberpfad nicht (Patch 0004)" >&2; exit 1; }
# Wine's other Unix libraries link against @rpath/ntdll.so (Gcenx's own
# ntdll.so is named plain "ntdll.so"; both resolve to the same file).
NTDLL_SO_NAME="$(otool -D "$NTDLL_SO" | tail -1)"
case "$NTDLL_SO_NAME" in
    ntdll.so|@rpath/ntdll.so) ;;
    *) echo "ntdll.so hat den unerwarteten Namen \"$NTDLL_SO_NAME\"" >&2; exit 1 ;;
esac

mkdir -p "$OUT/x86_64-unix" "$OUT/x86_64-windows"
cp "$WINEMAC" "$OUT/x86_64-unix/winemac.so.new"
codesign -s - -f "$OUT/x86_64-unix/winemac.so.new" 2>/dev/null
mv -f "$OUT/x86_64-unix/winemac.so.new" "$OUT/x86_64-unix/winemac.so"
cp "$NTDLL_SO" "$OUT/x86_64-unix/ntdll.so.new"
codesign -s - -f "$OUT/x86_64-unix/ntdll.so.new" 2>/dev/null
mv -f "$OUT/x86_64-unix/ntdll.so.new" "$OUT/x86_64-unix/ntdll.so"
x86_64-w64-mingw32-strip --strip-debug -o "$OUT/x86_64-windows/ntdll.dll.new" "$NTDLL"
mv -f "$OUT/x86_64-windows/ntdll.dll.new" "$OUT/x86_64-windows/ntdll.dll"

echo "Fertig (Wine $WINE_VERSION, Revision $REVISION): $OUT"
echo "In Kelter jetzt bei der Bottle die Grafik auswählen oder Steam starten."
