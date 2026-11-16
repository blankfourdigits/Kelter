# Mitmachen

Danke für dein Interesse an Kelter. Beiträge sind willkommen: Berichte zu
Spielen, Fehlermeldungen, Übersetzungen und Code.

## Erfahrungen mit Spielen

Ein kurzer Bericht hilft schon sehr. Bitte nenne:

- Spiel und Steam-Seite (oder App-ID)
- Mac-Modell und macOS-Version
- Grafik in Kelter (Wine eingebaut, DXMT)
- was passiert: läuft, Bildfehler, stürzt ab bei …, startet nicht
- bei Problemen: die wichtigsten Zeilen aus dem Log (Darstellung →
  Testansicht). Den Ordner von „Diagnose sammeln …“ bitte vorher durchsehen;
  Steams Logs können deinen Kontonamen enthalten.

## Bauen und testen

```sh
swift build          # kompilieren
swift test           # alle Tests
swift run Kelter     # starten (ohne App-Bundle, ohne Übersetzungen)
bash scripts/make-app.sh && open build/Kelter.app   # richtige App
```

Swift Package (Swift 5.9, macOS 15), kein Xcode-Projekt nötig;
`Package.swift` lässt sich aber in Xcode öffnen.

## Regeln für Änderungen

- **Vor jedem Commit** müssen `swift build` und `swift test` ohne Fehler und
  ohne neue Warnungen durchlaufen.
- **Zu jeder Logikänderung ein Test.** Wine selbst wird in Tests nie
  gestartet; getestet werden Pfade, Umgebung, Argumente und Dateioperationen
  in temporären Ordnern.
- **Alle Wine-Aufrufe laufen über `WineRunner`.**
- **Keine festen Versionen, URLs oder Prüfsummen im Code:** Was Kelter lädt,
  gehört in `Resources/runtimes.json`. Bei Strukturänderungen
  `schemaVersion` erhöhen und den Test in
  `Tests/KelterCoreTests/RuntimeConfigAndLogTests.swift` anpassen.
- **Keine Binärdateien fremder Herkunft und keine proprietären Bestandteile**
  im Repository. Ausnahme ist die selbst gebaute
  `Resources/steam-ui-fix/winmm.dll`, deren Quelltext beiliegt.
- **Apples Dateien** (D3DMetal, Game Porting Toolkit) werden nicht
  verändert, nicht disassembliert und nicht weitergegeben; Lösungen gehören
  in Wine (`Tools/wine-patches/`).
- **Texte:** Die Oberfläche ist deutsch, mit englischer Übersetzung. Neue
  Texte als festes SwiftUI-Literal oder über `loc("…")`, dann die
  Übersetzung in `Resources/en.lproj/Localizable.strings` ergänzen;
  `LocalizationTests` prüft das.
- Code-Kommentare und Bezeichner auf Englisch, Commit-Nachrichten gern auf
  Deutsch: eine Zeile, was sich ändert, darunter kurz warum.

## Lizenz

Mit einem Beitrag stimmst du zu, dass er unter der GPLv3 veröffentlicht wird,
wie der Rest von Kelter. Änderungen an Wine (`Tools/wine-patches/`) stehen
wie Wine unter der LGPL.
