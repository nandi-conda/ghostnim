/// The ghostnim window: tabs, the recent-folders strip, the file manager
/// pane, the terminal, the context menu, and everything the keyboard and
/// mouse do to them.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flatkit/flatkit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons, Material, MaterialApp, ThemeData;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Action, Key;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'file_pane.dart';
import 'input.dart';
import 'keybinds.dart';
import 'keys.dart';
import 'links.dart';
import 'options.dart';
import 'paths.dart';
import 'renderer.dart';
import 'session.dart';
import 'state.dart';
import 'update.dart';
import 'vt.dart';
import 'wordsel.dart';

const _window = MethodChannel('ghostnim/window');
const _blinkInterval = Duration(milliseconds: 600);
const _defaultPaneWidth = 240.0;

enum _SelectUnit { cell, word, line }

class GhostnimApp extends StatelessWidget {
  final Cli cli;
  final Options opts;
  final String defaultConfigText;
  const GhostnimApp(
      {super.key, required this.cli, required this.opts, required this.defaultConfigText});

  @override
  Widget build(BuildContext context) {
    return TerminalWindow(cli: cli, opts: opts, defaultConfigText: defaultConfigText);
  }
}

class TerminalWindow extends StatefulWidget {
  final Cli cli;
  final Options opts;
  final String defaultConfigText;
  const TerminalWindow(
      {super.key, required this.cli, required this.opts, required this.defaultConfigText});

  @override
  State<TerminalWindow> createState() => _TerminalWindowState();
}

class _Tab {
  final Session session;
  final TerminalRenderer renderer;
  _Tab(this.session, this.renderer);
}

class _TerminalWindowState extends State<TerminalWindow> with WidgetsBindingObserver {
  late Options opts;
  late String configStampValue;
  final _focus = FocusNode(debugLabel: 'ghostnim');
  final List<_Tab> tabs = [];
  int active = 0;
  int _nextId = 0;
  Encoders? _enc;
  Metrics? metrics;
  int fontSize = 14;
  final recent = RecentDirs();
  bool folderBar = true;
  bool windowFocused = true;
  bool blinkOn = true;
  Timer? _blinkTimer, _tick;
  int _lastConfigCheck = 0, _lastPaneCheck = 0;

  // Grid geometry of the terminal view, in logical pixels.
  Size _termSize = Size.zero;
  int cols = 0, rows = 0;

  // Selection drag state (viewport cells).
  bool selecting = false;
  (int, int) _selAnchor = (0, 0);
  _SelectUnit _selUnit = _SelectUnit.cell;
  (int, int) _selAnchorStart = (0, 0), _selAnchorEnd = (0, 0);
  // The viewport has scrolled mid-drag, so the anchor's viewport cell is
  // stale: the drag now moves the selection's own end (which libghostty
  // tracks through scrolling) instead. _selBackward: that end is `start`.
  bool _selScrolled = false, _selBackward = false;
  Timer? _autoScroll;

  // Mouse state in the terminal.
  int _buttons = 0; // buttons the terminal (or selection) has down
  int _ownButtons = 0; // buttons whose press we handled ourselves
  Offset _pointer = Offset.zero; // last pointer position in the terminal view
  bool _pointerInTerm = false;
  (int, int) _lastMouseCell = (-1, -1);
  DateTime _lastClick = DateTime(0);
  int _clickCount = 0, _clickButton = 0;
  (int, int) _clickCell = (-1, -1);
  double _wheelAccum = 0;
  MouseCursor _termCursor = SystemMouseCursors.text;

  // Tab dragging.
  int _dragTab = -1; // id of the tab held down, -1 for none
  double _dragGrab = 0, _dragStartX = 0, _dragOffset = 0;
  bool _tabDragging = false;

  // File manager pane.
  final pane = FilePaneModel();
  bool paneOn = false;
  double paneW = _defaultPaneWidth;
  int _paneTab = -1; // the tab it follows, -1 to pick up the current one
  String _paneCwd = '';
  bool paneFocused = false;
  int _paneRows = 10;
  String _typeAhead = '';
  DateTime _typeAheadAt = DateTime(0);

  // Context menu.
  Offset _menuAt = Offset.zero;
  VoidCallback? _menuToggle;
  bool menuOpen = false;
  int _menuGen = 0;

  // Colours of the active terminal, for the chrome.
  int _bg = 0x1d1f21, _fg = 0xc5c8c6, _accent = 0x81a2be;
  List<int> _palette = List.filled(16, 0x808080);

  Session get cur => tabs[active].session;
  TerminalRenderer get curRenderer => tabs[active].renderer;

  @override
  void initState() {
    super.initState();
    opts = widget.opts;
    fontSize = opts.size;
    configStampValue = configStamp(configFile(widget.cli.configPath));
    WidgetsBinding.instance.addObserver(this);
    final ps = loadPaneState(_defaultPaneWidth);
    paneOn = ps.on;
    paneW = ps.width;
    pane.showHidden = ps.hidden;
    folderBar = folderBarShown();
    recent.sync();
    _start();
  }

