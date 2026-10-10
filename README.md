# ghostnim

A terminal emulator written in [Flutter](https://flutter.dev) (Linux
desktop), built on
**libghostty-vt**, the embeddable C library for
[Ghostty](https://ghostty.org)'s terminal core.

![ghostnim screenshot](docs/screenshot.png)

libghostty-vt does the actual terminal work: VT parsing, screen and scrollback
state, reflow on resize, key and mouse encoding, selection, and the **render
state**, a snapshot of exactly what to draw with per-row dirty tracking.
ghostnim supplies the rest: the window, glyph rendering, a pty and the UI,
with widgets from [flatkit](https://github.com/codegod100/flutterkit). It
talks to libghostty-vt through `dart:ffi`. (The name is from its first
version, written in Nim; that code is in the git history.)

## Features

- Rendering driven by libghostty's render-state API. Only the rows libghostty
  marks dirty are redrawn; each row's drawing is cached as a picture.
- Truecolor and 256 colours. Bold, italic, faint, inverse, invisible,
  underline, double underline, strikethrough and overline.
- Wide characters, plus per-glyph font fallback (CJK, symbols, emoji).
- Font shaping: programming ligatures (Monaspace Frozen,
  JetBrains Mono, Fira Code) and contextual alternates (Monaspace's texture healing), kept on
  the cell grid.
- Box-drawing and block characters drawn procedurally, so lines join
  seamlessly between cells.
- Cursor shapes (block, bar, underline, hollow) with blinking.
- Keyboard input through libghostty's key encoder: legacy/xterm sequences,
  DECCKM, and the kitty keyboard protocol when an app requests it.
- Mouse reporting through libghostty's mouse encoder (X10/normal/button/any,
  SGR and more). Hold Shift to select instead.
- Mouse selection, copy (Ctrl+Shift+C), paste (Ctrl+Shift+V or middle click)
  with bracketed paste. Double-click selects the word under the pointer,
  where a "word" is as much as you'd want: a whole URL, path
  (`src/foo.nim:12:3`), flag (`--color=auto`), e-mail address or
  `host:port`, without the sentence punctuation after it. Triple-click
  selects the line. Keep dragging after a double or triple click to extend
  by words or lines. Every selection, Select All included, is copied to the
  clipboard as soon as it's made (turn off with `copy-on-select #false`).
- Ctrl+click opens links with `xdg-open`: OSC 8 hyperlinks, and URLs in the
  text (`https://`, `http://`, `file://`, `mailto:`, `www.` and a few more),
  even when they wrap onto the next line. The pointer turns into a hand over
  a link while Ctrl is held. It works when the application has mouse
  reporting on, too.
- Ctrl+click a path to open it in a new tab: a directory opens a new tab
  there, a file opens in `$VISUAL`/`$EDITOR` in a new tab (or with
  `xdg-open` when neither is set). Relative paths are taken from the tab's
  directory, so the names `ls` prints work, and `src/foo.nim:12:3`,
  git's `a/`/`b/` prefixes and `ls -F`'s `*`/`@` are understood. `file://`
  links to directories (`ls --hyperlink`) open in a new tab too.
- Right-click context menu with Copy, Paste, Select All, zoom, Show/Hide
  Recent Folders,
  Show/Hide File Manager, Open Folder in Editor and Open Config, drawn in-window and navigable with the
  arrow keys and Enter. When the application has mouse reporting on, hold
  Shift to open it.
- Scrollback with the mouse wheel or Shift+PageUp/PageDown.
- Tabs, each with its own shell and terminal state. The tab bar shows each
  tab's OSC title. Click a tab to switch to it, click × (or middle-click the
  tab) to close it, and click + to open a new one. Drag a tab along the bar to
  reorder it. The mouse wheel over the bar also switches tabs. New tabs start in the current tab's directory.
  Keys: Ctrl+Shift+T new tab, Ctrl+Shift+W close tab, Ctrl+Tab /
  Ctrl+Shift+Tab (or Ctrl+PageDown / Ctrl+PageUp) next / previous tab.
- Recent folders: a strip under the tabs shows the directories you've been in,
  most visited first (ties go to the most recent), as many as fit. The list
  is shared by all tabs and windows and leaves out the current tab's own
  directory.
  Click one to `cd` there, or
  middle-click it to open it in a new tab; if a program is running in the
  tab, a click opens a new tab too. Turn the strip on or off from the
  right-click menu. The folders and their visit counts, and whether the
  strip is shown, are remembered in
  `$XDG_STATE_HOME/ghostnim` (`~/.local/state/ghostnim`).
- File manager: Ctrl+Shift+E (or Show File Manager in the right-click menu)
  splits a folder listing off the left of the window. It shows the current
  tab's directory and follows it as you `cd` or switch tabs. Click a folder to
  `cd` there (while a program is running in the tab, the pane just browses
  there on its own), double-click a file to open it with `xdg-open`,
  middle-click a file to type its quoted path into the terminal, or
  middle-click a folder to open a new tab in it. The listing updates when
  files are added or removed. Hidden files (dotfiles) are left out until you
  press Ctrl+H in the pane or pick Show Hidden Files from the right-click
  menu; then they're listed, drawn fainter. Drag the divider to resize the
  pane; whether it's shown, its width and whether it lists hidden files are
  remembered in `$XDG_STATE_HOME/ghostnim`.
  Showing the pane gives it the keyboard (its selection turns the accent
  colour and the terminal's cursor goes hollow): Up/Down, PageUp/PageDown
  and Home/End move, Enter or Right goes into a folder or opens a file,
  Left or Backspace goes up to the parent folder, typing a name's first
  letters jumps to it, Shift+Enter types the selected path into the
  terminal, and Escape (or a click in the terminal) hands the keyboard back.
  To filter the listing by name, press `/` or Ctrl+F in the pane (or pick
  Filter Files from the right-click menu) and type: only entries whose names
  contain the text (in any case) are listed, with the filter shown in the
  pane's header. Backspace edits it, Enter opens the selected match, and
  Escape clears the filter; going to another folder clears it too.
  Ctrl+Shift+E focuses a pane that's already shown, and hides it once it has
  focus.
- Open Folder in Editor: Ctrl+Shift+O (or the right-click menu) opens the
  current folder in `$VISUAL`/`$EDITOR` in a new tab there, the way
  `$EDITOR .` would (in `vi` when neither is set). The folder is the one the
  file manager shows while it's open, else the current tab's directory.
  Launched from a desktop menu, ghostnim asks your shell for `$VISUAL`/`$EDITOR`
  when they aren't in its own environment, and if the editor fails its tab
  stays open with the exit status instead of closing.
- Window title from OSC 0/2, live resize with reflow, HiDPI.
- Font zoom: Ctrl+= (or Ctrl++) / Ctrl+- / Ctrl+0.
- A KDL config file for fonts, window size, shell, start directory, colours
  and keybindings, reloaded live when saved (see [Config file](#config-file)).

## Building

### 1. Dependencies

- [Flutter](https://docs.flutter.dev/get-started/install/linux/desktop) 3.x
  with Linux desktop support (clang, cmake, ninja, pkg-config and the GTK 3
  development package)
- curl, to fetch the prebuilt libghostty-vt, or Zig 0.16 and git to build it

On Debian/Ubuntu, besides Flutter:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev curl
```

The default font, Monaspace Neon Frozen, isn't packaged by most distros:
copy `fonts/frozen/MonaspaceNeonFrozen-*.ttf` from a
[Monaspace release](https://github.com/githubnext/monaspace/releases) into
`~/.local/share/fonts` (the AppImage bundles it). Without it ghostnim uses
Monaspace Neon if that's installed, else DejaVu Sans Mono or your system's
`monospace` font.

### 2. Get libghostty-vt

```sh
sh scripts/fetch-libghostty-vt.sh    # prebuilt, from the libghostty-vt release
# or build it yourself (needs Zig 0.16):
sh scripts/build-libghostty-vt.sh
```

Either way the headers and libraries land in `vendor/ghostty-vt`. The
prebuilt one comes from `.github/workflows/libghostty-vt.yml`, which builds the
Ghostty commit pinned in `scripts/build-libghostty-vt.sh` whenever that pin
changes. To use a libghostty-vt you already have, pass
`-DGHOSTTY_VT_PREFIX=/path/to/prefix` to CMake (or edit `linux/CMakeLists.txt`).

### 3. Build ghostnim

```sh
flutter build linux --release
build/linux/x64/release/bundle/ghostnim
```

The bundle carries `lib/libghostty-vt.so` next to the Flutter libraries. For
development, `flutter run -d linux` works too, and `flutter test` runs the
unit tests.

### AppImage

```sh
sh scripts/build-appimage.sh
```

This builds the release bundle and packages it with
[appimagetool](https://github.com/AppImage/appimagetool), which is downloaded
into `build/tools` on first use. The result is
`ghostnim-<version>-<arch>.AppImage` in the repository root. Monaspace Neon
Frozen (the default font), DejaVu Sans Mono and Symbols Nerd Font are bundled
and loaded at startup; other fonts are found through the host's fontconfig.
GTK 3 comes from the host, as for any Flutter app.

### Prebuilt AppImage and updates

CI (`.github/workflows/appimage.yml`) builds the AppImage on every push and
pull request, and each push to `main` publishes it to the
[`release`](https://github.com/codegod100/ghostnim/releases/tag/release)
release as `ghostnim-x86_64.AppImage`, replacing the previous build (there are
no per-build versioned releases).

Those builds update themselves: at most once a day, on launch, a background
process compares the running AppImage with the `release` release (by the SHA-1
in its `.zsync` file). If they differ, it downloads the new AppImage, checks
it, and replaces the file in place, so the next launch runs the new version.
This needs `curl` and `sha1sum` on the host and a writable AppImage file; set
`GHOSTNIM_NO_UPDATE=1` to turn it off. **Check for Updates** in the
right-click menu runs the same check right away, and reports the result as a
desktop notification (via `notify-send`, if installed). The update information is also
embedded in the AppImage, so AppImageUpdate, Gear Lever and similar tools can
update it too. Locally built AppImages don't self-update unless built with
`FLUTTER_FLAGS=--dart-define=AUTO_UPDATE=true`.

### conda package

The same CI build is packaged with [rattler-build](https://rattler.build)
(`recipe/recipe.yaml`) and published from `main` to the `nandi-testing` channel
on prefix.dev:

```sh
pixi global install -c https://prefix.dev/nandi-testing -c conda-forge ghostnim
```

GTK 3 comes from the host, as with the AppImage. To build the package
locally, run `sh scripts/build-appimage.sh`, then
`rattler-build build --recipe recipe`.

## Usage

```
ghostnim [options] [-e command [args...]]

  -c, --config FILE      config file  [$XDG_CONFIG_HOME/ghostnim/config.kdl]
  -f, --font NAME|PATH   font family or font file                 [Monaspace Neon Frozen]
  -s, --size N           font size in points                      [14]
      --no-font-shaping  draw characters one by one: no ligatures or
                         contextual alternates
      --cols N           initial columns                          [100]
      --rows N           initial rows                             [30]
      --scrollback N     scrollback lines                         [10000]
  -d, --working-directory DIR  start the first tab in DIR  [current directory]
      --no-inherit-directory   start new tabs in the working directory too,
                         not in the current tab's directory
  -e, --exec CMD ...     run CMD instead of $SHELL (must be last)
```

ghostnim sets `TERM=xterm-256color` for the child process.

### Config file

Settings can also go in a [KDL](https://kdl.dev) file at
`$XDG_CONFIG_HOME/ghostnim/config.kdl` (usually
`~/.config/ghostnim/config.kdl`), or wherever `--config` points. Each setting
is a node named after its command-line option, and the command line wins:

```kdl
font "Monaspace Neon"
font-size 13
font-shaping #false    // no ligatures or contextual alternates
cols 120
rows 36
scrollback 50000
command "fish" "--login"
working-directory "~/code"
inherit-directory #false     // new tabs start in working-directory too
copy-on-select #false        // selecting text doesn't copy it

colors {
  foreground "#c0caf5"
  background "#1a1b26"
  cursor "#c0caf5"
  selection-foreground "#c0caf5"
  selection-background "#33467c"
  palette 1 "#f7768e"   // one line per 256-colour palette entry to change
}

keybinds {
  alt+1 goto-tab 1
  ctrl+shift+enter send-text "\n"
  ctrl+shift+w none     // unbind a default
  "ctrl+=" font-bigger  // quote chords containing = / ; [ ] \
}
```

Keybindings add to the defaults listed under Features (use
`keybinds clear-defaults=#true { ... }` to start from none). Actions: `copy`,
`paste`, `select-all`, `new-tab`, `close-tab`, `next-tab`, `previous-tab`,
`goto-tab N`, `scroll-page-up`, `scroll-page-down`, `scroll-to-top`,
`scroll-to-bottom`, `font-bigger`, `font-smaller`, `font-reset`,
`send-text "..."`, `reload-config`, `open-config`, `toggle-file-pane`, `toggle-hidden-files`,
`open-folder-in-editor` and `none`.

**Open Config** in the right-click menu (or Ctrl+,) opens the file in
`$VISUAL`/`$EDITOR` in a new tab, or with `xdg-open` if neither is set. If
the file doesn't exist yet it's created from `docs/config.kdl` first.

The config reloads itself when you save it, or on Ctrl+Shift+, (comma). Font,
font shaping, colours, keybindings and scrollback change in the open window; `command`,
`working-directory` and `inherit-directory` apply to new tabs, and
`cols`/`rows` only size the first window.
`working-directory` is only used when ghostnim is launched from your home
directory or `/` (as desktop launchers do), so a file manager's "Open
Terminal Here" still opens in the folder you picked. A file that doesn't parse is skipped and the previous settings stay.

[`docs/config.kdl`](docs/config.kdl) lists every setting with its default and
what it does, so it's a good starting point to copy.
Mistakes such as an unknown setting or a value out of range are reported on
stderr and skipped, so a broken config never stops the terminal from starting.

## Layout

| File | Purpose |
| --- | --- |
| `lib/main.dart` | Entry point: command line, config, `runApp` |
| `lib/src/app.dart` | The window: tabs, folder strip, file pane, terminal view, menu, keyboard and mouse, selection, clipboard |
| `lib/src/session.dart` | One tab: libghostty terminal, render state snapshot, pty, key/mouse encoders |
| `lib/src/renderer.dart` | Paints the render state: cells, decorations, cursor, cached row pictures |
| `lib/src/boxdraw.dart` | Procedural box-drawing and block elements |
| `lib/src/vt.dart` | `dart:ffi` bindings for the libghostty-vt C API |
| `lib/src/keys.dart` | `GhosttyKey` values (generated from `key/event.h`) |
| `lib/src/input.dart` | Flutter physical key/modifier → libghostty key mapping |
| `lib/src/file_pane.dart` | The file manager pane: folder listing and its widget |
| `lib/src/state.dart` | Recent folders and pane settings, `xdg-open`, `$EDITOR` |
| `lib/src/options.dart` | Command line parsing, merged over the config |
| `lib/src/config.dart` | Loads the KDL config file |
| `lib/src/keybinds.dart` | Key chords, actions and the default keybindings |
| `lib/src/kdl.dart` | Small dependency-free KDL parser |
| `lib/src/links.dart`, `wordsel.dart`, `paths.dart` | URL, word and path detection under the pointer |
| `lib/src/update.dart` | Background self-update for CI-built AppImages |
| `linux/runner/` | GTK runner, plus the `ghostnim/window` channel for the title and size |

## Notes

- libghostty-vt's API is still pre-1.0. The bindings target the commit pinned
  in `scripts/build-libghostty-vt.sh`.
- Not implemented yet: Kitty graphics, and input methods (IME) / dead keys:
  keys go straight to libghostty's key encoder.
