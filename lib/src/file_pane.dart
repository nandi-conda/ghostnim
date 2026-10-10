/// The file manager pane: a folder listing split off the left of the window,
/// next to the terminal. It follows the current tab's working directory.
library;

import 'dart:io';

import 'package:flatkit/flatkit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';

const _maxEntries = 5000; // enough for any folder worth browsing

class Entry {
  final String name;
  final bool isDir;
  const Entry(this.name, {this.isDir = false});
  bool get isHidden => name.startsWith('.') && name != '..';
}

/// What the pane lists and where its selection is.
class FilePaneModel {
  String dir = ''; // the folder listed
  List<Entry> _all = []; // ".." (except at /), then folders, then files
  List<Entry> entries = []; // those of _all matching the filter
  DateTime? _stamp; // the folder's mtime when it was listed
  int scroll = 0; // first entry shown
  int hovered = -1, selected = -1; // entry indexes, -1 for none
  bool showHidden = false; // list dotfiles too
  String filter = ''; // only list names containing this (any case)
  bool filtering = false; // typing goes into the filter

  static DateTime? _mtime(String dir) {
    try {
      return Directory(dir).statSync().modified;
    } on FileSystemException {
      return null;
    }
  }

  /// The folder's entries, dotfiles only if [hidden]: folders first, each
  /// group by name.
  static List<Entry> _list(String dir, bool hidden) {
    final dirs = <Entry>[], files = <Entry>[];
    try {
      for (final e in Directory(dir).listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.') && !hidden) continue;
        var isDir = e is Directory;
        if (e is Link) isDir = FileSystemEntity.isDirectorySync(e.path);
        (isDir ? dirs : files).add(Entry(name, isDir: isDir));
        if (dirs.length + files.length >= _maxEntries) break;
      }
    } on FileSystemException {
      // unreadable: list what we have
    }
    int byName(Entry a, Entry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    dirs.sort(byName);
    files.sort(byName);
    return [if (dir != '/') const Entry('..', isDir: true), ...dirs, ...files];
  }

  /// The full path of entry [i].
  String path(int i) => entries[i].name == '..' ? p.dirname(dir) : p.join(dir, entries[i].name);

  bool _matches(Entry e, String filter) =>
      filter.isEmpty || (e.name != '..' && e.name.toLowerCase().contains(filter.toLowerCase()));

  /// List [newDir], from the top and unfiltered unless it's the folder
  /// already shown.
  void load(String newDir) {
    if (newDir != dir) {
      scroll = 0;
      selected = -1;
      hovered = -1;
      filter = '';
      filtering = false;
    }
    dir = newDir;
    _stamp = _mtime(dir);
    _all = _list(dir, showHidden);
    entries = [
      for (final e in _all)
        if (_matches(e, filter)) e
    ];
    scroll = scroll.clamp(0, entries.isEmpty ? 0 : entries.length - 1);
    if (selected >= entries.length) selected = -1;
  }

  /// List the folder again, keeping the selection on the same name.
  void _reload() {
    final selName = selected >= 0 ? entries[selected].name : '';
    load(dir);
    selected = entries.indexWhere((e) => e.name == selName);
  }

  /// List the folder again if something was added, removed or renamed in it.
  void refresh() {
    if (dir.isEmpty) return;
    if (!dirExists(dir)) {
      var up = dir;
      while (up.length > 1 && !dirExists(up)) {
        up = p.dirname(up);
      }
      load(up);
    } else if (_mtime(dir) != _stamp) {
      _reload();
    }
  }

  /// List dotfiles or not, keeping the selected entry if it's still there.
  void setShowHidden(bool on) {
    if (on == showHidden) return;
    showHidden = on;
    if (dir.isNotEmpty) _reload();
  }

  /// List only the names containing [f], keeping the selected entry if it
  /// still matches, else selecting the first match.
  void setFilter(String f) {
    final selName = selected >= 0 ? entries[selected].name : '';
    filter = f;
    entries = [
      for (final e in _all)
        if (_matches(e, f)) e
    ];
    hovered = -1;
    scroll = 0;
    selected = entries.isNotEmpty ? 0 : -1;
    final i = entries.indexWhere((e) => e.name == selName);
    if (i >= 0) selected = i;
  }

  void scrollBy(int delta, int rows) {
    scroll = (scroll + delta).clamp(0, (entries.length - rows).clamp(0, 1 << 30));
  }

  /// Select entry [i] (clamped), scrolling it into view in a pane showing
  /// [rows] entries.
  void select(int i, int rows) {
    if (entries.isEmpty) {
      selected = -1;
      return;
    }
    selected = i.clamp(0, entries.length - 1);
    rows = rows < 1 ? 1 : rows;
    if (selected < scroll) {
      scroll = selected;
    } else if (selected >= scroll + rows) {
      scroll = selected - rows + 1;
    }
  }

  /// Select the entry called [name], else the first one after "..".
  void selectName(String name, int rows) {
    final i = entries.indexWhere((e) => e.name == name);
    if (i >= 0) {
      select(i, rows);
    } else {
      select(entries.length > 1 && entries[0].name == '..' ? 1 : 0, rows);
    }
  }

  /// Type-ahead: select the next entry whose name starts with [prefix]. A
  /// one-letter prefix moves on from the selected entry, so repeating it
  /// cycles through the matches; a longer one may stay on it.
  void jumpTo(String prefix, int rows) {
    final n = entries.length;
    if (n == 0 || prefix.isEmpty) return;
    final start = prefix.length == 1 ? selected + 1 : (selected < 0 ? 0 : selected);
    for (var k = 0; k < n; k++) {
      final i = (start + k) % n;
      if (entries[i].name.toLowerCase().startsWith(prefix.toLowerCase())) {
        select(i, rows);
        return;
      }
    }
  }
}

// --- icons ----------------------------------------------------------------------

/// Icons by file name or extension (lowercase), with the terminal palette
/// entry to colour them: 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, 6 cyan;
/// -1 is the foreground.
const _nameIcons = <(String, IconData, int)>[
  ('makefile gnumakefile justfile', Icons.build_outlined, 1),
  ('dockerfile containerfile', Icons.inventory_2_outlined, 4),
  ('license licence copying license.md license.txt', Icons.gavel_outlined, 3),
  ('.gitignore .gitattributes .gitmodules', Icons.commit, 1),
  ('.bashrc .bash_profile .zshrc .zprofile .profile', Icons.terminal, 2),
];

const _extIcons = <(String, IconData, int)>[
  (
    'nim nims nimble zig rs go c h cpp cc cxx hpp hh hxx lua rb java kt kts swift php hs ex exs '
        'ml mli jl clj cljs scala dart py pyi js mjs cjs ts mts cts jsx tsx',
    Icons.code,
    4
  ),
  ('sh bash zsh fish', Icons.terminal, 2),
  ('html htm css scss sass svelte vue', Icons.web_outlined, 5),
  ('json jsonc toml yml yaml xml ini conf cfg kdl nix', Icons.data_object, 6),
  ('md markdown tex txt log rst', Icons.article_outlined, -1),
  ('csv tsv xls xlsx ods', Icons.table_chart_outlined, 2),
  ('sql db sqlite sqlite3', Icons.storage_outlined, 3),
  ('lock', Icons.lock_outline, -1),
  ('pdf', Icons.picture_as_pdf_outlined, 1),
  ('doc docx odt ppt pptx odp', Icons.description_outlined, 4),
  ('png jpg jpeg gif bmp webp ico tiff svg', Icons.image_outlined, 5),
  ('mp3 flac wav ogg opus m4a', Icons.audiotrack_outlined, 6),
  ('mp4 mkv webm mov avi', Icons.movie_outlined, 5),
  ('ttf otf woff woff2', Icons.font_download_outlined, 1),
  ('zip tar gz tgz xz bz2 zst 7z rar deb rpm appimage', Icons.archive_outlined, 3),
];

(IconData, int) fileIcon(String name) {
  final n = name.toLowerCase();
  for (final (keys, icon, color) in _nameIcons) {
    if (keys.split(' ').contains(n)) return (icon, color);
  }
  final dot = n.lastIndexOf('.');
  if (dot > 0) {
    final ext = n.substring(dot + 1);
    for (final (keys, icon, color) in _extIcons) {
      if (keys.split(' ').contains(ext)) return (icon, color);
    }
  }
  return (Icons.insert_drive_file_outlined, -1);
}

// --- view ---------------------------------------------------------------------------

Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

String _displayPath(String dir) {
  final home = homeDir().replaceAll(RegExp(r'/+$'), '');
  if (dir == home) return '~';
  if (dir.startsWith('$home/')) return '~${dir.substring(home.length)}';
  return dir;
}

/// Draws the pane from its model. Clicks, wheel and hover are reported back;
/// the app decides what they do.
class FilePaneView extends StatelessWidget {
  final FilePaneModel model;
  final double rowH;
  final bool focused;
  final Color background, foreground, accent;
  final List<Color> palette;
  final TextStyle textStyle;
  final void Function(int index, int button, int clicks) onClick;
  final void Function(int rows) onScroll;
  final void Function(int index) onHover;
  final void Function(int rows) onRows;