  Future<void> _start() async {
    final m = await _makeMetrics(fontSize);
    _enc = Encoders();
    setState(() => metrics = m);
    // Size the window to fit cols x rows (plus the bars and the pane).
    final w = opts.cols * m.cellW + 2 * m.pad + (paneOn ? paneW + 1 : 0);
    final h = opts.rows * m.cellH + 2 * m.pad + _topHeight(m);
    _window.invokeMethod('setSize', [w.ceilToDouble(), h.ceilToDouble()]);
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      if (tabs.isEmpty) return;
      if (cur.cursor.blinking) {
        blinkOn = !blinkOn;
        cur.changed();
      } else {
        blinkOn = true;
      }
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  Future<Metrics> _makeMetrics(int size) async {
    final (family, fallback) = await resolveFont(opts.font);
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return Metrics(
      family: family,
      fallback: fallback,
      fontSize: size.toDouble(),
      shaping: opts.fontShaping,
      devicePixelRatio: view.devicePixelRatio,
    );
  }

  double _tabH(Metrics m) => (m.cellH + 12).roundToDouble();
  double _folderH(Metrics m) => (m.cellH + 10).roundToDouble();
  double _topHeight(Metrics m) => _tabH(m) + (folderBar ? _folderH(m) : 0);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blinkTimer?.cancel();
    _tick?.cancel();
    _autoScroll?.cancel();
    for (final t in tabs) {
      t.session.dispose();
      t.renderer.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final focused = s == AppLifecycleState.resumed;
    if (focused == windowFocused) return;
    setState(() => windowFocused = focused);
    if (!focused) _closeMenu();
    if (tabs.isNotEmpty) cur.changed();
  }

  @override
  void didChangeMetrics() {
    // The display scale may have changed.
    final m = metrics;
    if (m == null) return;
    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    if (dpr != m.devicePixelRatio) _zoom(fontSize);
  }

  // --- periodic work ------------------------------------------------------------

  void _onTick() {
    if (tabs.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastConfigCheck >= 1000) {
      _lastConfigCheck = now;
      final stamp = configStamp(configFile(widget.cli.configPath));
      if (stamp != configStampValue) _reloadConfig();
    }
    _trackDirs();
    _syncPane(now);
  }

  /// Note each tab's working directory, counting a visit whenever one moves,
  /// in the list all tabs and windows share.
  void _trackDirs() {
    for (final t in tabs) {
      final dir = t.session.cwd;
      if (dir.isEmpty || dir == t.session.lastDir) continue;
      t.session.lastDir = dir;
      recent.visit(dir);
    }
    if (recent.sync()) setState(() {});
  }

  /// The most used folders, not counting the one the current tab is in.
  List<String> get recentDirs {
    final here = cur.lastDir;
    return [
      for (final d in recent.dirs)
        if (d.path != here) d.path
    ].take(shownRecentDirs).toList();
  }

  String _folderLabel(String dir) {
    if (dir == homeDir().replaceAll(RegExp(r'/+$'), '')) return '~';
    if (dir == '/') return '/';
    return p.basename(dir);
  }

  /// cd the current tab's shell into [dir], or, if a program is running in
  /// it (or [newTab]), open a new tab there.
  void _goToDir(String dir, {bool newTab = false}) {
    if (!dirExists(dir)) {
      recent.gone(dir);
      recent.sync();
      setState(() {});
      return;
    }
    if (newTab || !cur.atPrompt) {
      _addTab(dir: dir);
    } else {
      cur.sendInput('cd ${quoteShell(dir)}\r');
    }
    _focus.requestFocus();
  }

  void _toggleFolderBar() {
    setState(() => folderBar = !folderBar);
    saveFolderBar(folderBar);
  }

  // --- tabs ---------------------------------------------------------------------

  Session _newSession({String cwd = '', List<String> command = const []}) {
    final m = metrics!;
    final s = Session(
      id: _nextId++,
      cols: cols > 0 ? cols : opts.cols,
      rows: rows > 0 ? rows : opts.rows,
      cellW: m.cellWi,
      cellH: m.cellHi,
      command: command.isNotEmpty ? command : opts.command,
      cwd: cwd.isNotEmpty ? cwd : opts.workingDirectory,
      scrollback: opts.scrollback,
    );
    s.applyColors(opts.colors);
    s.onExit = () => _sessionExited(s);
    s.onTitle = () {
      if (tabs.isNotEmpty && s == cur) _updateWindowTitle();
      setState(() {});
    };
    return s;
  }

  _Tab _makeTab(Session s) {
    final r = TerminalRenderer(metrics!)
      ..selectionFg = _rgbOf(opts.colors.selectionForeground)
      ..selectionBg = _rgbOf(opts.colors.selectionBackground);
    return _Tab(s, r);
  }

  static int? _rgbOf(Rgb? c) => c == null ? null : (c.$1 << 16) | (c.$2 << 8) | c.$3;

  void _ensureFirstTab() {
    if (tabs.isNotEmpty || metrics == null || cols == 0) return;
    tabs.add(_makeTab(_newSession()));
    active = 0;
    _updateWindowTitle();
  }

  /// Open a tab next to the current one, in [dir] if given, else in the
  /// current tab's directory (or in working-directory, with
  /// inherit-directory off).
  void _addTab({List<String> command = const [], String dir = ''}) {
    final cwd = dir.isNotEmpty ? dir : (opts.inheritDirectory ? cur.cwd : '');
    final t = _makeTab(_newSession(cwd: cwd, command: command));
    setState(() {
      tabs.insert(active + 1, t);
      _activate(active + 1);
    });
  }

  void _activate(int i) {
    setState(() {
      active = i;
      _paneTab = -1; // the file pane follows the new tab
      selecting = false;
    });
    _closeMenu();
    cur.changed(full: true);
    _updateWindowTitle();
    _syncPane(DateTime.now().millisecondsSinceEpoch);
  }

  void _sessionExited(Session s) {
    final i = tabs.indexWhere((t) => t.session == s);
    if (i >= 0) _closeTab(i);
  }

  void _closeTab(int i) {
    final t = tabs.removeAt(i);
    t.session.dispose();
    t.renderer.dispose();
    if (tabs.isEmpty) {
      exit(0);
    }
    if (active > i || active >= tabs.length) active--;
    _activate(active);
  }

  /// Move tab [i] to position [j], keeping the same tab active.
  void _moveTab(int i, int j) {
    if (i == j) return;
    final t = tabs.removeAt(i);
    tabs.insert(j, t);
    if (active == i) {
      active = j;
    } else if (i < active && active <= j) {
      active--;
    } else if (j <= active && active < i) {
      active++;
    }
  }

  void _cycleTab(int delta) {
    final n = tabs.length;
    _activate(((active + delta) % n + n) % n);
  }

  void _updateWindowTitle() {
    final t = tabs.isEmpty ? '' : cur.title;
    _window.invokeMethod('setTitle', t.isNotEmpty ? t : 'ghostnim');
  }

  // --- sizing ---------------------------------------------------------------------

  /// The terminal view was laid out at [size]: fit every tab's grid to it.
  void _onTermSize(Size size) {
    final m = metrics;
    if (m == null || size == _termSize) return;
    _termSize = size;
    final c = math.max(1, ((size.width - 2 * m.pad) / m.cellW).floor());
    final r = math.max(1, ((size.height - 2 * m.pad) / m.cellH).floor());
    cols = c;
    rows = r;
    for (final t in tabs) {
      t.session.resize(c, r, m.cellWi, m.cellHi);
    }
    _enc?.setSize(
      width: c * m.cellWi + 2 * m.pad,
      height: r * m.cellHi + 2 * m.pad,
      cellW: m.cellWi,
      cellH: m.cellHi,
      padLeft: m.pad.round(),
      padTop: m.pad.round(),
      padRight: m.pad.round(),
      padBottom: m.pad.round(),
    );
    if (tabs.isEmpty) {
      _ensureFirstTab();
      setState(() {});
    }
  }

  Future<void> _zoom(int size) async {
    fontSize = size.clamp(4, 200);
    final m = await _makeMetrics(fontSize);
    if (!mounted) return;
    setState(() {
      metrics = m;
      _termSize = Size.zero; // re-fit the grid at the next layout
      for (final t in tabs) {
        t.renderer.setMetrics(m);
        t.session.changed(full: true);
      }
    });
  }

  // --- config ------------------------------------------------------------------------

  /// Re-read the config file and apply it. Window size (cols/rows) only
  /// matters at startup; command and working-directory apply to new tabs.
  Future<void> _reloadConfig() async {
    final path = configFile(widget.cli.configPath);
    configStampValue = configStamp(path);
    final cfg = reloadConfig(widget.cli.configPath);
    if (cfg == null) return; // unreadable or invalid: keep what we have
    final old = opts;
    opts = mergeOptions(cfg, widget.cli);
    for (final t in tabs) {
      t.session.applyColors(opts.colors);
      t.session.setScrollback(opts.scrollback);
      t.renderer
        ..selectionFg = _rgbOf(opts.colors.selectionForeground)
        ..selectionBg = _rgbOf(opts.colors.selectionBackground)
        ..invalidate();
    }
    if (opts.size != old.size) {
      await _zoom(opts.size); // also resets any zoom
    } else if (opts.font != old.font || opts.fontShaping != old.fontShaping) {
      await _zoom(fontSize);
    }
    setState(() {});
    stderr.writeln('ghostnim: reloaded $path');
  }

  void _openConfig() {
    final path = configFile(widget.cli.configPath);
    if (!ensureConfigFile(path, widget.defaultConfigText)) return;
    final cmd = editorCommand(path);
    if (cmd != null) {
      _addTab(command: cmd);
    } else if (canXdgOpen) {
      openExternal(path);
    } else {
      _addTab(command: ['vi', path]);
    }
  }

  /// Open the current folder (the file manager's, when it's shown, else the
  /// tab's) in $VISUAL/$EDITOR in a new tab there, or in vi without either.
  void _openFolderInEditor() {
    final dir = paneOn && pane.dir.isNotEmpty ? pane.dir : cur.cwd;
    if (!dirExists(dir)) return;
    final cmd = editorCommand(dir, fallback: 'vi');
    if (cmd != null) _addTab(command: cmd, dir: dir);
  }

  /// Ctrl+click on a path: a directory opens in a new tab; a file opens in
  /// $VISUAL/$EDITOR in a new tab in its directory, or with the desktop's
  /// handler without either.
  void _openPath(String path) {
    if (dirExists(path)) {
      _addTab(dir: path);
      return;
    }
    final cmd = editorCommand(path);
    if (cmd != null) {
      _addTab(command: cmd, dir: p.dirname(path));
    } else {
      openExternal(path);
    }
  }

  // --- clipboard and selection ----------------------------------------------------

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty || tabs.isEmpty) return;
    cur.sendBytes(cur.encodePaste(text));
  }

  void _copySelection() {
    final s = cur.selectionText();
    // Selecting only blanks (e.g. double-clicking empty space) mustn't wipe
    // out what's on the clipboard.
    if (s != null && s.trim().isNotEmpty) Clipboard.setData(ClipboardData(text: s));
  }

  void _selectAllText() {
    cur.selectAll();
    if (opts.copyOnSelect) _copySelection();
  }

  /// The viewport cell under [pos] (terminal view coordinates), clamped.
  (int, int) _cellAt(Offset pos) {
    final m = metrics!;
    final c = ((pos.dx - m.pad) / m.cellW).floor().clamp(0, math.max(0, cur.cols - 1)).toInt();
    final r = ((pos.dy - m.pad) / m.cellH).floor().clamp(0, math.max(0, cur.rows - 1)).toInt();
    return (c, r);
  }

  bool _before((int, int) a, (int, int) b) => a.$2 < b.$2 || (a.$2 == b.$2 && a.$1 < b.$1);

  /// The first and last cell of the word or line (per _selUnit) at [cell].
  ((int, int), (int, int)) _unitAt((int, int) cell) {
    final line = cur.lineAt(cell.$2);
    final c = math.max(1, cur.cols);
    (int, int) at(int i) => (i % c, line.first + i ~/ c);
    switch (_selUnit) {
      case _SelectUnit.cell:
        return (cell, cell);
      case _SelectUnit.line:
        return ((0, line.first), (c - 1, line.last));
      case _SelectUnit.word:
        final (a, b) = wordAt(line.cells, (cell.$2 - line.first) * c + cell.$1);
        return (at(a), at(b));
    }
  }

  /// A left press: one click starts a cell selection, two select the word
  /// under the pointer, three the line.
  void _startSelection((int, int) cell, int clicks) {
    selecting = true;
    _selScrolled = false;
    _selBackward = false;
    _selAnchor = cell;
    _selUnit = clicks <= 1 ? _SelectUnit.cell : (clicks == 2 ? _SelectUnit.word : _SelectUnit.line);
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 40), (_) => _autoScrollSelection());
    if (_selUnit == _SelectUnit.cell) {
      cur.clearSelection();
      return;
    }
    final (start, end) = _unitAt(cell);
    _selAnchorStart = start;
    _selAnchorEnd = end;
    cur.setSelection(_selAnchorStart, _selAnchorEnd);
  }

  /// A drag: select from the anchor to [cell], by whole words or lines after
  /// a double or triple click.
  void _extendSelection((int, int) cell) {
    if (_selScrolled && cur.moveSelectionEnd(cell, backward: _selBackward)) return;
    if (_selUnit == _SelectUnit.cell) {
      cur.setSelection(_selAnchor, cell);
      return;
    }
    final (a, b) = _unitAt(cell);
    _selBackward = _before(a, _selAnchorStart);
    if (_selBackward) {
      cur.setSelection(a, _selAnchorEnd);
    } else {
      cur.setSelection(_selAnchorStart, _before(b, _selAnchorEnd) ? _selAnchorEnd : b);
    }
  }

  /// While a drag is held above or below the grid, scroll the viewport
  /// (faster the further out the pointer is) and extend the selection to
  /// the edge row, so it can grow past what fits on screen.
  void _autoScrollSelection() {
    if (!selecting || _reportMouse || menuOpen || tabs.isEmpty) return;
    final m = metrics!;
    final top = m.pad;
    final bottom = top + cur.rows * m.cellH;
    final py = _pointer.dy;
    var lines = 0;
    if (py < top) {
      lines = -(1 + ((top - py) / m.cellH).floor()).clamp(1, 8);
    } else if (py >= bottom) {
      lines = (1 + ((py - bottom) / m.cellH).floor()).clamp(1, 8);
    }
    if (lines == 0) return;
    cur.scrollViewport(scrollViewportDelta, lines);
    _selScrolled = true;
    final cell = _cellAt(_pointer);
    cur.moveSelectionEnd((cell.$1, lines < 0 ? 0 : math.max(0, cur.rows - 1)),
        backward: _selBackward);
  }

  /// The button went up: copy what was selected, with copy-on-select.
  void _finishSelection() {
    selecting = false;
    _autoScroll?.cancel();
    if (opts.copyOnSelect && cur.hasSelection) _copySelection();
  }

  // --- links ----------------------------------------------------------------------------

  /// The link under viewport cell (col, row): its OSC 8 hyperlink if it has
  /// one, else a URL found in the text of its (soft-wrapped) line.
  String _linkAt(int col, int row) {
    final h = cur.hyperlinkAt(col, row);
    if (h.isNotEmpty) return h;
    final line = cur.lineAt(row);
    return urlAt(line.cells, (row - line.first) * cur.cols + col);
  }

  /// The existing file or directory named by the word under viewport cell
  /// (col, row), relative to the tab's directory, or "".
  String _pathAt(int col, int row) {
    final line = cur.lineAt(row);
    final i = (row - line.first) * cur.cols + col;
    if (i < 0 || i >= line.cells.length || line.cells[i] == ' ') return '';
    final (a, b) = wordAt(line.cells, i);
    return pathTarget(line.cells.sublist(a, b + 1).join(), cur.cwd);
  }

  bool get _linkModifier {
    final kb = HardwareKeyboard.instance;
    return kb.isControlPressed || kb.isMetaPressed;
  }

  /// Show a hand while Ctrl is held over a link or path.
  void _updateLinkCursor() {
    if (tabs.isEmpty || metrics == null) return;
    var want = SystemMouseCursors.text;
    if (_pointerInTerm && !menuOpen && !selecting && _ownButtons == 0 && _linkModifier) {
      final (c, r) = _cellAt(_pointer);
      if (_linkAt(c, r).isNotEmpty || _pathAt(c, r).isNotEmpty) want = SystemMouseCursors.click;
    }
    if (want != _termCursor) setState(() => _termCursor = want);
  }

  // --- mouse in the terminal ----------------------------------------------------

  bool get _reportMouse => cur.mouseTracking && !HardwareKeyboard.instance.isShiftPressed;

  static int _ghosttyButton(int flutterButton) => switch (flutterButton) {
        kPrimaryButton => mouseButtonLeft,
        kMiddleMouseButton => mouseButtonMiddle,
        kSecondaryButton => mouseButtonRight,
        _ => 0,
      };

  void _sendMouse(int action, int button, Offset pos) {
    final m = metrics!;
    // Map the position onto the whole-pixel grid the encoder was given.
    final fx = (pos.dx - m.pad) / m.cellW, fy = (pos.dy - m.pad) / m.cellH;
    final bytes = _enc!.encodeMouse(
        cur, action, button, currentMods(), m.pad + fx * m.cellWi, m.pad + fy * m.cellHi,
        anyPressed: _buttons != 0);
    cur.write(bytes);
  }

  void _onTermPointerDown(PointerDownEvent e) {
    _focus.requestFocus();
    _pointer = e.localPosition;
    final pressed = e.buttons & ~(_buttons | _ownButtons);
    final button = pressed & kPrimaryButton != 0
        ? kPrimaryButton
        : pressed & kSecondaryButton != 0
            ? kSecondaryButton
            : pressed & kMiddleMouseButton != 0
                ? kMiddleMouseButton
                : 0;
    if (button == 0 || tabs.isEmpty) return;
    final cell = _cellAt(e.localPosition);
    final now = DateTime.now();
    if (button == _clickButton &&
        cell == _clickCell &&
        now.difference(_lastClick).inMilliseconds < 400) {
      _clickCount++;
    } else {
      _clickCount = 1;
    }
    _lastClick = now;
    _clickButton = button;
    _clickCell = cell;
    if (paneFocused) _focusPane(false); // a click in the terminal gives it the keyboard back

    if (button == kPrimaryButton && _linkModifier && _buttons == 0) {
      // Ctrl+click on a link opens it, even when the app reports the mouse.
      // A directory (a file:// link to one, or a path in the text) opens in
      // a new tab instead.
      final link = _linkAt(cell.$1, cell.$2);
      if (link.isNotEmpty && !link.startsWith('-')) {
        _ownButtons |= button;
        final dir = fileUrlPath(link);
        if (dir.isNotEmpty && dirExists(dir)) {
          _addTab(dir: dir);
        } else {
          openExternal(link);
        }
        return;
      }
      final path = _pathAt(cell.$1, cell.$2);
      if (path.isNotEmpty) {
        _ownButtons |= button;
        _openPath(path);
        return;
      }
    }
    if (button == kSecondaryButton && !_reportMouse) {
      _ownButtons |= button;
      _openMenu(e.position);
      return;
    }
    _buttons |= button;
    if (_reportMouse) {
      _sendMouse(mouseActionPress, _ghosttyButton(button), e.localPosition);
      return;
    }
    if (button == kPrimaryButton) {
      _startSelection(cell, _clickCount);
    } else if (button == kMiddleMouseButton) {
      _paste();
    }
  }

  void _onTermPointerUp(PointerUpEvent e) {
    _pointer = e.localPosition;
    final released = (_buttons | _ownButtons) & ~e.buttons;
    for (final b in [kPrimaryButton, kSecondaryButton, kMiddleMouseButton]) {
      if (released & b == 0) continue;
      if (_ownButtons & b != 0) {
        _ownButtons &= ~b;
        continue;
      }
      _buttons &= ~b;
      if (_reportMouse) {
        _sendMouse(mouseActionRelease, _ghosttyButton(b), e.localPosition);
      } else if (b == kPrimaryButton && selecting) {
        _finishSelection();
      }
    }
    if (b0(e.buttons) && selecting) _finishSelection();
  }

  static bool b0(int buttons) => buttons == 0;

  void _onTermPointerMove(PointerEvent e) {
    _pointer = e.localPosition;
    _pointerInTerm = true;
    if (tabs.isEmpty || metrics == null) return;
    _updateLinkCursor();
    if (menuOpen) return;
    if (_reportMouse) {
      if (_ownButtons != 0) return;
      final cell = _cellAt(e.localPosition);
      if (cell == _lastMouseCell) return;
      _lastMouseCell = cell;
      var button = 0;
      for (final b in [kPrimaryButton, kMiddleMouseButton, kSecondaryButton]) {
        if (_buttons & b != 0) {
          button = _ghosttyButton(b);
          break;
        }
      }
      _sendMouse(mouseActionMotion, button, e.localPosition);
    } else if (selecting) {
      _extendSelection(_cellAt(e.localPosition));
    }
  }

  void _onTermScroll(PointerScrollEvent e) {
    if (tabs.isEmpty) return;
    if (menuOpen) {
      _closeMenu();
      return;
    }
    // A wheel notch is about 53 logical pixels in Flutter; touchpads send
    // smaller steps, which add up.
    _wheelAccum += e.scrollDelta.dy;
    final notches = (_wheelAccum / 53).truncate();
    if (notches == 0) {
      if (e.scrollDelta.dy.abs() >= 1 &&
          _wheelAccum.abs() < 53 &&
          e.kind == PointerDeviceKind.mouse) {
        // A mouse with smaller notches: treat each event as one.
        _wheelAccum = 0;
        _scrollNotches(e.scrollDelta.dy > 0 ? 1 : -1, e.localPosition);
      }
      return;
    }
    _wheelAccum -= notches * 53;
    _scrollNotches(notches, e.localPosition);
  }

  /// [n] notches down (positive) or up (negative).
  void _scrollNotches(int n, Offset pos) {
    if (_reportMouse) {
      final button = n < 0 ? mouseButtonFour : mouseButtonFive;
      for (var i = 0; i < n.abs(); i++) {
        _sendMouse(mouseActionPress, button, pos);
      }
    } else {
      if (selecting) _selScrolled = true;
      cur.scrollViewport(scrollViewportDelta, 3 * n);
    }
    _updateLinkCursor();
  }

  // --- context menu -----------------------------------------------------------------

  void _openMenu(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    setState(() {
      _menuAt = local;
      _menuGen++;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!menuOpen) _menuToggle?.call();
    });
  }

  void _closeMenu() {
    if (menuOpen) _menuToggle?.call();
  }

  List<KitMenuEntry> _menuItems() {
    final kb = opts.keybinds;
    String? k(Action a) {
      final s = shortcutLabel(kb, a);
      return s.isEmpty ? null : s;
    }

    void run(void Function() f) {
      f();
      _focus.requestFocus();
    }

    final hasSel = cur.hasSelection;
    return [
      KitMenuItem('Copy',
          shortcut: k(Action.copy), onSelected: hasSel ? () => run(_copySelection) : null),
      KitMenuItem('Paste', shortcut: k(Action.paste), onSelected: () => run(_paste)),
      KitMenuItem('Select All',
          shortcut: k(Action.selectAll), onSelected: () => run(_selectAllText)),
      const KitMenuDivider(),
      KitMenuItem('Zoom In',
          shortcut: k(Action.fontBigger), onSelected: () => run(() => _zoom(fontSize + 1))),
      KitMenuItem('Zoom Out',
          shortcut: k(Action.fontSmaller), onSelected: () => run(() => _zoom(fontSize - 1))),
      KitMenuItem('Reset Zoom',
          shortcut: k(Action.fontReset), onSelected: () => run(() => _zoom(opts.size))),
      const KitMenuDivider(),
      KitMenuItem(folderBar ? 'Hide Recent Folders' : 'Show Recent Folders',
          onSelected: () => run(_toggleFolderBar)),
      KitMenuItem(paneOn ? 'Hide File Manager' : 'Show File Manager',
          shortcut: k(Action.toggleFilePane), onSelected: () => run(_toggleFilePane)),
      if (paneOn) ...[
        KitMenuItem('${pane.showHidden ? 'Hide' : 'Show'} Hidden Files',
            shortcut: _hiddenFilesKey(), onSelected: () => run(_toggleHiddenFiles)),
        KitMenuItem('Filter Files', shortcut: 'Ctrl+F', onSelected: () {
          _focusPane(true);
          setState(() => pane.filtering = true);
          _focus.requestFocus();
        }),
      ],
      KitMenuItem('Open Folder in Editor',
          shortcut: k(Action.openFolderInEditor), onSelected: () => run(_openFolderInEditor)),
      KitMenuItem('Open Config',
          shortcut: k(Action.openConfig), onSelected: () => run(_openConfig)),
      if (canUpdate())
        KitMenuItem('Check for Updates',
            onSelected: () => run(() => startUpdateCheck(manual: true))),
    ];
  }

  String _hiddenFilesKey() {
    final k = shortcutLabel(opts.keybinds, Action.toggleHiddenFiles);
    return k.isNotEmpty ? k : 'Ctrl+H';
  }

  // --- file manager pane -----------------------------------------------------------

  /// Keep the pane on the current tab's directory, and its listing current.
  void _syncPane(int now) {
    if (!paneOn || tabs.isEmpty) return;
    final s = cur;
    final cwd = s.cwd;
    if (s.id != _paneTab || (cwd.isNotEmpty && cwd != _paneCwd)) {
      // A new tab, or its shell moved: follow it. Otherwise the pane stays
      // wherever it was browsed to.
      _paneTab = s.id;
      _paneCwd = cwd;
      setState(() {
        if (cwd.isNotEmpty) {
          pane.load(cwd);
        } else if (pane.dir.isEmpty) {
          pane.load(Directory.current.path);
        }
      });
      _lastPaneCheck = now;
      return;
    }
    if (now - _lastPaneCheck < 500) return;
    _lastPaneCheck = now;
    final before = (pane.dir, pane.entries.length, pane.selected);
    pane.refresh();
    if (before != (pane.dir, pane.entries.length, pane.selected)) setState(() {});
  }

  /// Give the keyboard to the file pane, or back to the terminal (whose
  /// cursor then shows it has focus again).
  void _focusPane(bool on) {
    on = on && paneOn;
    if (on == paneFocused) return;
    setState(() {
      paneFocused = on;
      _typeAhead = '';
      pane.filtering = false; // the filter stays, but typing no longer edits it
    });
    cur.changed();
  }

  /// Show the file pane and focus it, or hide it. With [focusFirst] (the
  /// shortcut), a pane that's shown but not focused gets focused instead.
  void _toggleFilePane({bool focusFirst = false}) {
    if (focusFirst && paneOn && !paneFocused) {
      _focusPane(true);
      return;
    }
    setState(() {
      paneOn = !paneOn;
      _paneTab = -1;
      pane.hovered = -1;
    });
    _savePane();
    _syncPane(DateTime.now().millisecondsSinceEpoch);
    _focusPane(paneOn);
  }

  void _savePane() => savePaneState(on: paneOn, width: paneW, hidden: pane.showHidden);

  /// Show [dir] in the pane, and cd the shell there when it's at its prompt.
  void _paneOpenDir(String dir) {
    if (!dirExists(dir)) {
      setState(pane.refresh);
      return;
    }
    if (cur.atPrompt) cur.sendInput('cd ${quoteShell(dir)}\r');
    setState(() => pane.load(dir));
  }

  void _toggleHiddenFiles() {
    setState(() {
      pane.setShowHidden(!pane.showHidden);
      if (pane.selected >= 0) pane.select(pane.selected, _paneRows);
      pane.scrollBy(0, _paneRows);
    });
    _savePane();
  }

  /// Enter on the selected entry: go into a folder, open a file.
  void _paneOpen() {
    final i = pane.selected;
    if (i < 0) return;
    final path = pane.path(i);
    if (pane.entries[i].isDir) {
      final parent = pane.entries[i].name == '..';
      final came = p.basename(pane.dir);
      _paneOpenDir(path);
      setState(() => pane.selectName(parent ? came : '', _paneRows));
    } else {
      openExternal(path);
    }
  }

  /// Go to the parent folder, with the one we were in selected.
  void _paneUp() {
    if (pane.dir.isEmpty || pane.dir == '/') return;
    final came = p.basename(pane.dir);
    _paneOpenDir(p.dirname(pane.dir));
    setState(() => pane.selectName(came, _paneRows));
  }

  void _paneFilter(String f) {
    setState(() {
      pane.setFilter(f);
      if (pane.selected >= 0) pane.select(pane.selected, _paneRows);
    });
  }

  /// Keyboard handling while the file pane has focus; nothing reaches the
  /// terminal.
  void _paneKey(KeyEvent e, int key) {
    final kb = HardwareKeyboard.instance;
    final shift = kb.isShiftPressed, ctrl = kb.isControlPressed;
    final sel = pane.selected;
    final rows = _paneRows;
    if (pane.filtering) {
      if (key == Key.backspace) {
        // Delete the last character; on an empty filter, stop filtering.
        if (pane.filter.isEmpty) {
          setState(() => pane.filtering = false);
        } else {
          final r = pane.filter.runes.toList()..removeLast();
          _paneFilter(String.fromCharCodes(r));
        }
        return;
      }
      if (key == Key.escape) {
        setState(() => pane.filtering = false);
        _paneFilter('');
        return;
      }
      if (key == Key.enter || key == Key.numpadEnter) {
        pane.filtering = false; // then open the selected entry, as below
      } else if (key == Key.arrowLeft || key == Key.arrowRight) {
        return; // don't leave the folder while typing
      }
    }
    var handled = true;
    setState(() {
      if (key == Key.arrowDown) {
        pane.select(sel + 1, rows);
      } else if (key == Key.arrowUp) {
        pane.select(sel < 0 ? 0 : sel - 1, rows);
      } else if (key == Key.pageDown) {
        pane.select(sel + math.max(1, rows - 1), rows);
      } else if (key == Key.pageUp) {
        pane.select(sel - math.max(1, rows - 1), rows);
      } else if (key == Key.home) {
        pane.select(0, rows);
      } else if (key == Key.end) {
        pane.select(pane.entries.length - 1, rows);
      } else {
        handled = false;
      }
    });
    if (!handled) {
      if (key == Key.enter || key == Key.numpadEnter) {
        if (shift && sel >= 0) {
          // Type the path into the terminal and go back to it.
          cur.sendInput('${quoteShell(pane.path(sel))} ');
          _focusPane(false);
        } else {
          _paneOpen();
        }
      } else if (key == Key.arrowRight) {
        if (sel >= 0 && pane.entries[sel].isDir) _paneOpen();
      } else if (key == Key.arrowLeft || key == Key.backspace) {
        _paneUp();
      } else if (key == Key.escape) {
        if (pane.filter.isNotEmpty) {
          _paneFilter(''); // clear the filter first
        } else {
          _focusPane(false);
        }
      } else if (key == Key.h && ctrl) {
        _toggleHiddenFiles();
      } else if (key == Key.f && ctrl) {
        setState(() => pane.filtering = true);
      } else {
        // Printable keys: type-ahead, or the filter while it's being typed.
        final ch = e.character;
        if (!ctrl && ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20) _paneTypeAhead(ch);
        return;
      }
    }
    _typeAhead = '';
  }

  /// Letters typed into the focused pane select the entry they start, or go
  /// into the filter while it's being typed; "/" starts typing one.
  void _paneTypeAhead(String text) {
    if (pane.filtering) {
      _paneFilter(pane.filter + text);
      return;
    }
    if (text == '/') {
      setState(() => pane.filtering = true);
      _typeAhead = '';
      return;
    }
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_typeAheadAt).inMilliseconds > 1000) _typeAhead = '';
    _typeAheadAt = now;
    _typeAhead += text;
    setState(() => pane.jumpTo(_typeAhead, _paneRows));
  }

  void _onPaneClick(int i, int buttons, int clicks) {
    _focus.requestFocus();
    _focusPane(true);
    final path = pane.path(i);
    final isDir = pane.entries[i].isDir;
    if (buttons & kPrimaryButton != 0) {
      setState(() => pane.selected = i);
      if (isDir) {
        _paneOpenDir(path);
      } else if (clicks >= 2) {
        openExternal(path);
      }
    } else if (buttons & kMiddleMouseButton != 0) {
      if (isDir && dirExists(path)) {
        _addTab(dir: path);
      } else if (!isDir) {
        cur.sendInput('${quoteShell(path)} ');
      }
    } else if (buttons & kSecondaryButton != 0) {
      setState(() => pane.selected = i);
    }
  }

  // --- keyboard ------------------------------------------------------------------------

  void _runAction(Binding b) {
    switch (b.action) {
      case Action.none:
        break;
      case Action.copy:
        _copySelection();
      case Action.paste:
        _paste();
      case Action.selectAll:
        _selectAllText();
      case Action.newTab:
        _addTab();
      case Action.closeTab:
        _closeTab(active);
      case Action.nextTab:
        _cycleTab(1);
      case Action.previousTab:
        _cycleTab(-1);
      case Action.gotoTab:
        if (b.num <= tabs.length) _activate(b.num - 1);
      case Action.scrollPageUp || Action.scrollPageDown:
        final d = math.max(1, cur.rows ~/ 2);
        cur.scrollViewport(scrollViewportDelta, b.action == Action.scrollPageUp ? -d : d);
      case Action.scrollToTop:
        cur.scrollViewport(scrollViewportTop);
      case Action.scrollToBottom:
        cur.scrollViewport(scrollViewportBottom);
      case Action.fontBigger:
        _zoom(fontSize + 1);
      case Action.fontSmaller:
        _zoom(fontSize - 1);
      case Action.fontReset:
        _zoom(opts.size);
      case Action.sendText:
        cur.sendInput(b.text);
      case Action.reloadConfig:
        _reloadConfig();
      case Action.openConfig:
        _openConfig();
      case Action.openFolderInEditor:
        _openFolderInEditor();
      case Action.toggleFilePane:
        _toggleFilePane(focusFirst: true);
      case Action.toggleHiddenFiles:
        _toggleHiddenFiles();
    }
  }

  /// Unshifted characters of the US layout's digit and punctuation keys,
  /// for when Shift changes what the layout reports.
  static const _usUnshifted = {
    Key.digit0: 0x30, Key.digit1: 0x31, Key.digit2: 0x32, Key.digit3: 0x33, Key.digit4: 0x34, //
    Key.digit5: 0x35, Key.digit6: 0x36, Key.digit7: 0x37, Key.digit8: 0x38, Key.digit9: 0x39,
    Key.minus: 0x2D, Key.equal: 0x3D, Key.bracketLeft: 0x5B, Key.bracketRight: 0x5D,
    Key.backslash: 0x5C, Key.semicolon: 0x3B, Key.quote: 0x27, Key.backquote: 0x60,
    Key.comma: 0x2C, Key.period: 0x2E, Key.slash: 0x2F,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (tabs.isEmpty || metrics == null) return KeyEventResult.ignored;
    final key = toGhosttyKey(e.physicalKey);
    final kb = HardwareKeyboard.instance;
    if (e is KeyUpEvent) {
      _updateLinkCursor();
      // Only sent when the kitty keyboard protocol asks for release events.
      if (!paneFocused) {
        cur.write(
            _enc!.encodeKey(cur, key, keyActionRelease, currentMods(), _unshifted(e, key), ''));
      }
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent) _updateLinkCursor(); // Ctrl pressed over a link

    // Keybindings from the config (or the defaults).
    var chordMods = 0;
    if (kb.isControlPressed) chordMods |= modCtrl;
    if (kb.isShiftPressed) chordMods |= modShift;
    if (kb.isAltPressed) chordMods |= modAlt;
    if (kb.isMetaPressed) chordMods |= modSuper;
    final binding = opts.keybinds[Chord(key, chordMods)];
    if (binding != null && binding.action != Action.none) {
      _runAction(binding);
      return KeyEventResult.handled;
    }
    if (paneFocused) {
      _paneKey(e, key);
      return KeyEventResult.handled;
    }

    final mods = currentMods();
    final action = e is KeyRepeatEvent ? keyActionRepeat : keyActionPress;
    final unshifted = _unshifted(e, key);
    var text = '';
    final ch = e.character;
    if (mods & (modsCtrl | modsAlt | modsSuper) == 0) {
      if (ch != null && ch.isNotEmpty && ch.runes.first >= 0x20 && ch.runes.first != 0x7F) {
        text = ch;
      }
    } else if (unshifted != 0 && mods & (modsCtrl | modsAlt) != 0) {
      // Ctrl/Alt combos generate no text; supply the character ourselves.
      var cp = unshifted;
      if (mods & modsShift != 0 && cp >= 0x61 && cp <= 0x7A) cp -= 32;
      text = String.fromCharCode(cp);
    }
    cur.sendBytes(_enc!.encodeKey(cur, key, action, mods, unshifted, text));
    return KeyEventResult.handled;
  }

  int _unshifted(KeyEvent e, int key) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      final us = _usUnshifted[key];
      if (us != null) return us;
    }
    final cp = unshiftedCodepoint(e.logicalKey);
    if (cp >= 0x41 && cp <= 0x5A) return cp + 32;
    return cp;
  }

  // --- theme ---------------------------------------------------------------------------

  /// Called after each paint with the active terminal's colours, so the
  /// chrome can follow them.
  void _onColors(Session s) {
    if (tabs.isEmpty || s != cur) return;
    final c = s.colors;
    if (c.background == _bg &&
        c.foreground == _fg &&
        c.palette[4] == _accent &&
        c.palette[1] == _palette[1]) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _bg = c.background;
        _fg = c.foreground;
        _accent = c.palette[4];
        _palette = c.palette.sublist(0, 16);
      });
    });
  }

  KitColors _kitColors() {
    final bg = rgbColor(_bg), fg = rgbColor(_fg), accent = rgbColor(_accent);
    final dark = bg.computeLuminance() < 0.4;
    Color m(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    final onAccent =
        accent.computeLuminance() > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final danger = rgbColor(_palette[1]);
    return KitColors(
      brightness: dark ? Brightness.dark : Brightness.light,
      background: bg,
      surface: m(bg, fg, 0.06),
      hover: m(bg, fg, 0.12),
      pressed: m(bg, fg, 0.18),
      border: m(bg, fg, 0.2),
      borderStrong: m(bg, fg, 0.35),
      text: fg,
      textDim: m(bg, fg, 0.6),
      accent: accent,
      accentHover: m(accent, fg, 0.1),
      accentPressed: m(accent, bg, 0.1),
      onAccent: onAccent,
      danger: danger,
      dangerHover: m(danger, fg, 0.1),
      onDanger: danger.computeLuminance() > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      success: rgbColor(_palette[2]),
      focus: accent,
      shadow: const Color(0x66000000),
    );
  }

  // --- building -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = _kitColors();
    final m = metrics;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ghostnim',
      theme: KitTheme.material(colors).copyWith(
        textTheme: ThemeData().textTheme.apply(fontFamily: m?.family),
      ),
      home: KitTheme(
        colors: colors,
        child: Material(
          color: colors.background,
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: m?.family,
              fontFamilyFallback: m?.fallback,
              fontSize: m?.fontSize ?? 14,
              color: colors.text,
              height: 1.0,
            ),
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: m == null ? const SizedBox.expand() : _body(context, m, colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Metrics m, KitColors colors) {
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: _tabH(m), child: _tabBar(m, colors)),
        if (folderBar) SizedBox(height: _folderH(m), child: _folderStrip(m, colors)),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (paneOn && tabs.isNotEmpty) SizedBox(width: paneW, child: _filePane(m, colors)),
            if (paneOn && tabs.isNotEmpty) _divider(colors),
            Expanded(child: _terminal(m)),
          ]),
        ),
      ]),
      // The context menu opens from an anchor at the pointer.
      Positioned(
        left: _menuAt.dx,
        top: _menuAt.dy,
        child: KitMenu(
          key: ValueKey(_menuGen),
          minWidth: 220,
          items: tabs.isEmpty ? () => const [] : _menuItems,
          builder: (context, toggle, open) {
            _menuToggle = toggle;
            if (open != menuOpen) {
              menuOpen = open;
              if (!open) {
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !menuOpen) _focus.requestFocus();
                });
              }
            }
            return const SizedBox(width: 1, height: 1);
          },
        ),
      ),
    ]);
  }

  Widget _terminal(Metrics m) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      if (size != _termSize) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onTermSize(size);
        });
      }
      if (tabs.isEmpty) return const SizedBox.expand();
      final t = tabs[active];
      return MouseRegion(
        cursor: _termCursor,
        onEnter: (_) => _pointerInTerm = true,
        onExit: (_) {
          _pointerInTerm = false;
          _updateLinkCursor();
        },
        onHover: _onTermPointerMove,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onTermPointerDown,
          onPointerUp: _onTermPointerUp,
          onPointerMove: _onTermPointerMove,
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _onTermScroll(e);
          },
          child: ClipRect(
            child: CustomPaint(
              size: size,
              painter: _TerminalPainter(
                session: t.session,
                renderer: t.renderer,
                focused: windowFocused && !paneFocused,
                blinkOn: blinkOn,
                onPainted: _onColors,
              ),
            ),
          ),
        ),
      );
    });
  }

  // --- tab bar -----------------------------------------------------------------------

  double _tabWidth(double barW, Metrics m) {
    final n = math.max(1, tabs.length);
    return math.max(1, math.min(32 * m.cellW, (barW - _tabH(m)) / n));
  }

  Widget _tabBar(Metrics m, KitColors c) {
    final bg = c.background, fg = c.text;
    final barBg = mix(bg, fg, 0.08);
    final tabH = _tabH(m);
    return LayoutBuilder(builder: (context, box) {
      final tabW = _tabWidth(box.maxWidth, m);
      final dragged = _tabDragging ? tabs.indexWhere((t) => t.session.id == _dragTab) : -1;
      double tabX(int i) => tabH + i * tabW + (i == dragged ? _dragOffset : 0);
      Widget tab(int i) {
        final t = tabs[i];
        final isActive = i == active;
        final title = t.session.title.isNotEmpty ? t.session.title : 'shell';
        return Positioned(
          left: tabX(i),
          top: 0,
          width: tabW,
          height: tabH,
          child: _TabWidget(
            title: title,
            active: isActive,
            lifted: i == dragged,
            showDivider: !isActive && i + 1 != active && i != dragged && i + 1 != dragged,
            colors: c,
            onClose: () => _closeTab(i),
            onPointerDown: (e) => _onTabPointerDown(e, i, tabX(i)),
            onPointerMove: (e) => _onTabPointerMove(e, box.maxWidth, m),
            onPointerUp: (_) => _endTabDrag(),
          ),
        );
      }

      return Listener(
        onPointerSignal: (e) {
          // The mouse wheel over the bar switches tabs.
          if (e is PointerScrollEvent && tabs.isNotEmpty) _cycleTab(e.scrollDelta.dy < 0 ? -1 : 1);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Double-clicking the empty bar space opens a new tab.
          onDoubleTap: tabs.isEmpty ? null : () => _addTab(),
          child: Container(
            decoration: BoxDecoration(
              color: barBg,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned(
                left: 0,
                top: 0,
                width: tabH,
                height: tabH,
                child: Center(
                  child: KitIconButton(Icons.add,
                      size: 16,
                      color: c.textDim,
                      tooltip: 'New tab',
                      onPressed: tabs.isEmpty ? null : () => _addTab()),
                ),
              ),
              for (var i = 0; i < tabs.length; i++)
                if (i != dragged) tab(i),
              if (dragged >= 0) tab(dragged),
            ]),
          ),
        ),
      );
    });
  }

  void _onTabPointerDown(PointerDownEvent e, int i, double x) {
    if (e.buttons & kMiddleMouseButton != 0) {
      _closeTab(i);
      return;
    }
    if (e.buttons & kPrimaryButton == 0) return;
    if (i != active) _activate(i);
    // Hold it to drag it along the bar.
    _dragTab = tabs[i].session.id;
    _dragGrab = e.localPosition.dx;
    _dragStartX = x + e.localPosition.dx;
    _tabDragging = false;
    _dragOffset = 0;
    _focus.requestFocus();
  }

  /// The pointer moved while holding a tab: slide it along the bar, moving
  /// it past the tabs whose middle it crosses.
  void _onTabPointerMove(PointerMoveEvent e, double barW, Metrics m) {
    if (_dragTab < 0) return;
    final i = tabs.indexWhere((t) => t.session.id == _dragTab);
    if (i < 0) {
      _endTabDrag(); // it closed under us
      return;
    }
    final tabH = _tabH(m);
    final n = tabs.length;
    final tabW = _tabWidth(barW, m);
    // Where the pointer is along the bar.
    final px = tabH + i * tabW + (_tabDragging ? _dragOffset : 0) + e.localPosition.dx;
    if (!_tabDragging && (px - _dragStartX).abs() < math.max(4, m.cellW / 2)) return;
    _tabDragging = true;
    final left = (px - _dragGrab).clamp(tabH, tabH + (n - 1) * tabW);
    final slot = ((left - tabH + tabW / 2) / tabW).floor().clamp(0, n - 1);
    setState(() {
      _moveTab(i, slot);
      _dragOffset = left - (tabH + slot * tabW);
    });
  }

  void _endTabDrag() {
    if (_dragTab < 0) return;
    setState(() {
      _dragTab = -1;
      _tabDragging = false;
      _dragOffset = 0;
    });
  }

  // --- recent folders -------------------------------------------------------------

  Widget _folderStrip(Metrics m, KitColors c) {
    final bg = c.background, fg = c.text;
    if (tabs.isEmpty) return Container(color: bg);
    final dirs = recentDirs;
    final chipH = _folderH(m) - 8;
    return Container(
      color: bg,
      padding: EdgeInsets.symmetric(horizontal: m.pad + m.cellW / 2, vertical: 4),
      child: LayoutBuilder(builder: (context, box) {
        // Only the chips that fit.
        final chips = <Widget>[];
        var x = 0.0;
        for (final dir in dirs) {
          final label = _folderLabel(dir);
          final w = label.runes.length * m.cellW + 2 * m.cellW;
          if (x + w > box.maxWidth) break;
          chips.add(Padding(
            padding: EdgeInsets.only(right: m.cellW / 2),
            child: KitTooltip(
              message: dir,
              child: Listener(
                onPointerDown: (e) {
                  if (e.buttons & kMiddleMouseButton != 0) _goToDir(dir, newTab: true);
                },
                child: Pressable(
                  onPressed: () => _goToDir(dir),
                  builder: (context, s) => Container(
                    height: chipH,
                    width: w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mix(bg, fg, s.hovered ? 0.16 : 0.06),
                      borderRadius: BorderRadius.circular(chipH / 2),
                    ),
                    child: Text(label,
                        maxLines: 1, style: TextStyle(color: s.hovered ? fg : mix(bg, fg, 0.6))),
                  ),
                ),
              ),
            ),
          ));
          x += w + m.cellW / 2;
        }
        return Row(children: chips);
      }),
    );
  }

  // --- file pane --------------------------------------------------------------------

  Widget _filePane(Metrics m, KitColors c) {
    return FilePaneView(
      model: pane,
      rowH: m.cellH + 6,
      focused: paneFocused && windowFocused,
      background: c.background,
      foreground: c.text,
      accent: c.accent,
      palette: [for (final v in _palette) rgbColor(v)],
      textStyle: DefaultTextStyle.of(context).style.copyWith(
            fontFamily: m.family,
            fontFamilyFallback: m.fallback,
            fontSize: m.fontSize,
          ),
      onClick: _onPaneClick,
      onScroll: (d) => setState(() => pane.scrollBy(d, _paneRows)),
      onHover: (i) => setState(() => pane.hovered = i),
      onRows: (r) => _paneRows = r,
    );
  }

  Widget _divider(KitColors c) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          final m = metrics!;
          final box = context.findRenderObject() as RenderBox;
          final maxW = math.max(12 * m.cellW, box.size.width - 20 * m.cellW - 2 * m.pad);
          setState(() => paneW = (paneW + d.delta.dx).clamp(12 * m.cellW, maxW));
        },
        onHorizontalDragEnd: (_) {
          _savePane();
        },
        child: Container(
            width: 5, alignment: Alignment.center, child: Container(width: 1, color: c.border)),
      ),
    );
  }
}

