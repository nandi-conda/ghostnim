/// A small, dependency-free KDL parser (https://kdl.dev), enough for config
/// files. It reads KDL v2 and also accepts v1's bare `true`/`false`/`null`.
///
/// Supported: nodes, arguments, properties, children blocks, `;` and newline
/// terminators, `\` line continuations, `//`, `/* */` (nested) and `/-`
/// comments, bare identifiers, quoted strings with escapes, raw strings
/// (`#"..."#`), multi-line strings (`"""`), decimal/hex/octal/binary numbers
/// with `_` separators, `#inf`/`#-inf`/`#nan`, and `(type)` annotations
/// (parsed and kept but not interpreted).
library;

enum KdlKind { string, integer, float, boolean, nul }

class KdlVal {
  final KdlKind kind;
  final String str;
  final int num;
  final double fnum;
  final bool bval;
  String tag = '';

  KdlVal.string(this.str)
      : kind = KdlKind.string,
        num = 0,
        fnum = 0,
        bval = false;
  KdlVal.integer(this.num)
      : kind = KdlKind.integer,
        str = '',
        fnum = 0,
        bval = false;
  KdlVal.float(this.fnum)
      : kind = KdlKind.float,
        str = '',
        num = 0,
        bval = false;
  KdlVal.boolean(this.bval)
      : kind = KdlKind.boolean,
        str = '',
        num = 0,
        fnum = 0;
  KdlVal.nul()
      : kind = KdlKind.nul,
        str = '',
        num = 0,
        fnum = 0,
        bval = false;

  @override
  String toString() => switch (kind) {
        KdlKind.string => _escape(str),
        KdlKind.integer => '$num',
        KdlKind.float => '$fnum',
        KdlKind.boolean => bval ? '#true' : '#false',
        KdlKind.nul => '#null',
      };
}

String _escape(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    switch (r) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        b.writeCharCode(r);
    }
  }
  b.write('"');
  return b.toString();
}

class KdlNode {
  String tag = '';
  String name = '';
  final List<KdlVal> args = [];

  /// In source order; later keys win.
  final List<(String, KdlVal)> props = [];
  final List<KdlNode> children = [];
  int line = 0;

  /// The last value given for property [key], if any.
  KdlVal? prop(String key) {
    for (var i = props.length - 1; i >= 0; i--) {
      if (props[i].$1 == key) return props[i].$2;
    }
    return null;
  }
}

class KdlError implements Exception {
  final String message;
  final int line;
  KdlError(this.message, this.line);
  @override
  String toString() => 'line $line: $message';
}

const _spaces = [
  ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', //
  ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　',
];

const _nonIdent = r'\/(){};[]"#= ' '\t\r\n\f';

class _Parser {
  final String s;
  int i = 0;
  int line = 1;
  _Parser(this.s);

  Never fail(String msg) => throw KdlError(msg, line);

  bool get atEnd => i >= s.length;
  String peek([int o = 0]) => i + o < s.length ? s[i + o] : '\x00';
  bool startsWith(String t) => s.startsWith(t, i);

  /// Newlines: CRLF, CR, LF, NEL, FF, LS, PS. Returns the length or 0.
  int newlineLen() {
    final c = peek();
    if (c == '\r') return peek(1) == '\n' ? 2 : 1;
    if (c == '\n' || c == '\f' || c == '\u0085' || c == ' ' || c == ' ') return 1;
    return 0;
  }

  /// Length of the unicode whitespace at the cursor, or 0.
  int isSpace() {
    final c = peek();
    if (c == ' ' || c == '\t' || c == '﻿') return 1;
    return _spaces.contains(c) ? 1 : 0;
  }

  void skipBlockComment() {
    i += 2;
    var depth = 1;
    while (depth > 0) {
      if (atEnd) fail('unterminated /* comment');
      if (startsWith('/*')) {
        depth++;
        i += 2;
      } else if (startsWith('*/')) {
        depth--;
        i += 2;
      } else {
        final n = newlineLen();
        if (n > 0) {
          i += n;
          line++;
        } else {
          i++;
        }
      }
    }
  }

  void skipLineComment() {
    while (!atEnd && newlineLen() == 0) {
      i++;
    }
  }

  /// Whitespace and block comments on the current line.
  void skipWs() {
    while (!atEnd) {
      final n = isSpace();
      if (n > 0) {
        i += n;
      } else if (startsWith('/*')) {
        skipBlockComment();
      } else {
        break;
      }
    }
  }

