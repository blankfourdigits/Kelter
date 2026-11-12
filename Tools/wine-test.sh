#!/bin/bash
# Finds out under which conditions the installed Wine build can set up a
# fresh Windows environment. Each test uses its own temporary prefix, so no
# bottle is touched.
#
# Usage: bash Tools/wine-test.sh
# Result: wine-test.txt in the Kelter project folder.

APP="$HOME/Library/Application Support/Kelter"
OUT="$(cd "$(dirname "$0")/.." && pwd)/wine-test.txt"

ENGINE="$(ls -d "$APP"/Runtimes/wine/*/wswine.bundle 2>/dev/null | head -1)"
CONTENTS="$(ls -d "$APP"/Runtimes/support/*/*.app/Contents 2>/dev/null | head -1)"
WINE="$ENGINE/bin/wine"
SERVER="$ENGINE/bin/wineserver"
FW="$CONTENTS/Frameworks"

LIBS="DYLD_FALLBACK_LIBRARY_PATH=$FW:$FW/GStreamer.framework/Libraries:/usr/lib"
AVX="ROSETTA_ADVERTISE_AVX=1"
VK1="VK_DRIVER_FILES=$CONTENTS/Resources/vulkan/icd.d/MoltenVK_icd.json"
VK2="VK_ICD_FILENAMES=$CONTENTS/Resources/vulkan/icd.d/MoltenVK_icd.json"
GST="GST_PLUGIN_PATH=$FW/GStreamer.framework/Libraries/gstreamer-1.0"
D9VK="WINEDLLPATH_D9VK=$FW/renderer/d9vk/wine"
DXMT="WINEDLLPATH_DXMT=$FW/renderer/dxmt/wine"
MENU="WINEDLLOVERRIDES=winemenubuilder.exe=d"

# Keep the terminal for progress messages; everything else goes to the file.
exec 3>&1
exec > "$OUT" 2>&1

if [ ! -x "$WINE" ]; then
    echo "Wine wurde nicht gefunden: $WINE"
    echo "Wine wurde nicht gefunden. Bitte zuerst in Kelter installieren." >&3
    exit 1
fi
echo "Der Test läuft und kann bis zu zehn Minuten dauern. Bitte warten …" >&3

echo "Datum: $(date)"
sw_vers
echo "Engine:   $ENGINE"
echo "Template: $CONTENTS"
echo
echo "--- Dateien"
ls -la "$ENGINE/bin" "$ENGINE/lib/wine/x86_64-unix/wine"
file "$WINE" "$ENGINE/lib/wine/x86_64-unix/wine"
cat "$ENGINE/version" 2>/dev/null; echo
echo "--- Erweiterte Attribute"
xattr -l "$WINE" "$SERVER" "$ENGINE/lib/wine/x86_64-unix/wine" "$ENGINE/lib/wine/x86_64-unix/ntdll.so" 2>&1
echo "--- Signaturen"
codesign -dv "$WINE" 2>&1 | head -4
codesign -dv "$ENGINE/lib/wine/x86_64-unix/wine" 2>&1 | head -4
echo "--- Rosetta"
arch -x86_64 /usr/bin/true && echo "Rosetta: ok"
echo "--- Renderer im Template"
ls "$FW/renderer" 2>&1
echo

# run_test <name> <seconds> <WINEDEBUG> [VAR=value ...]
run_test() {
    local name="$1" limit="$2" debug="$3"
    shift 3
    local prefix
    prefix="$(mktemp -d /tmp/kelter-test.XXXXXX)"
    echo "===================================================================="
    echo "TEST: $name"
    echo "  Test $name …" >&3
    for assignment in "$@"; do echo "  $assignment"; done
    local log="$prefix.log"
    local started=$SECONDS
    env -i HOME="$HOME" USER="$USER" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" \
        WINEPREFIX="$prefix" WINEDEBUG="$debug" "$@" \
        "$WINE" wineboot --init < /dev/null > "$log" 2>&1 &
    local pid=$!
    local result=""
    while kill -0 "$pid" 2>/dev/null; do
        if [ $((SECONDS - started)) -ge "$limit" ]; then
            kill "$pid" 2>/dev/null
            result="ZEITLIMIT nach ${limit}s"
            break
        fi
        sleep 1
    done
    if [ -z "$result" ]; then
        wait "$pid"
        result="Status $?"
    fi
    echo "ERGEBNIS: $result nach $((SECONDS - started))s"
    echo "drive_c vorhanden: $([ -d "$prefix/drive_c/windows/system32" ] && echo ja || echo nein)"
    local lines=120
    [ "$debug" != "fixme-all" ] && lines=400
    echo "--- Ausgabe (höchstens $lines Zeilen)"
    head -"$lines" "$log"
    env -i HOME="$HOME" USER="$USER" PATH="/usr/bin:/bin" WINEPREFIX="$prefix" "$@" "$SERVER" -k > /dev/null 2>&1
    sleep 1
    rm -rf "$prefix" "$log"
    echo
}

run_test "1 nur WINEPREFIX" 240 "fixme-all"
run_test "2 mit Laufzeitbibliotheken" 240 "fixme-all" "$LIBS"
run_test "3 Bibliotheken + AVX" 240 "fixme-all" "$LIBS" "$AVX"
run_test "4 Bibliotheken + Vulkan + GStreamer" 240 "fixme-all" "$LIBS" "$VK1" "$VK2" "$GST"
run_test "5 Bibliotheken + D9VK" 240 "fixme-all" "$LIBS" "$D9VK"
run_test "6 Bibliotheken + DXMT" 240 "fixme-all" "$LIBS" "$DXMT"
run_test "7 Bibliotheken + winemenubuilder aus" 240 "fixme-all" "$LIBS" "$MENU"
run_test "8 alles wie in Kelter" 240 "fixme-all" "$LIBS" "$AVX" "$VK1" "$VK2" "$GST" "$D9VK" "$DXMT" "$MENU"
run_test "9 alles wie in Kelter, ausführlich" 60 "+pid,+process,+module,+loaddll" "$LIBS" "$AVX" "$VK1" "$VK2" "$GST" "$D9VK" "$DXMT" "$MENU"

echo "Fertig."
echo "Fertig. Das Ergebnis steht in $OUT" >&3