  const FilePaneView({
    super.key,
    required this.model,
    required this.rowH,
    required this.focused,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.palette,
    required this.textStyle,
    required this.onClick,
    required this.onScroll,
    required this.onHover,
    required this.onRows,
  });

  double get headerH => rowH + 4;

  @override
  Widget build(BuildContext context) {
    final bg = background, fg = foreground;
    final m = model;
    return LayoutBuilder(builder: (context, box) {
      final rows = ((box.maxHeight - headerH) / rowH).floor().clamp(0, 1 << 20);
      onRows(rows);
      final header = m.filtering || m.filter.isNotEmpty
          ? Row(children: [
              Flexible(
                child: Text('/${m.filter}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle.copyWith(color: m.filtering ? fg : mix(bg, fg, 0.6))),
              ),
              if (m.filtering && focused) Container(width: 2, height: rowH - 8, color: accent),
            ])
          : Text(_displayPath(m.dir),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: textStyle.copyWith(color: mix(bg, fg, 0.6)));
      final end = (m.scroll + rows).clamp(0, m.entries.length);
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) onScroll(e.scrollDelta.dy > 0 ? 3 : -3);
        },
        child: MouseRegion(
          onExit: (_) => onHover(-1),
          child: Container(
            color: mix(bg, fg, 0.04),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  height: headerH,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration:
                      BoxDecoration(border: Border(bottom: BorderSide(color: mix(bg, fg, 0.12)))),
                  child: KitTooltip(message: m.dir, child: header),
                ),
                for (var i = m.scroll; i < end; i++) _row(context, i),
                if (m.entries.isEmpty && m.filter.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    child: Text('No matches', style: textStyle.copyWith(color: mix(bg, fg, 0.45))),
                  ),
              ]),
              if (m.entries.length > rows && rows > 0) _scrollbar(rows),
            ]),
          ),
        ),
      );
    });
  }

  Widget _scrollbar(int rows) {
    final m = model;
    final trackH = rows * rowH;
    final thumbH = (trackH * rows / m.entries.length).clamp(rowH, trackH);
    final thumbY =
        headerH + (trackH - thumbH) * m.scroll / (m.entries.length - rows).clamp(1, 1 << 30);
    return Positioned(
      right: 2,
      top: thumbY,
      child: Container(
        width: 3,
        height: thumbH,
        decoration: BoxDecoration(
          color: mix(background, foreground, 0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final m = model;
    final e = m.entries[i];
    final bg = background, fg = foreground;
    final dim = e.isHidden ? 0.6 : 1.0; // dotfiles are drawn fainter
    Color? rowBg;
    if (i == m.selected) {
      rowBg = focused ? mix(bg, accent, 0.35) : mix(bg, fg, 0.16);
    } else if (i == m.hovered) {
      rowBg = mix(bg, fg, 0.08);
    }
    final IconData icon;
    final Color iconColor;
    if (e.isDir) {
      icon = e.name == '..' ? Icons.drive_folder_upload_outlined : Icons.folder;
      iconColor = mix(bg, accent, 0.85 * dim);
    } else {
      final (ic, col) = fileIcon(e.name);
      icon = ic;
      iconColor = col < 0 ? mix(bg, fg, 0.6 * dim) : mix(bg, palette[col], 0.9 * dim);
    }
    final textT = e.isDir || i == m.selected ? 1.0 : 0.75;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) {
        if (m.hovered != i) onHover(i);
      },
      child: _ClickCounter(
        onClick: (button, clicks) => onClick(i, button, clicks),
        child: Container(
          height: rowH,
          color: rowBg,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Icon(icon, size: rowH * 0.6, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(color: mix(bg, fg, textT * dim))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Reports presses with their button and how many clicks in a row they
/// make (double-click and so on).
class _ClickCounter extends StatefulWidget {
  final void Function(int button, int clicks) onClick;
  final Widget child;
  const _ClickCounter({required this.onClick, required this.child});

  @override
  State<_ClickCounter> createState() => _ClickCounterState();
}

class _ClickCounterState extends State<_ClickCounter> {
  static DateTime _last = DateTime(0);
  static int _lastButton = 0, _count = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        final now = DateTime.now();
        if (e.buttons == _lastButton && now.difference(_last).inMilliseconds < 400) {
          _count++;
        } else {
          _count = 1;
        }
        _last = now;
        _lastButton = e.buttons;
        widget.onClick(e.buttons, _count);
      },
      child: widget.child,
    );
  }
}
