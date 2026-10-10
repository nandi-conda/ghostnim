/// Double-click selection: which cells of a line make up the "word" under
/// the pointer.
///
/// A URL is taken whole. Otherwise a word runs until whitespace, a quote, a
/// bracket or a separator like `,` `;` `|`, so paths, flags, e-mail
/// addresses, host:port pairs and identifiers each select in one go. Sentence
/// punctuation at the end ("see foo.nim:12.") is left out. Clicking a blank
/// selects the run of blanks, and clicking a separator selects the run of
/// that same character (e.g. a row of `=`).
library;

import 'links.dart';

/// ASCII characters that end a word.
const _boundaryChars = '\t"\'`|;,()[]{}<>';

/// Trailing characters that usually belong to the sentence, not the word.
const _trailingPunct = '.:!?';

enum _Kind { blank, word, boundary }

bool _isBlank(String c) => c.isEmpty || c == ' ';

_Kind _kind(String c) {
  if (_isBlank(c)) return _Kind.blank;
  final r = c.runes.first;
  if (r < 0x80 && c.length == 1) {
    return (_boundaryChars.contains(c) || r < 0x20) ? _Kind.boundary : _Kind.word;
  }
  // Box drawing and block elements are table borders, not text.
  return (r >= 0x2500 && r <= 0x259F) ? _Kind.boundary : _Kind.word;
}

/// The first and last cell (inclusive) of the word covering cell [col] of a
/// line. Each entry of [cells] is that cell's text: " " for a blank cell and
/// "" for the right half of a wide character.
(int, int) wordAt(List<String> cells, int col) {
  if (cells.isEmpty) return (0, 0);
  col = col.clamp(0, cells.length - 1);
  // The right half of a wide character belongs to its left half.
  while (col > 0 && cells[col].isEmpty) {
    col--;
  }

  // A URL, taken whole even across brackets and quotes.
  final text = StringBuffer();
  final starts = List<int>.filled(cells.length, 0);
  for (var i = 0; i < cells.length; i++) {
    starts[i] = text.length;
    text.write(cells[i]);
  }
  final (ua, ub) = urlSpan(text.toString(), starts[col]);
  if (ua >= 0) {
    var a = col;
    while (a > 0 && starts[a] > ua) {
      a--;
    }
    var b = col;
    while (b + 1 < cells.length && starts[b + 1] < ub) {
      b++;
    }
    while (b + 1 < cells.length && cells[b + 1].isEmpty) {
      b++;
    }
    return (a, b);
  }

  // The right half of a wide character goes with its left half.
  int owner(int i) => (i > 0 && cells[i].isEmpty && cells[i - 1].isNotEmpty) ? i - 1 : i;
  final k = _kind(cells[col]);
  bool same(int i) => switch (k) {
        _Kind.blank => owner(i) == i && _isBlank(cells[i]),
        _Kind.word => _kind(cells[owner(i)]) == _Kind.word,
        _Kind.boundary => cells[owner(i)] == cells[col],
      };
  var a = col;
  while (a > 0 && same(a - 1)) {
    a--;
  }
  var b = col;
  while (b + 1 < cells.length && same(b + 1)) {
    b++;
  }

  if (k == _Kind.word) {
    // Drop trailing sentence punctuation, unless that's what was clicked.
    var e = b;
    while (e > a && cells[e].length == 1 && _trailingPunct.contains(cells[e])) {
      e--;
    }
    if (e >= col) b = e;
  }
  return (a, b);
}
