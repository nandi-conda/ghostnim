/// Draws a session's snapshot of libghostty's render state onto a canvas.
///
/// Each row is recorded into a [ui.Picture] that is kept until libghostty
/// marks the row dirty again, so a frame only re-records the rows that
/// changed; the cursor is drawn on top every frame.
library;

import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;

import 'boxdraw.dart';
import 'session.dart';
import 'vt.dart';

/// The default font families, tried in order. The Frozen build has its
/// ligatures and texture healing on by default.
const defaultFonts = ['Monaspace Neon Frozen', 'Monaspace Neon'];

/// Font settings and the cell size they give, in logical pixels.
class Metrics {
  final String family;
  final List<String> fallback;
  final double fontSize;
  final bool shaping;
  final double devicePixelRatio;
  late final double cellW, cellH, ascent;

  /// The padding around the grid.
  final double pad = 4;

  Metrics({
    required this.family,
    required this.fallback,
    required this.fontSize,
    required this.shaping,
    required this.devicePixelRatio,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMM', style: style(bold: false, italic: false)),
      textDirection: TextDirection.ltr,
    )..layout();
    final m = tp.computeLineMetrics().first;
    cellW = tp.width / 10;
    // Whole device pixels, so rows don't blur into each other.
    cellH = (tp.height * devicePixelRatio).ceilToDouble() / devicePixelRatio;
    ascent = m.ascent;
    tp.dispose();
  }

  /// Cell width and height in whole pixels, for libghostty and the pty.
  int get cellWi => math.max(1, cellW.round());
  int get cellHi => math.max(1, cellH.round());

  TextStyle style({required bool bold, required bool italic, Color? color}) => TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: fontSize,
        height: 1.0,
        leadingDistribution: TextLeadingDistribution.even,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
        fontFeatures:
            shaping ? null : const [FontFeature.disable('liga'), FontFeature.disable('calt')],
      );

  bool sameAs(Metrics o) =>
      family == o.family &&
      fontSize == o.fontSize &&
      shaping == o.shaping &&
      devicePixelRatio == o.devicePixelRatio &&
      fallback.join('\n') == o.fallback.join('\n');
}

const _fallbackFonts = ['DejaVu Sans Mono', 'Symbols Nerd Font Mono', 'monospace'];

/// Fonts shipped next to the executable (the AppImage puts Monaspace, DejaVu
/// Sans Mono and the Nerd Font symbols in data/fonts), by family, from the
/// file name: "MonaspaceNeonFrozen-Bold.ttf" is "Monaspace Neon Frozen".
const _bundledFamilies = {
  'MonaspaceNeonFrozen': 'Monaspace Neon Frozen',
  'MonaspaceNeon': 'Monaspace Neon',
  'DejaVuSansMono': 'DejaVu Sans Mono',
  'SymbolsNerdFontMono': 'Symbols Nerd Font Mono',
};

bool _bundledLoaded = false;

Future<void> _loadBundledFonts() async {
  if (_bundledLoaded) return;
  _bundledLoaded = true;
  final dir = Directory(p.join(p.dirname(Platform.resolvedExecutable), 'data', 'fonts'));
  if (!dir.existsSync()) return;
  final byFamily = <String, List<File>>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(f.path)) continue;
    final family = _bundledFamilies[p.basenameWithoutExtension(f.path).split('-').first];
    if (family != null) byFamily.putIfAbsent(family, () => []).add(f);
  }
  for (final MapEntry(key: family, value: files) in byFamily.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(f.readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }
}

/// Resolve the configured font: a font file is loaded under its own family
/// name; a family name is used as is (fontconfig finds it), with the
/// defaults and "monospace" as fallbacks.
Future<(String, List<String>)> resolveFont(String font) async {
  await _loadBundledFonts();
  if (font.isNotEmpty && File(font).existsSync()) {
    final family = 'ghostnim:${p.basenameWithoutExtension(font)}';
    final loader = FontLoader(family);
    loader.addFont(File(font).readAsBytes().then((b) => b.buffer.asByteData()));
    await loader.load();
    return (family, [...defaultFonts, ..._fallbackFonts]);
  }
  if (font.isNotEmpty) return (font, [...defaultFonts, ..._fallbackFonts]);
  return (defaultFonts.first, [...defaultFonts.skip(1), ..._fallbackFonts]);
}

