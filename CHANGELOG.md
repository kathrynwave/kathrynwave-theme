# Changelog

## 0.1.0 - 2026-05-20

Initial kathrynwave tester release for Ubuntu 26.

- Added stable GNOME Terminal palette and Bash prompt install/uninstall scripts.
- Added tester-ready adaptive desktop chrome color installer for GTK3 and
  GTK4/libadwaita. It keeps static GNOME Shell top-panel and transparent
  bottom-dock accents plus a static kathrynwave legacy window decoration so GNOME's
  normal light/dark switcher can control the installed GTK side.
- Scoped desktop chrome support to Ubuntu 26 only.
- Added desktop installer preflight reporting with `--check`.
- Preserved Desktop Icons NG/DING transparency so wallpaper remains visible.
- Added bundled kathrynwave official day/night wallpapers, adaptive desktop
  palettes, Terminal chrome set to `system`, and Ubuntu accent color set to
  `pink`.
- Positioned the release as kathrynwave, a feel good Ubuntu 26 theme based on
  Ubuntu Yaru, and licensed the original project wallpapers under CC BY 4.0.
- Updated the shipped day wallpaper and final light/dark desktop previews.
- Added explicit GTK3 Terminal tab label, spinner, and backdrop contrast rules
  for readable inactive tabs.
- Added a bright cyan GTK3 Terminal active-tab underline so the selected tab is
  clear in both day and night palettes.
- Swapped day-mode Terminal tab colors so the active tab is the light raised tab
  and inactive tabs recede into pink.
- Forced GTK3 Terminal headerbar controls to stay white in focused and
  unfocused windows.
- Forced GTK4/libadwaita backdrop window controls to stay white so Terminal
  minimize, maximize, and close buttons remain readable.
- Updated legacy Terminal window-control assets to use white glyphs without
  dark gray circular fills.
- Kept icons, cursors, fonts, and spacing unchanged.
- Added rollback handling and isolated fake-HOME regression tests.
