# Third-party notices

Kelter itself is licensed under the [GNU GPL, version 3](LICENSE).

## In this repository

| Part | Origin | License |
| --- | --- | --- |
| Kelter's source code (`Sources/`, `Tests/`, `scripts/`, `Tools/`) | Kelter | GPLv3 |
| `Resources/steam-ui-fix/winmm.dll` | built from `Tools/steam-ui-fix/winmm_proxy.c`, source included | GPLv3 |
| `Resources/AppIcon.icns`, `Tools/app-icon/AppIcon-preview.png` | drawn by `Tools/app-icon/make-icon.swift` | GPLv3 |
| `Tools/wine-patches/*.patch` | Kelter's changes to Wine | LGPL-2.1-or-later, like Wine |

The Wine patches build on earlier work, credited in the patch files:

- [NNikolaG/bridgewine](https://github.com/NNikolaG/bridgewine), patches
  0006 and 0007 for Wine 11.21 (MIT license)
- [codeWonderland/neutron](https://github.com/codeWonderland/neutron),
  `tools/wine-dxmt/winemac-dxmt.patch` (MIT license)
- the interface of CrossOver's `winemac.drv` as DXMT and D3DMetal expect it
  (no CrossOver code was copied)
- patch 0004 reproduces the behaviour of a change in Gcenx's macOS builds of
  Wine (LGPL), see [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)

## Downloaded at run time

These parts are **not** in the repository and not in the app. Kelter
downloads them during setup from the sources below and checks the checksums
listed in `Resources/runtimes.json`.

| Part | Source | License |
| --- | --- | --- |
| Wine Staging (macOS build) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) | Wine: LGPL-2.1-or-later; the package contains further free libraries under their own licenses (among them MoltenVK, GStreamer, wine-mono, wine-gecko) |
| Kelter's Wine files (`winemac.so`, `ntdll.so`, `ntdll.dll`), only for the graphics layers | built from Wine, Wine Staging and `Tools/wine-patches/` by this repository's workflow `wine-files.yml`; published as a release of this repository together with the complete source | LGPL-2.1-or-later |
| Wine and Wine Staging source (only when building the Wine patches yourself) | [gitlab.winehq.org](https://gitlab.winehq.org/wine) | LGPL-2.1-or-later |
| DXMT | [3Shain/dxmt](https://github.com/3Shain/dxmt), © Feifan He for CodeWeavers | LGPL-2.1-or-later |
| Winetricks | [Winetricks/winetricks](https://github.com/Winetricks/winetricks) | LGPL-2.1 |
| Steam client for Windows | Valve, official installer | proprietary, Valve's license; Kelter only runs Valve's installer |
| D3DMetal (Game Porting Toolkit) | Apple; either Apple's disk image or [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) | proprietary, Apple's license for the Game Porting Toolkit. Only after explicit consent in Kelter; currently paused |

Packages that Winetricks installs on request (for example Microsoft's Visual
C++ runtime) are downloaded by Winetricks from their vendors and are subject
to their licenses.

## Trademarks

Steam is a trademark of Valve Corporation. Apple, macOS and Metal are
trademarks of Apple Inc. DirectX is a trademark of Microsoft Corporation.
CrossOver is a trademark of CodeWeavers, Inc. Kelter is not affiliated with
any of these companies.
