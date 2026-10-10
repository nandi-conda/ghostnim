/// One tab's terminal: a libghostty-vt terminal fed by a child process on a
/// pseudo-terminal, and a snapshot of what to draw, read from libghostty's
/// render state with its per-row dirty tracking.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_pty/flutter_pty.dart';

import 'config.dart' show Colors, Rgb;
import 'vt.dart';

/// What to draw for one cell.
class CellInfo {
  String text = '';
  int fg = 0; // 0xRRGGBB
  int bg = 0;
  bool hasBg = false;
  bool bold = false, italic = false;
  bool faint = false, invisible = false, strike = false, overline = false;
  int underline = sgrUnderlineNone;
  bool wide = false;

  bool sameLook(CellInfo o) =>
      text == o.text &&
      fg == o.fg &&
      bg == o.bg &&
      hasBg == o.hasBg &&
      bold == o.bold &&
      italic == o.italic &&
      faint == o.faint &&
      invisible == o.invisible &&
      strike == o.strike &&
      overline == o.overline &&
      underline == o.underline &&
      wide == o.wide;
}

class RowInfo {
  List<CellInfo> cells;
  int selStart = -1, selEnd = -1;

  /// Changes whenever the row's content changes, so drawings of it can be
  /// cached. Unique across all rows ever made, so a row rebuilt after a
  /// resize never matches a drawing of the old one.
  int version = _nextVersion();
  RowInfo(int cols) : cells = List.generate(cols, (_) => CellInfo());

  void bump() => version = _nextVersion();

  static int _versions = 0;
  static int _nextVersion() => ++_versions;
}

class CursorInfo {
  bool visible = false;
  bool blinking = false;
  int x = 0, y = 0;
  int style = cursorBlock;
}

/// The colours libghostty reports for the terminal: defaults and palette.
class TermColors {
  int background = 0x000000;
  int foreground = 0xFFFFFF;
  int? cursor;
  final palette = List<int>.filled(256, 0);
}

int _rgb(GhosttyColorRgb c) => (c.r << 16) | (c.g << 8) | c.b;

/// Scratch memory shared by all sessions (everything runs on the UI isolate).
class _Scratch {
  static final u64 = calloc<Uint64>();
  static final u32 = calloc<Uint32>();
  static final u16 = calloc<Uint16>();
  static final i32 = calloc<Int32>();
  static final boolean = calloc<Bool>();
  static final size = calloc<Size>();
  static final utf8Buf = calloc<Uint8>(256);
  static final buffer = calloc<GhosttyBuffer>();
  static final rgb = calloc<GhosttyColorRgb>();
  static final style = calloc<GhosttyStyle>();
  static final rowSel = calloc<GhosttyRenderStateRowSelection>();
  static final colors = calloc<GhosttyRenderStateColors>();
  static final cursor = calloc<GhosttyRenderStateCursor>();
  static final gridRef = calloc<GhosttyGridRef>();
  static final gridRef2 = calloc<GhosttyGridRef>();
  static final selection = calloc<GhosttySelection>();
  static final point = calloc<GhosttyPoint>();
  static final scroll = calloc<GhosttyScrollViewport>();
  static final cps = calloc<Uint32>(16);
  static final ioBuf = calloc<Uint8>(65536);
  static final outBuf = calloc<Uint8>(256);
  static final string = calloc<GhosttyString>();
  static final modeCfg = calloc<GhosttyModeConfig>();
}

/// The child's current working directory (Linux /proc), or "" if unknown.
String procCwd(int pid) {
  try {
    return Link('/proc/$pid/cwd').resolveSymbolicLinksSync();
  } on FileSystemException {
    return '';
  }
}

class Session extends ChangeNotifier {
  final int id;
  late final GhosttyTerminal term;
  late final GhosttyRenderState _state;
  late final GhosttyRowIterator _rowIter;
  late final GhosttyRowCells _rowCells;
  late final Pty pty;
  late final NativeCallable<WritePtyNative> _writePty;
  late final NativeCallable<TerminalCallbackNative> _titleChanged;

  String title = '';
  String lastDir = '';
  bool exited = false;
  int cols, rows;

  /// Called when the child exits.
  VoidCallback? onExit;

  /// Called when the title changes.
  VoidCallback? onTitle;

  final List<RowInfo> grid = [];
  final colors = TermColors();
  final cursor = CursorInfo();
  bool _needsFull = true;
  bool _frameScheduled = false;
  bool _titleDirty = false;

