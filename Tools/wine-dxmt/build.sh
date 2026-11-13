#!/bin/bash
# Builds Wine's macOS driver winemac.so with winemac-dxmt.patch, so that DXMT
# can create its Metal view. Only this one file is built; it replaces the
# driver in Kelter's DXMT copy of Wine, never in the Wine all bottles use.
#
# The source matches the Gcenx "Wine Staging" build Kelter downloads: Wine
# plus all Wine Staging patches. Gcenx adds one Vulkan patch on top that does
# not touch winemac.drv.
#
# Needs (Homebrew): bison >= 3 ("brew install bison") and MinGW
# ("brew install mingw-w64"). Wine's configure refuses to run without a PE
# compiler on macOS, even though only a Unix library is built here. Builds
# for x86_64 under Rosetta 2, for macOS 10.15 like the Gcenx build.
#
# Wine version and revision come from the "wineFiles" entry of the DXMT layer
# in Resources/runtimes.json. The result goes where Kelter looks for it:
# ~/Library/Application Support/Kelter/Runtimes/wine-files/dxmt/<wine>-<revision>/
#
# Usage: Tools/wine-dxmt/build.sh [output directory]
#   WORK  working folder, kept for faster rebuilds
#         (default ~/Library/Caches/Kelter/wine-dxmt-build)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HERE/../../Resources/runtimes.json"
read -r WINE_VERSION REVISION < <(python3 -I -c '
import json, sys
layer = next(l for l in json.load(open(sys.argv[1]))["graphicsLayers"] if l["id"] == "dxmt")
print(layer["wineFiles"]["wineVersion"], layer["wineFiles"]["version"])
' "$CONFIG")
WORK="${WORK:-$HOME/Library/Caches/Kelter/wine-dxmt-build}"
OUT="${1:-$HOME/Library/Application Support/Kelter/Runtimes/wine-files/dxmt/$WINE_VERSION-$REVISION}"
PATCH="$HERE/winemac-dxmt.patch"

BISON_DIR="$(brew --prefix bison 2>/dev/null)/bin"
[ -x "$BISON_DIR/bison" ] || { echo "bison >= 3 fehlt: brew install bison" >&2; exit 1; }
command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "MinGW fehlt: brew install mingw-w64" >&2; exit 1; }
/usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || { echo "Rosetta 2 fehlt: softwareupdate --install-rosetta" >&2; exit 1; }

export PATH="$BISON_DIR:$PATH"
export MACOSX_DEPLOYMENT_TARGET=10.15

SRC="$WORK/src-$WINE_VERSION"
BUILD="$WORK/build-$WINE_VERSION"
PATCH_SUM="$(shasum -a 256 "$PATCH" | cut -d' ' -f1)"
STAMP="$SRC/.kelter-patched-$PATCH_SUM"
mkdir -p "$WORK"

# 1. Source: Wine + Wine Staging + our patch. Prepared once per patch version.
if [ ! -f "$STAMP" ]; then
    rm -rf "$SRC" "$WORK/staging-$WINE_VERSION" "$BUILD"
    git clone -q -c advice.detachedHead=false --depth 1 --branch "wine-$WINE_VERSION" \
        https://gitlab.winehq.org/wine/wine.git "$SRC"
    git clone -q -c advice.detachedHead=false --depth 1 --branch "v$WINE_VERSION" \
        https://gitlab.winehq.org/wine/wine-staging.git "$WORK/staging-$WINE_VERSION"
    python3 -I "$WORK/staging-$WINE_VERSION/staging/patchinstall.py" DESTDIR="$SRC" \
        --all --no-autoconf --backend=git-apply >/dev/null
    (cd "$SRC" && perl tools/make_requests >/dev/null)
    git -C "$SRC" apply "$PATCH"
    touch "$STAMP"
fi

# 2. Configure (once) and build only the driver.
mkdir -p "$BUILD"
cd "$BUILD"
if [ ! -f Makefile ]; then
    /usr/bin/arch -x86_64 "$SRC/configure" --host=x86_64-apple-darwin \
        CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64" \
        --enable-archs=x86_64 --disable-tests \
        --without-x --without-freetype --without-gnutls --without-gstreamer \
        --without-sdl --without-vulkan --without-wayland --without-ffmpeg \
        > configure.log 2>&1 || { tail -20 configure.log >&2; exit 1; }
fi
/usr/bin/arch -x86_64 make -j"$(sysctl -n hw.ncpu)" dlls/winemac.drv/winemac.so > make.log 2>&1 \
    || { tail -30 make.log >&2; exit 1; }

# 3. Check, sign like the Gcenx build (ad hoc) and hand out.
LIB="$BUILD/dlls/winemac.drv/winemac.so"
nm -gU "$LIB" | grep -q ' _macdrv_functions$' \
    || { echo "macdrv_functions wird nicht exportiert" >&2; exit 1; }
mkdir -p "$OUT/x86_64-unix"
cp "$LIB" "$OUT/x86_64-unix/winemac.so.new"
codesign -s - -f "$OUT/x86_64-unix/winemac.so.new" 2>/dev/null
mv -f "$OUT/x86_64-unix/winemac.so.new" "$OUT/x86_64-unix/winemac.so"
echo "Fertig (Wine $WINE_VERSION, Revision $REVISION): $OUT/x86_64-unix/winemac.so"
echo "In Kelter jetzt bei der Bottle DXMT auswählen oder Steam starten."
