#!/bin/bash
# Builds Resources/steam-ui-fix/winmm.dll from winmm_proxy.c.
#
# Needs clang, lld-link and llvm-dlltool (LLVM 15 or newer), for example from
# "brew install llvm lld" on a Mac or the llvm/lld packages on Linux. No
# Windows SDK and no MinGW are needed: the library uses no C runtime, and the
# three small import libraries are generated here.
#
# Usage: Tools/steam-ui-fix/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../Resources/steam-ui-fix"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CLANG="${CLANG:-clang}"
LLD_LINK="${LLD_LINK:-lld-link}"
DLLTOOL="${DLLTOOL:-llvm-dlltool}"

# Import libraries for the few functions the proxy calls itself.
printf 'LIBRARY kernelbase.dll\nEXPORTS\nGetCommandLineW\nGetEnvironmentVariableW\nGetModuleHandleW\n' > "$WORK/kernelbase.def"
printf 'LIBRARY ntdll.dll\nEXPORTS\n__wine_dbg_output\n' > "$WORK/ntdll.def"
"$DLLTOOL" -m i386:x86-64 -d "$WORK/kernelbase.def" -l "$WORK/kernelbase.lib"
"$DLLTOOL" -m i386:x86-64 -d "$WORK/ntdll.def" -l "$WORK/ntdll.lib"

# Every winmm function is forwarded to winmm_orig.dll. The names come from
# Wine's dlls/winmm/winmm.spec (see winmm_exports.txt).
{
    printf 'LIBRARY winmm.dll\nEXPORTS\n'
    while IFS= read -r name; do
        [ -n "$name" ] && printf '    %s = winmm_orig.%s\n' "$name" "$name"
    done < "$HERE/winmm_exports.txt"
} > "$WORK/winmm_proxy.def"

"$CLANG" --target=x86_64-pc-windows-msvc -c \
    -Os -ffreestanding -fno-builtin -fno-stack-protector -mno-stack-arg-probe \
    -Wall -Wextra \
    -o "$WORK/winmm_proxy.obj" "$HERE/winmm_proxy.c"

mkdir -p "$OUT"
"$LLD_LINK" /dll /nodefaultlib /entry:DllMain /subsystem:windows \
    /machine:x64 /def:"$WORK/winmm_proxy.def" /Brepro \
    /out:"$OUT/winmm.dll" \
    "$WORK/winmm_proxy.obj" "$WORK/kernelbase.lib" "$WORK/ntdll.lib"

rm -f "$OUT/winmm.lib"
echo "Gebaut: $OUT/winmm.dll"