  Session({
    required this.id,
    required this.cols,
    required this.rows,
    required int cellW,
    required int cellH,
    required List<String> command,
    required String cwd,
    required int scrollback,
  }) {
    final out = calloc<Pointer<Void>>();
    if (Vt.terminalNew(nullptr, out, cols, rows) != ghosttySuccess) {
      calloc.free(out);
      throw StateError('ghostty_terminal_new failed');
    }
    term = out.value;
    if (Vt.renderStateNew(nullptr, out) != ghosttySuccess) throw StateError('render state');
    _state = out.value;
    Vt.rowIteratorNew(nullptr, out);
    _rowIter = out.value;
    Vt.rowCellsNew(nullptr, out);
    _rowCells = out.value;
    calloc.free(out);
    Vt.terminalResize(term, cols, rows, cellW, cellH);
    setScrollback(scrollback);

    // The terminal wants to reply to the application (DA, DSR, ...).
    _writePty = NativeCallable<WritePtyNative>.isolateLocal(
        (GhosttyTerminal t, Pointer<Void> ud, Pointer<Uint8> data, int len) {
      if (!exited) pty.write(Uint8List.fromList(data.asTypedList(len)));
    });
    _titleChanged =
        NativeCallable<TerminalCallbackNative>.isolateLocal((GhosttyTerminal t, Pointer<Void> ud) {
      _titleDirty = true; // read once the write is done
    });
    Vt.terminalSet(term, termOptWritePty, _writePty.nativeFunction.cast());
    Vt.terminalSet(term, termOptTitleChanged, _titleChanged.nativeFunction.cast());

    final env = Map<String, String>.of(Platform.environment)
      ..['TERM'] = 'xterm-256color'
      ..['COLORTERM'] = 'truecolor'
      ..['TERM_PROGRAM'] = 'ghostnim';
    env.remove('VTE_VERSION');
    pty = Pty.start(
      command.first,
      arguments: command.sublist(1),
      workingDirectory: cwd.isNotEmpty ? cwd : null,
      environment: env,
      columns: cols,
      rows: rows,
    );
    pty.output.listen(_onOutput);
    pty.exitCode.then((_) {
      exited = true;
      onExit?.call();
    });
  }

  int get pid => pty.pid;

  String get cwd => procCwd(pty.pid);

  /// Whether the child itself (normally the shell) is in the foreground,
  /// rather than a program it started: the terminal's foreground process
  /// group (field 8 of /proc/PID/stat) is the child's own.
  bool get atPrompt {
    try {
      final stat = File('/proc/${pty.pid}/stat').readAsStringSync();
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      return int.parse(fields[5]) == pty.pid;
    } catch (_) {
      return true;
    }
  }

  void _onOutput(Uint8List data) {
    var off = 0;
    while (off < data.length) {
      final n = (data.length - off).clamp(0, 65536);
      _Scratch.ioBuf.asTypedList(n).setRange(0, n, data, off);
      Vt.terminalVtWrite(term, _Scratch.ioBuf, n);
      off += n;
    }
    if (_titleDirty) {
      _titleDirty = false;
      _refreshTitle();
    }
    changed();
  }

