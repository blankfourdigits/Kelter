# Kelter

Eine freie Mac-App, die Windows-Spiele aus der Steam-Bibliothek über
[Wine](https://www.winehq.org) auf Apple-Silicon-Macs startet. Kelter ist nur
die Oberfläche: Wine und die Grafikschichten werden als fertige Builds geladen.

Lizenz: GPLv3 (siehe `LICENSE`). Kelter enthält keinen Code und keine Grafiken
von CrossOver und liefert keine proprietären Bestandteile mit.

## Stand

| Schritt | Inhalt | Status |
| --- | --- | --- |
| 1 | Wine-Download, Rosetta-Prüfung, Bottles, Log | läuft |
| 2 | Steam-Einrichtung und Start | läuft |
| 3 | Grafik | DXMT geschrieben, Test steht aus. D9VK und D3DMetal offen |
| 4 | Spielebibliothek, Einstellungen pro Spiel, Winetricks | offen |

## Voraussetzungen

- Mac mit Apple Silicon, macOS 15 oder neuer
- Xcode (einmal geöffnet, Lizenz bestätigt)
- Rosetta 2. Kelter bietet die Installation an; von Hand geht es mit
  `softwareupdate --install-rosetta --agree-to-license`

## Bauen und starten

Im Terminal, im Ordner dieses Projekts:

```sh
swift build          # kompilieren
swift test           # Tests ausführen
swift run Kelter     # App starten
```

Eine richtige App zum Doppelklicken entsteht mit:

```sh
bash scripts/make-app.sh
open build/Kelter.app
```

Alternativ `Package.swift` in Xcode öffnen und das Schema `Kelter` starten.

## Erste Schritte in der App

1. Beim ersten Start zeigt Kelter die Einrichtung: Rosetta 2 prüfen, Wine laden.
2. Mit dem Plus-Knopf eine Bottle anlegen. Das erste Einrichten dauert ein bis
   zwei Minuten.
3. Über "Wine-Konfiguration" prüfen, ob Wine läuft, oder mit "Programm
   starten …" eine `.exe` ausführen.

Alles, was Wine ausgibt, steht im Log-Bereich unten. "Kopieren" legt es in die
Zwischenablage.

## Steam

"Steam einrichten" (Gamecontroller-Knopf oben links) legt eine Bottle namens
Steam an, lädt den Windows-Installer von Valve, installiert ihn und startet
Steam. Beim ersten Start aktualisiert sich Steam selbst; das dauert einige
Minuten.

### Warum Steam eine Hilfsbibliothek braucht

Das Steam-Fenster ist eine eingebettete Chromium-Oberfläche. Chromium zeichnet
aus einem zweiten Prozess in das Fenster, und Wines Mac-Treiber kann das nicht
darstellen: Das Fenster bleibt schwarz. Chromiums Schalter `--in-process-gpu`
verlegt das Zeichnen in den Hauptprozess, aber Steam reicht seinen eigenen
Startparameter `-cef-in-process-gpu` nicht an Chromium weiter (auf einem Mac
mit Wine Staging 11.21 und dem Steam-Client vom November 2026 nachgeprüft).

Kelter legt deshalb vor jedem Steam-Start eine kleine Hilfsbibliothek in die
Bottle:

- `windows/system32/winmm.dll` ist die Hilfsbibliothek aus
  `Resources/steam-ui-fix/`. Ein Registrierungseintrag sorgt dafür, dass nur
  `steamwebhelper.exe` sie lädt; alle anderen Programme benutzen weiter Wines
  eigenes winmm.
- `windows/system32/winmm_orig.dll` ist eine Kopie von Wines winmm. Die
  Hilfsbibliothek leitet jeden Aufruf dorthin weiter.
- Beim Laden hängt sie die Browser-Parameter aus `runtimes.json`
  (`steam.uiFix.browserArguments`, Standard `--in-process-gpu`) an die
  Kommandozeile von Steams Browser-Prozess an.

An Steams eigenen Dateien ändert Kelter nichts, Steam-Updates machen die
Korrektur also nicht rückgängig. Abschalten lässt sie sich mit
`"enabled": false` unter `steam.uiFix`.

Der Quelltext liegt in `Tools/steam-ui-fix/winmm_proxy.c`. Neu bauen:

```sh
bash Tools/steam-ui-fix/build.sh    # braucht clang, lld-link und llvm-dlltool
```

Zusätzlich startet Kelter Steam mit `-cef-disable-gpu
-cef-disable-gpu-compositing`. Die Oberfläche wird dann ohne
Grafikbeschleunigung gezeichnet; mit ihr stürzt Chromiums Grafikteil unter
Wines eingebautem Direct3D ab. Das betrifft nur das Steam-Fenster, nicht die
Spiele.

### Steam-Overlay

Steam lädt in jedes Spiel seine Overlay-Bibliothek `gameoverlayrenderer.dll`.
Unter Wine auf dem Mac bleibt das Spiel danach stehen: Half-Life 2 lud nach
ihr keine weitere Datei mehr und beendete sich nach rund einer Minute. Kelter
schaltet die Bibliothek deshalb für Steam und alle daraus gestarteten Spiele
ab (`steam.dllOverrides` in `runtimes.json`). Das Overlay im Spiel (Shift+Tab)
gibt es dadurch nicht.

"Steam beenden" bittet Steam, sich zu schließen, und beendet danach alle
Wine-Prozesse der Bottle.

## Wenn ein Spiel nicht startet

1. In der Bottle "Ausführliches Wine-Log" einschalten und Steam neu starten.
   Wine schreibt dann mit, welche Bibliotheken es lädt, wo Fehler auftreten
   und welche Windows-Funktionen ihm fehlen. Das Log wird dadurch schnell
   groß, deshalb danach wieder ausschalten.
2. Das Spiel starten und warten, bis es sich beendet oder hängen bleibt.
3. Im Log-Bereich "Diagnose sammeln …" drücken und einen Ordner wählen.
   Kelter legt dort einen Ordner `Kelter-Diagnose-<Datum>-<Zeit>` an mit:
   Kelters Log, den Einstellungen der Bottle, Steams eigenen Logs, der Liste
   der laufenden Wine-Prozesse, der Liste der installierten Spiele und den
   Konsolen-Logs von Source-Spielen (Startoption `-condebug`).

Der Ordner bleibt auf dem Mac. Steams Logs können den Kontonamen enthalten.

## Wo Kelter Daten ablegt

Alles liegt unter `~/Library/Application Support/Kelter/`:

| Pfad | Inhalt |
| --- | --- |
| `Runtimes/wine/<Version>/` | das entpackte Wine |
| `Bottles/<ID>/bottle.json` | Name und Einstellungen einer Bottle |
| `Bottles/<ID>/prefix/` | die Windows-Umgebung (WINEPREFIX) |
| `Logs/kelter.log` | Ausgabe von Kelter und Wine |
| `runtimes.json` | optional: eigene Konfiguration, hat Vorrang |

Um Kelter vollständig zu entfernen, genügt es, diesen Ordner zu löschen.

## Konfiguration: `runtimes.json`

Welches Wine-Build geladen wird, steht in `Resources/runtimes.json`, nicht im
Code. Für ein anderes Build die Datei nach
`~/Library/Application Support/Kelter/runtimes.json` kopieren und anpassen:

| Feld | Bedeutung |
| --- | --- |
| `version`, `url`, `sha256` | Version, Download-Adresse und Prüfsumme des Archivs |
| `archiveRoot` | oberster Ordner im Archiv |
| `binDirectory`, `libDirectory` | Lage von `wine` und der Bibliotheken darin |
| `supportsESync`, `supportsMSync` | ob das Build diese Schalter kennt |

Unter `support` steht ein zweites Paket, das zum Wine-Build gehört: die
Bibliotheken, die Wine zur Laufzeit lädt, und die Grafikschichten.

| Feld | Bedeutung |
| --- | --- |
| `libraryPaths` | Ordner mit Laufzeitbibliotheken (FreeType, GnuTLS, MoltenVK …) |
| `vulkanDriverFile` | Beschreibung des Vulkan-Treibers (MoltenVK) |
| `renderers` | Grafikschichten: Kennung, Umgebungsvariable des Wine-Builds, Ordner |
| `removeAfterInstall` | Pfade, die nach dem Entpacken gelöscht werden |
| `environment` | zusätzliche Umgebungsvariablen für jeden Wine-Prozess |

## Wine-Build und Grafik

Voreingestellt ist Wine Staging 11.21 von Gcenx, ohne Zusatzpaket und ohne
ESync oder MSync. Pro Bottle lässt sich die Grafik wählen:

| Auswahl | DirectX 9 | DirectX 10/11 | DirectX 12 |
| --- | --- | --- | --- |
| Wine (eingebaut) | OpenGL | OpenGL | nicht unterstützt |
| DXMT | OpenGL | DXMT (Metal) | nicht unterstützt |

Wine sucht seine eingebauten Bibliotheken zuerst im eigenen Ordner. Eine
Grafikschicht, die `d3d11.dll` ersetzt, muss deshalb in einem Wine-Baum liegen.
Kelter verändert dafür nicht das eine Wine, das alle Bottles benutzen, sondern
legt pro Schicht eine Kopie an (`Runtimes/wine-variants/`) und startet eine
Bottle mit dem Baum, der zu ihrer Auswahl passt. Auf APFS ist die Kopie ein
Klon und belegt kaum zusätzlichen Platz. Welche Schichten es gibt, steht unter
`graphicsLayers` in `runtimes.json`.

Kelter kann auch ein Wine-Build mit Zusatzpaket benutzen (Abschnitt `support`
in `runtimes.json`): Dann lässt sich pro Bottle wählen, ob Direct3D über DXMT
oder DXVK läuft, und DirectX 8/9 gehen über D9VK. Erprobt wurde das mit der
Sikarugir-Engine (Wine 11.0) und dem Sikarugir-Template 1.0.15. Auf einem
MacBook Air mit macOS 26.6 brach dort aber jeder Wine-Prozess gleich nach dem
Laden von ntdll ab (`run_wineboot failed to start wineboot 1`), unabhängig von
den gesetzten Umgebungsvariablen. `Tools/wine-test.sh` stellt das nach. Solange
die Ursache offen ist, bleibt es beim Gcenx-Build.

## Architektur

```
Sources/
  KelterCore/   Pfade, Konfiguration, Bottle-Verwaltung, Logdatei (nur Foundation)
  KelterWine/   Wine laden, entpacken und starten; Rosetta-Prüfung
  KelterSteam/  Steam installieren, starten und beenden; Fensterkorrektur
  KelterApp/    SwiftUI-Oberfläche
Tools/
  steam-ui-fix/ Quelltext und Bauskript der Hilfsbibliothek für das Steam-Fenster
Tests/
  KelterCoreTests/   BottleStore, Konfiguration, Pfade, Log
  KelterWineTests/   Umgebungsvariablen, Pfade, Prüfsumme
  KelterSteamTests/  Steam-Pfade, Startparameter, Fensterkorrektur
```

- `WineRunner` ist die einzige Stelle, die Wine startet. Er setzt `WINEPREFIX`
  und die Umgebungsvariablen der Bottle.
- Wine schreibt in eine Logdatei statt in eine Pipe, weil seine
  Hintergrundprozesse länger leben als das gestartete Programm. Die Oberfläche
  liest die Datei mit.
- `BottleStore` benennt Ordner nach einer ID, nicht nach dem Namen. Umbenennen
  verschiebt deshalb nie eine Windows-Umgebung.

## Grenzen

- Spiele mit Kernel-Anti-Cheat laufen unter Wine nicht.
- DirectX-12-Spiele brauchen Apples D3DMetal. Kelter liefert es nicht mit und
  wird es aus einem selbst geladenen Game Porting Toolkit übernehmen.