Color rgbColor(int rgb, [double alpha = 1]) =>
    Color.fromARGB((alpha * 255).round(), (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);

/// Paragraphs of laid-out text, by (text, look). Text in a terminal repeats
/// a lot, so this saves most of the shaping work.
class _ParagraphCache {
  final _map = LinkedHashMap<String, ui.Paragraph>();

  ui.Paragraph get(Metrics m, String text, bool bold, bool italic, int color, bool faint) {
    final key = '${bold ? 'b' : ''}${italic ? 'i' : ''}$color${faint ? 'f' : ''}\u0000$text';
    final hit = _map.remove(key);
    if (hit != null) {
      _map[key] = hit;
      return hit;
    }
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
      ..pushStyle(m
          .style(bold: bold, italic: italic, color: rgbColor(color, faint ? 0.5 : 1))
          .getTextStyle())
      ..addText(text);
    final para = b.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    _map[key] = para;
    if (_map.length > 4096) {
      _map.remove(_map.keys.first)?.dispose();
    }
    return para;
  }

  void clear() {
    for (final para in _map.values) {
      para.dispose();
    }
    _map.clear();
  }
}

class TerminalRenderer {
  Metrics metrics;
  int? selectionFg, selectionBg; // unset: swap fg and bg
  final _paragraphs = _ParagraphCache();
  final _rows = <int, (int, ui.Picture)>{}; // row -> (version, picture)

  TerminalRenderer(this.metrics);

  void setMetrics(Metrics m) {
    metrics = m;
    invalidate();
    _paragraphs.clear();
  }

  void invalidate() {
    for (final (_, pic) in _rows.values) {
      pic.dispose();
    }
    _rows.clear();
  }

  double cellX(int col) => metrics.pad + col * metrics.cellW;
  double cellY(int row) => metrics.pad + row * metrics.cellH;

  /// (fg, bg, drawBg) after applying selection.
  (int, int, bool) _resolved(Session s, CellInfo c, bool selected) {
    var fg = c.fg;
    var bg = c.hasBg ? c.bg : s.colors.background;
    var drawBg = c.hasBg;
    if (selected) {
      final f = fg;
      fg = selectionFg ?? bg;
      bg = selectionBg ?? f;
      drawBg = true;
    }
    return (fg, bg, drawBg);
  }

  /// Paint the terminal: rows (re-recording the dirty ones) and the cursor.
  void paint(Canvas canvas, Size size, Session s, {required bool focused, required bool blinkOn}) {
    s.update();
    canvas.drawRect(Offset.zero & size, Paint()..color = rgbColor(s.colors.background));
    for (var y = 0; y < s.grid.length; y++) {
      final row = s.grid[y];
      var cached = _rows[y];
      if (cached == null || cached.$1 != row.version) {
        cached?.$2.dispose();
        final rec = ui.PictureRecorder();
        _drawRow(Canvas(rec), s, row, y);
        cached = (row.version, rec.endRecording());
        _rows[y] = cached;
      }
      canvas.drawPicture(cached.$2);
    }
    for (final k in _rows.keys.where((k) => k >= s.grid.length).toList()) {
      _rows.remove(k)?.$2.dispose();
    }
    final cur = s.cursor;
    if (cur.visible && (blinkOn || !cur.blinking || !focused)) {
      _drawCursor(canvas, s, focused);
    }
  }

  bool _runnable(CellInfo c) {
    // Plain ASCII in the cell's own face can be drawn as one shaped run,
    // which keeps ligatures; anything else is drawn cell by cell so fallback
    // fonts can't push the rest of the line off the grid.
    if (c.text.length != 1 || c.invisible || c.wide) return false;
    final cp = c.text.codeUnitAt(0);
    return cp >= 0x20 && cp < 0x7F;
  }

  void _drawRow(Canvas canvas, Session s, RowInfo row, int y) {
    final m = metrics;
    final cells = row.cells;
    final top = cellY(y);
    bool isSel(int x) => row.selStart >= 0 && x >= row.selStart && x <= row.selEnd;
    final bgPaint = Paint()..isAntiAlias = false;
    // Pass 1: backgrounds, so wide/overhanging glyphs aren't painted over.
    for (var x = 0; x < cells.length; x++) {
      final (_, bg, drawBg) = _resolved(s, cells[x], isSel(x));
      if (!drawBg) continue;
      bgPaint.color = rgbColor(bg);
      // Snap to device pixels so neighbouring backgrounds don't leave seams.
      final dpr = m.devicePixelRatio;
      final l = (cellX(x) * dpr).roundToDouble() / dpr;
      final r = (cellX(x + 1) * dpr).roundToDouble() / dpr;
      canvas.drawRect(Rect.fromLTRB(l, top, r, top + m.cellH), bgPaint);
    }
    // Pass 2: glyphs and decorations. Neighbouring cells that share a face
    // and colour form a run, drawn as one string so ligatures can form.
    var x = 0;
    while (x < cells.length) {
      final c = cells[x];
      final (fg, _, _) = _resolved(s, c, isSel(x));
      var last = x + 1;
      if (m.shaping && _runnable(c)) {
        while (last < cells.length &&
            cells[last].bold == c.bold &&
            cells[last].italic == c.italic &&
            cells[last].faint == c.faint &&
            _runnable(cells[last]) &&
            _resolved(s, cells[last], isSel(last)).$1 == fg) {
          last++;
        }
      }
      if (last - x >= 2) {
        final text = StringBuffer();
        for (var i = x; i < last; i++) {
          text.write(cells[i].text);
        }
        final t = text.toString();
        if (t.trim().isNotEmpty) {
          final para = _paragraphs.get(m, t, c.bold, c.italic, fg, c.faint);
          canvas.drawParagraph(para, Offset(cellX(x), top));
        }
      } else {
        for (var i = x; i < last; i++) {
          _drawGlyph(canvas, s, cells[i], i, y, fg);
        }
      }
      for (var i = x; i < last; i++) {
        _drawDecorations(canvas, cells[i], i, y, fg);
      }
      x = last;
    }
  }

  void _drawGlyph(Canvas canvas, Session s, CellInfo c, int col, int row, int fg) {
    if (c.text.isEmpty || c.invisible || c.text == ' ') return;
    final m = metrics;
    final cp = c.text.runes.first;
    if (c.text.runes.length == 1 && isSpecial(cp)) {
      drawSpecial(
          canvas, cp, cellX(col), cellY(row), m.cellW, m.cellH, rgbColor(fg, c.faint ? 0.5 : 1),
          px: 1 / m.devicePixelRatio);
      return;
    }
    final para = _paragraphs.get(m, c.text, c.bold, c.italic, fg, c.faint);
    final span = (c.wide ? 2 : 1) * m.cellW;
    var dx = 0.0;
    var scale = 1.0;
    final w = para.maxIntrinsicWidth;
    if (w > span * 1.05 && w > 0) {
      // A fallback glyph wider than its cells (emoji, some symbols): shrink
      // it to fit rather than run into the neighbours.
      scale = span / w;
    } else if (c.wide && w < span) {
      dx = (span - w) / 2; // centre CJK in its two cells
    }
    if (scale == 1.0) {
      canvas.drawParagraph(para, Offset(cellX(col) + dx, cellY(row)));
    } else {
      canvas.save();
      final h = para.height * scale;
      canvas.translate(cellX(col), cellY(row) + (m.cellH - h) / 2);
      canvas.scale(scale);
      canvas.drawParagraph(para, Offset.zero);
      canvas.restore();
    }
  }

  void _drawDecorations(Canvas canvas, CellInfo c, int col, int row, int fg) {
    if (c.underline == sgrUnderlineNone && !c.strike && !c.overline) return;
    final m = metrics;
    final x = cellX(col), y = cellY(row);
    final w = (c.wide ? 2 : 1) * m.cellW;
    final thick = math.max(1.0, m.cellH / 16).roundToDouble();
    final paint = Paint()
      ..color = rgbColor(fg, c.faint ? 0.5 : 1)
      ..isAntiAlias = false;
    if (c.underline != sgrUnderlineNone) {
      final uy = y + math.min(m.cellH - thick, m.ascent + 2 * thick);
      canvas.drawRect(Rect.fromLTWH(x, uy, w, thick), paint);
      if (c.underline == sgrUnderlineDouble) {
        canvas.drawRect(Rect.fromLTWH(x, math.max(y, uy - 2 * thick), w, thick), paint);
      }
    }
    if (c.strike) canvas.drawRect(Rect.fromLTWH(x, y + m.ascent * 2 / 3, w, thick), paint);
    if (c.overline) canvas.drawRect(Rect.fromLTWH(x, y, w, thick), paint);
  }

  void _drawCursor(Canvas canvas, Session s, bool focused) {
    final cur = s.cursor;
    if (cur.y >= s.grid.length || cur.x >= s.grid[cur.y].cells.length) return;
    final m = metrics;
    final cell = s.grid[cur.y].cells[cur.x];
    final color = rgbColor(s.colors.cursor ?? s.colors.foreground);
    final x = cellX(cur.x), y = cellY(cur.y);
    final w = (cell.wide ? 2 : 1) * m.cellW;
    const thick = 2.0;
    final paint = Paint()..color = color;
    final style = focused ? cur.style : cursorBlockHollow;
    switch (style) {
      case cursorBar:
        canvas.drawRect(Rect.fromLTWH(x, y, thick, m.cellH), paint);
      case cursorUnderline:
        canvas.drawRect(Rect.fromLTWH(x, y + m.cellH - thick, w, thick), paint);
      case cursorBlockHollow:
        canvas.drawRect(
            Rect.fromLTWH(x + 0.5, y + 0.5, w - 1, m.cellH - 1),
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      default:
        canvas.drawRect(Rect.fromLTWH(x, y, w, m.cellH), paint);
        // Re-draw the character under the cursor in the background colour.
        final bg = cell.hasBg ? cell.bg : s.colors.background;
        _drawGlyph(canvas, s, cell, cur.x, cur.y, bg);
    }
  }

  void dispose() {
    invalidate();
    _paragraphs.clear();
  }
}