  /// Ask for a repaint at the next frame (once, however much output comes).
  void changed({bool full = false}) {
    if (full) _needsFull = true;
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _refreshTitle() {
    title = '';
    if (Vt.terminalGet(term, termDataTitle, _Scratch.string.cast()) == ghosttySuccess &&
        _Scratch.string.ref.len > 0) {
      title = utf8.decode(_Scratch.string.ref.ptr.asTypedList(_Scratch.string.ref.len),
          allowMalformed: true);
    }
    onTitle?.call();
  }

  void write(List<int> bytes) {
    if (exited || bytes.isEmpty) return;
    pty.write(Uint8List.fromList(bytes));
  }

  /// Send input typed by the user: the viewport jumps to the bottom first.
  void sendInput(String s) {
    if (s.isEmpty) return;
    scrollViewport(scrollViewportBottom);
    write(utf8.encode(s));
  }

  void sendBytes(List<int> b) {
    if (b.isEmpty) return;
    scrollViewport(scrollViewportBottom);
    write(b);
  }

  void resize(int cols, int rows, int cellW, int cellH) {
    if (cols == this.cols && rows == this.rows) {
      Vt.terminalResize(term, cols, rows, cellW, cellH);
      return;
    }
    this.cols = cols;
    this.rows = rows;
    Vt.terminalResize(term, cols, rows, cellW, cellH);
    if (!exited) pty.resize(rows, cols);
    changed(full: true);
  }

  void setScrollback(int lines) {
    _Scratch.size.value = lines;
    Vt.terminalSet(term, termOptScrollbackMaxLines, _Scratch.size.cast());
  }

  /// The config file's colours become the terminal's defaults, which
  /// programs can still override with OSC 4/10/11/12. Unset ones go back to
  /// the built-in ones.
  void applyColors(Colors c) {
    void set(int opt, Rgb? col) {
      if (col == null) {
        Vt.terminalSet(term, opt, nullptr);
        return;
      }
      _Scratch.rgb.ref
        ..r = col.$1
        ..g = col.$2
        ..b = col.$3;
      Vt.terminalSet(term, opt, _Scratch.rgb.cast());
    }

    set(termOptColorForeground, c.foreground);
    set(termOptColorBackground, c.background);
    set(termOptColorCursor, c.cursor);
    // Reset first, so PALETTE_DEFAULT is the built-in palette, not the last
    // config's.
    Vt.terminalSet(term, termOptColorPalette, nullptr);
    if (c.palette.isNotEmpty) {
      final pal = calloc<GhosttyColorRgb>(256);
      Vt.terminalGet(term, termDataColorPaletteDefault, pal.cast());
      for (final (i, col) in c.palette) {
        pal[i]
          ..r = col.$1
          ..g = col.$2
          ..b = col.$3;
      }
      Vt.terminalSet(term, termOptColorPalette, pal.cast());
      calloc.free(pal);
    }
    changed(full: true);
  }

  // --- viewport, modes --------------------------------------------------------

  void scrollViewport(int tag, [int delta = 0]) {
    _Scratch.scroll.ref.tag = tag;
    _Scratch.scroll.ref.value.delta = delta;
    Vt.terminalScrollViewport(term, _Scratch.scroll.ref);
    changed();
  }

  bool modeEnabled(int mode) {
    _Scratch.modeCfg.ref
      ..mode = mode
      ..value = false;
    return Vt.terminalGet(term, termDataMode, _Scratch.modeCfg.cast()) == ghosttySuccess &&
        _Scratch.modeCfg.ref.value;
  }

  bool get mouseTracking {
    _Scratch.boolean.value = false;
    return Vt.terminalGet(term, termDataMouseTracking, _Scratch.boolean.cast()) == ghosttySuccess &&
        _Scratch.boolean.value;
  }

  // --- grid references and selection ------------------------------------------

  /// A grid reference for (col, row) in [tag] coordinates, written to [out].
  bool gridRef(int col, int row, Pointer<GhosttyGridRef> out, [int tag = pointTagViewport]) {
    _Scratch.point.ref.tag = tag;
    _Scratch.point.ref.value.coordinate
      ..x = col
      ..y = row;
    out.ref.size = sizeOf<GhosttyGridRef>();
    return Vt.terminalGridRef(term, _Scratch.point.ref, out) == ghosttySuccess;
  }

  void _initSelection() {
    final s = _Scratch.selection;
    s.ref.size = sizeOf<GhosttySelection>();
    s.ref.rectangle = false;
  }

  void setSelection((int, int) a, (int, int) b) {
    if (!gridRef(a.$1, a.$2, _Scratch.gridRef) || !gridRef(b.$1, b.$2, _Scratch.gridRef2)) return;
    _initSelection();
    _Scratch.selection.ref.start = _Scratch.gridRef.ref;
    _Scratch.selection.ref.end = _Scratch.gridRef2.ref;
    Vt.terminalSet(term, termOptSelection, _Scratch.selection.cast());
    changed();
  }

  /// Select everything, from the top of the scrollback to the bottom-right
  /// of the active screen.
  void selectAll() {
    if (!gridRef(0, 0, _Scratch.gridRef, pointTagScreen) ||
        !gridRef((cols - 1).clamp(0, 1 << 16), (rows - 1).clamp(0, 1 << 30), _Scratch.gridRef2,
            pointTagActive)) {
      return;
    }
    _initSelection();
    _Scratch.selection.ref.start = _Scratch.gridRef.ref;
    _Scratch.selection.ref.end = _Scratch.gridRef2.ref;
    Vt.terminalSet(term, termOptSelection, _Scratch.selection.cast());
    changed();
  }

  void clearSelection() {
    Vt.terminalSet(term, termOptSelection, nullptr);
    changed();
  }

  bool get hasSelection {
    _initSelection();
    return Vt.terminalGet(term, termDataSelection, _Scratch.selection.cast()) == ghosttySuccess;
  }

  /// Point the dragged end of the selection at viewport [cell], keeping the
  /// other end where it is even if the viewport has scrolled since.
  bool moveSelectionEnd((int, int) cell, {required bool backward}) {
    _initSelection();
    if (Vt.terminalGet(term, termDataSelection, _Scratch.selection.cast()) != ghosttySuccess) {
      return false;
    }
    if (!gridRef(cell.$1, cell.$2, _Scratch.gridRef)) return false;
    if (backward) {
      _Scratch.selection.ref.start = _Scratch.gridRef.ref;
    } else {
      _Scratch.selection.ref.end = _Scratch.gridRef.ref;
    }
    final ok = Vt.terminalSet(term, termOptSelection, _Scratch.selection.cast()) == ghosttySuccess;
    changed();
    return ok;
  }

  /// The selection as plain text, or null if there is none.
  String? selectionText() {
    _initSelection();
    if (Vt.terminalGet(term, termDataSelection, _Scratch.selection.cast()) != ghosttySuccess) {
      return null;
    }
    final opts = calloc<GhosttyFormatterTerminalOptions>();
    opts.ref
      ..size = sizeOf<GhosttyFormatterTerminalOptions>()
      ..emit = formatterFormatPlain
      ..unwrap = true
      ..trim = true
      ..selection = _Scratch.selection;
    opts.ref.extra.size = sizeOf<GhosttyFormatterTerminalExtra>();
    opts.ref.extra.screen.size = sizeOf<GhosttyFormatterScreenExtra>();
    final fmt = calloc<Pointer<Void>>();
    final outPtr = calloc<Pointer<Uint8>>();
    String? result;
    if (Vt.formatterTerminalNew(nullptr, fmt, term, opts.ref) == ghosttySuccess) {
      if (Vt.formatterFormatAlloc(fmt.value, nullptr, outPtr, _Scratch.size) == ghosttySuccess &&
          outPtr.value != nullptr) {
        final n = _Scratch.size.value;
        result = utf8.decode(outPtr.value.asTypedList(n), allowMalformed: true);
        Vt.free(nullptr, outPtr.value.cast(), n);
      }
      Vt.formatterFree(fmt.value);
    }
    calloc.free(fmt);
    calloc.free(outPtr);
    calloc.free(opts);
    return result;
  }

  /// Encode a paste for the program (bracketed when it asked for that).
  List<int> encodePaste(String text) {
    final bracketed = modeEnabled(ghosttyMode(2004, false));
    final data = utf8.encode(text);
    final inBuf = calloc<Uint8>(data.length + 1);
    inBuf.asTypedList(data.length).setAll(0, data);
    final cap = data.length * 2 + 16;
    final outBuf = calloc<Uint8>(cap);
    var result = <int>[];
    if (Vt.pasteEncode(inBuf, data.length, bracketed, outBuf, cap, _Scratch.size) ==
        ghosttySuccess) {
      result = Uint8List.fromList(outBuf.asTypedList(_Scratch.size.value));
    }
    calloc.free(inBuf);
    calloc.free(outBuf);
    return result;
  }

  // --- cell text, for links and word selection --------------------------------

  /// The cell's text: " " when blank, "" for the right half of a wide
  /// character.
  String _cellText(Pointer<GhosttyGridRef> r) {
    if (Vt.gridRefCell(r, _Scratch.u64) == ghosttySuccess &&
        Vt.cellGet(_Scratch.u64.value, cellDataWide, _Scratch.i32.cast()) == ghosttySuccess &&
        _Scratch.i32.value == cellWideSpacerTail) {
      return '';
    }
    if (Vt.gridRefGraphemes(r, _Scratch.cps, 16, _Scratch.size) != ghosttySuccess ||
        _Scratch.size.value == 0) {
      return ' ';
    }
    return String.fromCharCodes(_Scratch.cps.asTypedList(_Scratch.size.value));
  }

  /// Whether viewport row [row] soft-wraps onto the next one.
  bool rowWraps(int row) {
    if (!gridRef(0, row, _Scratch.gridRef)) return false;
    _Scratch.boolean.value = false;
    return Vt.gridRefRow(_Scratch.gridRef, _Scratch.u64) == ghosttySuccess &&
        Vt.rowGet(_Scratch.u64.value, rowDataWrap, _Scratch.boolean.cast()) == ghosttySuccess &&
        _Scratch.boolean.value;
  }

  /// The (soft-wrapped) line through viewport row [row]: its first and last
  /// rows, and the text of each of its cells.
  ({int first, int last, List<String> cells}) lineAt(int row) {
    var first = row;
    while (first > 0 && rowWraps(first - 1)) {
      first--;
    }
    var last = row;
    while (last < rows - 1 && rowWraps(last)) {
      last++;
    }
    final cells = <String>[];
    for (var y = first; y <= last; y++) {
      for (var x = 0; x < cols; x++) {
        cells.add(gridRef(x, y, _Scratch.gridRef) ? _cellText(_Scratch.gridRef) : ' ');
      }
    }
    return (first: first, last: last, cells: cells);
  }

  /// The OSC 8 hyperlink of viewport cell (col, row), or "".
  String hyperlinkAt(int col, int row) {
    if (!gridRef(col, row, _Scratch.gridRef)) return '';
    if (Vt.gridRefHyperlinkUri(_Scratch.gridRef, nullptr, 0, _Scratch.size) != ghosttyOutOfSpace ||
        _Scratch.size.value == 0) {
      return '';
    }
    final n = _Scratch.size.value;
    final buf = calloc<Uint8>(n);
    var result = '';
    if (Vt.gridRefHyperlinkUri(_Scratch.gridRef, buf, n, _Scratch.size) == ghosttySuccess) {
      result = utf8.decode(buf.asTypedList(_Scratch.size.value), allowMalformed: true);
    }
    calloc.free(buf);
    return result;
  }

  // --- render state --------------------------------------------------------------

  /// Update the snapshot from libghostty: colours, cursor, and the rows it
  /// marks dirty. Returns true if any row changed.
  bool update() {
    if (Vt.renderStateUpdate(_state, term) != ghosttySuccess) return false;
    Vt.renderStateGet(_state, renderDataDirty, _Scratch.i32.cast());
    final dirty = _Scratch.i32.value;

    final c = _Scratch.colors;
    c.ref.size = sizeOf<GhosttyRenderStateColors>();
    Vt.renderStateGet(_state, renderDataColors, c.cast());
    final bg = _rgb(c.ref.background), fg = _rgb(c.ref.foreground);
    var full = _needsFull || dirty == renderDirtyFull;
    if (bg != colors.background || fg != colors.foreground) full = true;
    colors.background = bg;
    colors.foreground = fg;
    colors.cursor = c.ref.cursorHasValue ? _rgb(c.ref.cursor) : null;
    for (var i = 0; i < 256; i++) {
      colors.palette[i] = _rgb(c.ref.palette[i]);
    }

    Vt.renderStateGet(_state, renderDataCols, _Scratch.u16.cast());
    final nCols = _Scratch.u16.value;
    Vt.renderStateGet(_state, renderDataRows, _Scratch.u16.cast());
    final nRows = _Scratch.u16.value;
    if (grid.length != nRows || (nRows > 0 && grid[0].cells.length != nCols)) {
      grid
        ..clear()
        ..addAll(List.generate(nRows, (_) => RowInfo(nCols)));
      full = true;
    }

    final cur = _Scratch.cursor;
    cur.ref.size = sizeOf<GhosttyRenderStateCursor>();
    Vt.renderStateGet(_state, renderDataCursor, cur.cast());
    cursor
      ..visible = cur.ref.visible && cur.ref.viewportHasValue
      ..blinking = cur.ref.blinking
      ..x = cur.ref.viewportX
      ..y = cur.ref.viewportY
      ..style = cur.ref.visualStyle;

    var any = false;
    if (full || dirty != renderDirtyFalse) {
      final it = calloc<Pointer<Void>>()..value = _rowIter;
      Vt.renderStateGet(_state, renderDataRowIterator, it.cast());
      calloc.free(it);
      var row = 0;
      while (Vt.rowIteratorNext(_rowIter) && row < grid.length) {
        _Scratch.boolean.value = false;
        Vt.rowGetState(_rowIter, rowDataDirty, _Scratch.boolean.cast());
        if (full || _Scratch.boolean.value) {
          if (_readRow(grid[row]) || full) {
            grid[row].bump();
            any = true;
          }
        }
        row++;
      }
      Vt.renderStateClean(_state);
    }
    _needsFull = false;
    return any;
  }

  /// Pull the current row's cells out of the render state. True if anything
  /// in it looks different.
  bool _readRow(RowInfo row) {
    var changed = false;
    final sel = _Scratch.rowSel;
    sel.ref.size = sizeOf<GhosttyRenderStateRowSelection>();
    var selStart = -1, selEnd = -1;
    if (Vt.rowGetState(_rowIter, rowDataSelection, sel.cast()) == ghosttySuccess) {
      selStart = sel.ref.startX;
      selEnd = sel.ref.endX;
    }
    if (selStart != row.selStart || selEnd != row.selEnd) changed = true;
    row.selStart = selStart;
    row.selEnd = selEnd;

    final cellsOut = calloc<Pointer<Void>>()..value = _rowCells;
    Vt.rowGetState(_rowIter, rowDataCells, cellsOut.cast());
    calloc.free(cellsOut);

    final defFg = colors.foreground;
    final scratch = CellInfo();
    var col = 0;
    while (Vt.rowCellsNext(_rowCells)) {
      if (col >= row.cells.length) break;
      final c = scratch
        ..text = ''
        ..fg = defFg
        ..bg = 0
        ..hasBg = false
        ..wide = false;
      if (Vt.rowCellsGet(_rowCells, cellsDataRaw, _Scratch.u64.cast()) == ghosttySuccess &&
          Vt.cellGet(_Scratch.u64.value, cellDataWide, _Scratch.i32.cast()) == ghosttySuccess) {
        c.wide = _Scratch.i32.value == cellWideWide;
      }
      _Scratch.u32.value = 0;
      Vt.rowCellsGet(_rowCells, cellsDataGraphemesLen, _Scratch.u32.cast());
      if (_Scratch.u32.value > 0) {
        final buf = _Scratch.buffer.ref
          ..ptr = _Scratch.utf8Buf
          ..cap = 256
          ..len = 0;
        if (Vt.rowCellsGet(_rowCells, cellsDataGraphemesUtf8, _Scratch.buffer.cast()) ==
                ghosttySuccess &&
            buf.len > 0) {
          c.text = utf8.decode(_Scratch.utf8Buf.asTypedList(buf.len), allowMalformed: true);
        }
      }
      final st = _Scratch.style;
      st.ref.size = sizeOf<GhosttyStyle>();
      Vt.rowCellsGet(_rowCells, cellsDataStyle, st.cast());
      if (Vt.rowCellsGet(_rowCells, cellsDataFgColor, _Scratch.rgb.cast()) == ghosttySuccess) {
        c.fg = _rgb(_Scratch.rgb.ref);
      }
      if (Vt.rowCellsGet(_rowCells, cellsDataBgColor, _Scratch.rgb.cast()) == ghosttySuccess) {
        c.bg = _rgb(_Scratch.rgb.ref);
        c.hasBg = true;
      }
      if (st.ref.inverse) {
        final bg = c.hasBg ? c.bg : colors.background;
        c.bg = c.fg;
        c.fg = bg;
        c.hasBg = true;
      }
      c
        ..bold = st.ref.bold
        ..italic = st.ref.italic
        ..faint = st.ref.faint
        ..invisible = st.ref.invisible
        ..strike = st.ref.strikethrough
        ..overline = st.ref.overline
        ..underline = st.ref.underline;
      final target = row.cells[col];
      if (!target.sameLook(c)) {
        changed = true;
        _copy(c, target);
      }
      col++;
    }
    for (var x = col; x < row.cells.length; x++) {
      final t = row.cells[x];
      if (t.text.isNotEmpty || t.hasBg) {
        changed = true;
        row.cells[x] = CellInfo()..fg = defFg;
      }
    }
    return changed;
  }

  static void _copy(CellInfo s, CellInfo d) {
    d
      ..text = s.text
      ..fg = s.fg
      ..bg = s.bg
      ..hasBg = s.hasBg
      ..bold = s.bold
      ..italic = s.italic
      ..faint = s.faint
      ..invisible = s.invisible
      ..strike = s.strike
      ..overline = s.overline
      ..underline = s.underline
      ..wide = s.wide;
  }

  void close() {
    if (!exited) pty.kill(ProcessSignal.sighup);
  }

  @override
  void dispose() {
    close();
    Vt.renderStateFree(_state);
    Vt.rowCellsFree(_rowCells);
    Vt.rowIteratorFree(_rowIter);
    Vt.terminalFree(term);
    _writePty.close();
    _titleChanged.close();
    super.dispose();
  }
}

/// The libghostty key and mouse encoders, shared by all tabs.
class Encoders {
  late final GhosttyKeyEncoder key;
  late final GhosttyKeyEvent keyEvent;
  late final GhosttyMouseEncoder mouse;
  late final GhosttyMouseEvent mouseEvent;
  final _utf8 = calloc<Uint8>(64);
  final _size = calloc<GhosttyMouseEncoderSize>();
  final _anyPressed = calloc<Bool>();
  final _pos = calloc<GhosttyMousePosition>();

