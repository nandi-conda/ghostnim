/// Finding plain-text URLs in a line of terminal cells, for Ctrl+click.
///
/// OSC 8 hyperlinks come straight from libghostty; this covers the URLs
/// programs just print. Offsets are UTF-16 indexes into the line's text.
library;

const _schemes = [
  'https://', 'http://', 'ftp://', 'file://', 'ssh://', 'git://', 'mailto:', 'www.', //
];

/// Characters that end a URL even without whitespace.
const _stopChars = '"\'`<>{}|\\^\x7F';

/// Punctuation that usually belongs to the sentence, not the URL.
const _trailingPunct = '.,:;!?';

bool _isUrlChar(String c) => c.codeUnitAt(0) > 0x20 && !_stopChars.contains(c);

bool _isAlnum(String c) => RegExp(r'^[A-Za-z0-9]$').hasMatch(c);

int _count(String s, String c) => c.allMatches(s).length;

/// Drop trailing sentence punctuation and closing brackets that have no
/// opening partner inside the URL, e.g. "(see https://x.org/a)."
int _trimUrl(String s, int a, int b) {
  while (b > a) {
    final c = s[b - 1];
    if (_trailingPunct.contains(c)) {
      b--;
    } else if (c == ')' || c == ']') {
      final open = c == ')' ? '(' : '[';
      final span = s.substring(a, b);
      if (_count(span, open) < _count(span, c)) {
        b--;
      } else {
        break;
      }
    } else {
      break;
    }
  }
  return b;
}

String _schemeAt(String s, int i) {
  for (final sc in _schemes) {
    if (i + sc.length <= s.length && s.substring(i, i + sc.length).toLowerCase() == sc) return sc;
  }
  return '';
}

/// The range [a, b) of the URL in [text] that covers index [target], or
/// (-1, -1) if there's none.
(int, int) urlSpan(String text, int target) {
  var i = 0;
  while (i < text.length) {
    final sc = (i == 0 || !_isAlnum(text[i - 1])) ? _schemeAt(text, i) : '';
    if (sc.isEmpty) {
      i++;
      continue;
    }
    var e = i;
    while (e < text.length && _isUrlChar(text[e])) {
      e++;
    }
    e = _trimUrl(text, i, e);
    if (e - i > sc.length && target >= i && target < e) return (i, e);
    i = e > i + 1 ? e : i + 1;
  }
  return (-1, -1);
}

/// The URL covering cell [col] of a line, or "". Each entry of [cells] is
/// that cell's text: " " for a blank cell and "" for the right half of a
/// wide character.
String urlAt(List<String> cells, int col) {
  if (col < 0 || col >= cells.length) return '';
  final text = StringBuffer();
  var target = -1;
  for (var i = 0; i < cells.length; i++) {
    if (i == col) target = text.length;
    text.write(cells[i]);
  }
  if (cells[col].isEmpty) target = target > 0 ? target - 1 : 0; // right half of a wide char
  final s = text.toString();
  final (a, b) = urlSpan(s, target);
  if (a < 0) return '';
  final url = s.substring(a, b);
  return url.toLowerCase().startsWith('www.') ? 'https://$url' : url;
}
