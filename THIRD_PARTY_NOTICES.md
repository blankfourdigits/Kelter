# Herkunft und Lizenzen

Kelter selbst steht unter der [GNU GPL, Version 3](LICENSE).

## Was im Repository liegt

| Bestandteil | Herkunft | Lizenz |
| --- | --- | --- |
| Kelters Quelltext (`Sources/`, `Tests/`, `scripts/`, `Tools/`) | Kelter | GPLv3 |
| `Resources/steam-ui-fix/winmm.dll` | aus `Tools/steam-ui-fix/winmm_proxy.c` gebaut, Quelltext liegt bei | GPLv3 |
| `Resources/AppIcon.icns`, `Tools/app-icon/AppIcon-preview.png` | von `Tools/app-icon/make-icon.swift` gezeichnet | GPLv3 |
| `Tools/wine-patches/*.patch` | Kelters Änderungen an Wine | LGPL-2.1-or-later, wie Wine |

Die Wine-Patches stützen sich auf Vorarbeiten, die in den Patch-Dateien
genannt sind:

- [NNikolaG/bridgewine](https://github.com/NNikolaG/bridgewine), Patches
  0006 und 0007 für Wine 11.21 (MIT-Lizenz)
- [codeWonderland/neutron](https://github.com/codeWonderland/neutron),
  `tools/wine-dxmt/winemac-dxmt.patch` (MIT-Lizenz)
- die Schnittstelle von CrossOvers `winemac.drv`, wie sie DXMT und D3DMetal
  erwarten (es wurde kein Code von CrossOver übernommen)

## Was Kelter zur Laufzeit lädt

Diese Bestandteile sind **nicht** im Repository und nicht in der App. Kelter
lädt sie beim Einrichten von den genannten Quellen und prüft die Prüfsummen
aus `Resources/runtimes.json`.

| Bestandteil | Quelle | Lizenz |
| --- | --- | --- |
| Wine Staging (macOS-Build) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) | Wine: LGPL-2.1-or-later; das Paket enthält weitere freie Bibliotheken mit eigenen Lizenzen (u. a. MoltenVK, GStreamer, wine-mono, wine-gecko) |
| Wine und Wine Staging als Quelltext (nur beim Bauen der Wine-Patches) | [gitlab.winehq.org](https://gitlab.winehq.org/wine) | LGPL-2.1-or-later |
| DXMT | [3Shain/dxmt](https://github.com/3Shain/dxmt), © Feifan He für CodeWeavers | LGPL-2.1-or-later |
| Winetricks | [Winetricks/winetricks](https://github.com/Winetricks/winetricks) | LGPL-2.1 |
| Steam-Client für Windows | Valve, offizieller Installer | proprietär, Lizenz von Valve; Kelter startet nur Valves Installer |
| D3DMetal (Game Porting Toolkit) | Apple; wahlweise Apples Disk-Image oder [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) | proprietär, Apples Lizenz für das Game Porting Toolkit. Nur nach ausdrücklicher Zustimmung in Kelter; derzeit pausiert |

Pakete, die Winetricks auf Wunsch installiert (etwa Visual C++ von
Microsoft), lädt Winetricks von den Herstellern; für sie gelten deren
Lizenzen.

## Marken

Steam ist eine Marke der Valve Corporation. Apple, macOS und Metal sind Marken
von Apple Inc. DirectX ist eine Marke der Microsoft Corporation. CrossOver ist
eine Marke von CodeWeavers, Inc. Kelter steht mit keinem dieser Unternehmen in
Verbindung.