  Encoders() {
    final out = calloc<Pointer<Void>>();
    Vt.keyEncoderNew(nullptr, out);
    key = out.value;
    Vt.keyEventNew(nullptr, out);
    keyEvent = out.value;
    Vt.mouseEncoderNew(nullptr, out);
    mouse = out.value;
    Vt.mouseEventNew(nullptr, out);
    mouseEvent = out.value;
    calloc.free(out);
  }

  /// The bytes to send for a key event, or empty.
  List<int> encodeKey(Session s, int keyCode, int action, int mods, int unshifted, String text) {
    final ev = keyEvent;
    Vt.keyEventSetAction(ev, action);
    Vt.keyEventSetKey(ev, keyCode);
    Vt.keyEventSetMods(ev, mods);
    Vt.keyEventSetConsumedMods(ev, 0);
    Vt.keyEventSetUnshiftedCodepoint(ev, unshifted);
    final bytes = utf8.encode(text);
    final n = bytes.length.clamp(0, 63);
    _utf8.asTypedList(n).setAll(0, bytes.take(n));
    Vt.keyEventSetUtf8(ev, _utf8, n);
    // Pick up the terminal's current keyboard modes (DECCKM, kitty flags, ...).
    Vt.keyEncoderSetoptFromTerminal(key, s.term);
    if (Vt.keyEncoderEncode(key, ev, _Scratch.outBuf, 256, _Scratch.size) == ghosttySuccess &&
        _Scratch.size.value > 0) {
      return Uint8List.fromList(_Scratch.outBuf.asTypedList(_Scratch.size.value));
    }
    return const [];
  }