class _TabWidget extends StatefulWidget {
  final String title;
  final bool active, lifted, showDivider;
  final KitColors colors;
  final VoidCallback onClose;
  final void Function(PointerDownEvent) onPointerDown;
  final void Function(PointerMoveEvent) onPointerMove;
  final void Function(PointerUpEvent) onPointerUp;

  const _TabWidget({
    required this.title,
    required this.active,
    required this.lifted,
    required this.showDivider,
    required this.colors,
    required this.onClose,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
  });

  @override
  State<_TabWidget> createState() => _TabWidgetState();
}

class _TabWidgetState extends State<_TabWidget> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final bg = c.background, fg = c.text;
    final active = widget.active;
    final textFg = active ? fg : mix(bg, fg, 0.6);
    final Color? body = active
        ? bg
        : widget.lifted
            ? mix(bg, fg, 0.14)
            : (_hover ? mix(bg, fg, 0.12) : null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: widget.onPointerDown,
        onPointerMove: widget.onPointerMove,
        onPointerUp: widget.onPointerUp,
        child: Stack(children: [
          Positioned.fill(
            top: 4,
            left: 2,
            right: 2,
            bottom: active ? -1 : 0,
            child: Container(
              decoration: BoxDecoration(
                color: body,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                border: active
                    ? Border(
                        top: BorderSide(color: c.border),
                        left: BorderSide(color: c.border),
                        right: BorderSide(color: c.border),
                      )
                    : null,
              ),
            ),
          ),
          if (widget.showDivider)
            Positioned(
              right: 0,
              top: 12,
              bottom: 8,
              child: Container(width: 1, color: mix(bg, fg, 0.25)),
            ),
          Positioned.fill(
            top: 4,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(children: [
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: textFg, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: KitIconButton(Icons.close,
                      size: 16, color: textFg, tooltip: 'Close tab', onPressed: widget.onClose),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TerminalPainter extends CustomPainter {
  final Session session;
  final TerminalRenderer renderer;
  final bool focused, blinkOn;
  final void Function(Session) onPainted;

  _TerminalPainter({
    required this.session,
    required this.renderer,
    required this.focused,
    required this.blinkOn,
    required this.onPainted,
  }) : super(repaint: session);

  @override
  void paint(Canvas canvas, Size size) {
    renderer.paint(canvas, size, session, focused: focused, blinkOn: blinkOn);
    onPainted(session);
  }

  @override
  bool shouldRepaint(_TerminalPainter old) =>
      old.session != session ||
      old.renderer != renderer ||
      old.focused != focused ||
      old.blinkOn != blinkOn;
}