  /// Whitespace between a node's entries, including `\` line continuations.
  void skipNodeSpace() {
    while (true) {
      skipWs();
      if (peek() == r'\') {
        i++;
        skipWs();
        if (startsWith('//')) skipLineComment();
        final n = newlineLen();
        if (n > 0) {
          i += n;
          line++;
        } else if (!atEnd) {
          fail(r'expected newline after \');
        }
      } else {
        break;
      }
    }
  }

  /// Whitespace, newlines and comments between nodes.
  void skipLineSpace() {
    while (!atEnd) {
      skipWs();
      if (startsWith('//')) skipLineComment();
      final n = newlineLen();
      if (n > 0) {
        i += n;
        line++;
      } else {
        break;
      }
    }
  }

  bool atIdentChar() =>
      !atEnd &&
      !_nonIdent.contains(peek()) &&
      peek() != '\x00' &&
      isSpace() == 0 &&
      newlineLen() == 0;

  String parseBareIdent() {
    final start = i;
    while (atIdentChar()) {
      i++;
    }
    final r = s.substring(start, i);
    if (r.isEmpty) fail('expected identifier');
    return r;
  }

  /// Multi-line string rules: drop the first and last line; strip the last
  /// line's indentation (which must be whitespace only) from every line.
  String dedent(String body) {
    final lines = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    if (lines.length < 2 || lines.first.trim().isNotEmpty) {
      fail('multi-line string must start with a newline after """');
    }
    final indent = lines.last;
    if (indent.trim().isNotEmpty) {
      fail('multi-line string\'s closing """ must be on its own line');
    }
    final out = <String>[];
    for (final l in lines.sublist(1, lines.length - 1)) {
      if (l.trim().isEmpty) {
        out.add('');
      } else if (l.startsWith(indent)) {
        out.add(l.substring(indent.length));
      } else {
        fail('multi-line string line is less indented than its closing """');
      }
    }
    return out.join('\n');
  }

  String unescape(String s) {
    final b = StringBuffer();
    var j = 0;
    while (j < s.length) {
      final c = s[j];
      if (c != r'\') {
        b.write(c);
        j++;
        continue;
      }
      j++;
      if (j >= s.length) fail('bad escape at end of string');
      switch (s[j]) {
        case 'n':
          b.write('\n');
        case 'r':
          b.write('\r');
        case 't':
          b.write('\t');
        case r'\':
          b.write(r'\');
        case '"':
          b.write('"');
        case 'b':
          b.write('\b');
        case 'f':
          b.write('\f');
        case 's':
          b.write(' ');
        case 'u':
          if (j + 1 >= s.length || s[j + 1] != '{') fail(r'bad \u escape');
          final close = s.indexOf('}', j);
          if (close < 0) fail(r'bad \u escape');
          final hex = s.substring(j + 2, close);
          final v = int.tryParse(hex, radix: 16);
          if (hex.isEmpty || hex.length > 6 || v == null) fail(r'bad \u escape');
          b.writeCharCode(v);
          j = close;
        case ' ' || '\t' || '\n' || '\r' || '\f':
          // Escaped whitespace: skip it all.
          while (j < s.length && ' \t\n\r\f'.contains(s[j])) {
            j++;
          }
          continue;
        default:
          fail('unknown escape \\${s[j]}');
      }
      j++;
    }
    return b.toString();
  }

  /// At the opening quote(s). [hashes] > 0 means a raw string.
  String parseQuoted(int hashes) {
    final raw = hashes > 0;
    final multi = startsWith('"""');
    i += multi ? 3 : 1;
    final closer = (multi ? '"""' : '"') + '#' * hashes;
    final start = i;
    while (true) {
      if (atEnd) fail('unterminated string');
      if (!raw && peek() == r'\') {
        i += 2;
        continue;
      }
      if (startsWith(closer)) break;
      final n = newlineLen();
      if (n > 0) {
        if (!multi) fail('newline in single-line string (use """)');
        i += n;
        line++;
      } else {
        i++;
      }
    }
    final body = s.substring(start, i);
    i += closer.length;
    if (multi) return raw ? dedent(body) : unescape(dedent(body));
    return raw ? body : unescape(body);
  }

  /// A quoted, raw or bare-identifier string.
  String parseString() {
    if (peek() == '"') return parseQuoted(0);
    if (peek() == '#') {
      var h = 0;
      while (peek(h) == '#') {
        h++;
      }
      if (peek(h) == '"') {
        i += h;
        return parseQuoted(h);
      }
      fail('expected string');
    }
    final r = parseBareIdent();
    if (const ['true', 'false', 'null', 'inf', '-inf', 'nan'].contains(r)) {
      fail("'$r' must be quoted to use it as a string");
    }
    return r;
  }

  KdlVal parseNumber(String word) {
    var w = word.replaceAll('_', '');
    var neg = false;
    if (w.isNotEmpty && (w[0] == '+' || w[0] == '-')) {
      neg = w[0] == '-';
      w = w.substring(1);
    }
    if (w.length > 2 && w[0] == '0' && 'xob'.contains(w[1])) {
      final radix = switch (w[1]) { 'x' => 16, 'o' => 8, _ => 2 };
      final n = int.tryParse(w.substring(2), radix: radix);
      if (n == null) fail("bad number '$word'");
      return KdlVal.integer(neg ? -n : n);
    }
    if (w.contains(RegExp('[.eE]'))) {
      final f = double.tryParse(w);
      if (f == null) fail("bad number '$word'");
      return KdlVal.float(neg ? -f : f);
    }
    final n = int.tryParse(w);
    if (n == null) fail("bad number '$word'");
    return KdlVal.integer(neg ? -n : n);
  }

  String parseTag() {
    if (peek() != '(') return '';
    i++;
    skipWs();
    final r = parseString();
    skipWs();
    if (peek() != ')') fail("expected ')'");
    i++;
    skipWs();
    return r;
  }

  KdlVal parseValue() {
    final tag = parseTag();
    final c = peek();
    KdlVal r;
    if (c == '"' || (c == '#' && (peek(1) == '"' || peek(1) == '#'))) {
      r = KdlVal.string(parseString());
    } else if (c == '#') {
      i++;
      final w = parseBareIdent();
      r = switch (w) {
        'true' => KdlVal.boolean(true),
        'false' => KdlVal.boolean(false),
        'null' => KdlVal.nul(),
        'inf' => KdlVal.float(double.infinity),
        '-inf' => KdlVal.float(double.negativeInfinity),
        'nan' => KdlVal.float(double.nan),
        _ => fail('unknown keyword #$w'),
      };
    } else {
      final w = parseBareIdent();
      final digit = RegExp('[0-9]');
      if (w[0].contains(digit) ||
          (w.length > 1 && (w[0] == '+' || w[0] == '-') && w[1].contains(digit))) {
        r = parseNumber(w);
      } else {
        r = switch (w) {
          'true' => KdlVal.boolean(true), // KDL v1
          'false' => KdlVal.boolean(false),
          'null' => KdlVal.nul(),
          _ => KdlVal.string(w),
        };
      }
    }
    r.tag = tag;
    return r;
  }

  bool atNodeEnd() =>
      atEnd || peek() == ';' || peek() == '}' || newlineLen() > 0 || startsWith('//');

  KdlNode parseNode() {
    final n = KdlNode()..line = line;
    n.tag = parseTag();
    n.name = parseString();
    while (true) {
      final before = i;
      skipNodeSpace();
      if (atNodeEnd()) break;
      if (i == before && peek() != '{' && !startsWith('/-')) {
        fail('expected whitespace between node entries');
      }
      var skip = false;
      if (startsWith('/-')) {
        i += 2;
        skipNodeSpace();
        skip = true;
      }
      if (peek() == '{') {
        i++;
        final kids = parseNodes(true);
        if (peek() != '}') fail("expected '}'");
        i++;
        if (!skip) n.children.addAll(kids);
        continue;
      }
      // A property is `key=value`, where key is any string form.
      final save = i;
      final saveLine = line;
      var isProp = false;
      if (peek() != '(') {
        try {
          parseString();
          skipWs();
          isProp = peek() == '=';
        } on KdlError {
          // not a property
        }
      }
      i = save;
      line = saveLine;
      if (isProp) {
        final key = parseString();
        skipWs();
        i++; // '='
        skipWs();
        final v = parseValue();
        if (!skip) n.props.add((key, v));
      } else {
        final v = parseValue();
        if (!skip) n.args.add(v);
      }
    }
    if (peek() == ';') i++;
    return n;
  }

  List<KdlNode> parseNodes(bool nested) {
    final out = <KdlNode>[];
    while (true) {
      skipLineSpace();
      if (atEnd) {
        if (nested) fail("unterminated '{'");
        break;
      }
      if (peek() == '}') {
        if (!nested) fail("unexpected '}'");
        break;
      }
      if (peek() == ';') {
        i++;
        continue;
      }
      var skip = false;
      if (startsWith('/-')) {
        i += 2;
        skipNodeSpace();
        skip = true;
      }
      final n = parseNode();
      if (!skip) out.add(n);
    }
    return out;
  }
}

/// Parse a KDL document. Throws [KdlError] on malformed input.
List<KdlNode> parseKdl(String s) {
  final p = _Parser(s);
  if (s.startsWith('﻿')) p.i = 1;
  return p.parseNodes(false);
}