  void setSize({
    required double width,
    required double height,
    required int cellW,
    required int cellH,
    required int padLeft,
    required int padTop,
    required int padRight,
    required int padBottom,
  }) {
    _size.ref
      ..size = sizeOf<GhosttyMouseEncoderSize>()
      ..screenWidth = width.round()
      ..screenHeight = height.round()
      ..cellWidth = cellW
      ..cellHeight = cellH
      ..paddingLeft = padLeft
      ..paddingTop = padTop
      ..paddingRight = padRight.clamp(0, 1 << 30)
      ..paddingBottom = padBottom.clamp(0, 1 << 30);
    Vt.mouseEncoderSetopt(mouse, mouseEncoderOptSize, _size.cast());
  }

  /// The bytes to send for a mouse event at (x, y) in the terminal view.
  List<int> encodeMouse(Session s, int action, int button, int mods, double x, double y,
      {required bool anyPressed}) {
    final ev = mouseEvent;
    Vt.mouseEventSetAction(ev, action);
    if (button == 0) {
      Vt.mouseEventClearButton(ev);
    } else {
      Vt.mouseEventSetButton(ev, button);
    }
    Vt.mouseEventSetMods(ev, mods);
    _pos.ref
      ..x = x
      ..y = y;
    Vt.mouseEventSetPosition(ev, _pos.ref);
    Vt.mouseEncoderSetoptFromTerminal(mouse, s.term);
    _anyPressed.value = anyPressed;
    Vt.mouseEncoderSetopt(mouse, mouseEncoderOptAnyButtonPressed, _anyPressed.cast());
    if (Vt.mouseEncoderEncode(mouse, ev, _Scratch.outBuf, 256, _Scratch.size) == ghosttySuccess &&
        _Scratch.size.value > 0) {
      return Uint8List.fromList(_Scratch.outBuf.asTypedList(_Scratch.size.value));
    }
    return const [];
  }
}
