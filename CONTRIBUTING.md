# Contributing

Thanks for your interest in Kelter. Contributions are welcome: game reports,
bug reports, translations and code.

## Game reports

A short report already helps a lot. The easiest way is the **Game report**
form when you open a new issue; it asks for:

- the game and its Steam page (or app ID)
- Mac model and macOS version
- the graphics chosen in Kelter (Wine built-in, DXMT)
- what happens: runs, graphics glitches, crashes when …, doesn't start
- for problems: the relevant lines from the log (View → Test view). Please
  look through the folder from "Collect diagnostics …" before sharing it;
  Steam's logs may contain your account name.

Problems in Kelter itself go into a **Bug report**. Security problems please
report privately, see [SECURITY.md](SECURITY.md).

## Building and testing

```sh
swift build          # compile
swift test           # all tests
swift run Kelter     # run (without app bundle, without translations)
bash scripts/make-app.sh && open build/Kelter.app   # the real app
```

Kelter is a Swift package (Swift 5.9, macOS 15); no Xcode project is needed,
but `Package.swift` opens in Xcode. GitHub builds and tests every push and
pull request on an Apple Silicon Mac (`.github/workflows/ci.yml`).

## Rules for changes

- **Before every commit**, `swift build` and `swift test` must pass without
  errors and without new warnings.
- **Every change in logic comes with a test.** Wine itself is never started
  in tests; tests cover paths, environment, arguments and file operations in
  temporary folders.
- **Every Wine call goes through `WineRunner`.**
- **No fixed versions, URLs or checksums in the code:** what Kelter downloads
  belongs in `Resources/runtimes.json`. On structural changes, increase
  `schemaVersion` and adjust the test in
  `Tests/KelterCoreTests/RuntimeConfigAndLogTests.swift`.
- **No binaries of foreign origin and no proprietary components** in the
  repository. The exception is the self-built
  `Resources/steam-ui-fix/winmm.dll`, whose source is included.
- **Apple's files** (D3DMetal, Game Porting Toolkit) are not changed, not
  disassembled and not redistributed; fixes belong in Wine
  (`Tools/wine-patches/`).
- **Texts:** the interface is German with an English translation. Add new
  texts as a fixed SwiftUI literal or through `loc("…")`, using the German
  text as the key, and add the translation to
  `Resources/en.lproj/Localizable.strings`; `LocalizationTests` checks this.
- Code comments and identifiers in English.

## License

By contributing you agree that your contribution is published under the
GPLv3, like the rest of Kelter. Changes to Wine (`Tools/wine-patches/`) are
licensed under the LGPL, like Wine.
