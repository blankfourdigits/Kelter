# Security policy

## Reporting a vulnerability

Please **don't** report security problems in a public issue. Use GitHub's
private reporting instead:
[Report a vulnerability](https://github.com/blankfourdigits/Kelter/security/advisories/new)
(Security tab → "Report a vulnerability").

Please include what is affected, how to reproduce it and what an attacker
could do with it. You'll get an answer as soon as possible; this is a
volunteer project, so please allow a few days.

## Scope

In scope is Kelter's own code in this repository, for example:

- downloading and checking runtimes (checksums, paths from `runtimes.json`,
  unpacking archives, mounting disk images)
- how Kelter starts Wine, Winetricks and Steam (arguments, environment)
- the Steam helper library in `Tools/steam-ui-fix/` and Kelter's Wine patches
  in `Tools/wine-patches/`

Out of scope are problems in the projects Kelter downloads (Wine, DXMT,
Winetricks, Steam, Apple's Game Porting Toolkit) and in Windows programs run
inside a bottle; please report those to their maintainers. Keep in mind that
Windows programs in a bottle run with your user's rights on the Mac, like
under any Wine setup.

## Supported versions

Kelter is in an early stage. Fixes go into the `main` branch; there are no
separately maintained releases yet.
