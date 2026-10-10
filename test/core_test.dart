import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghostnim/src/config.dart';
import 'package:ghostnim/src/kdl.dart';
import 'package:ghostnim/src/keybinds.dart';
import 'package:ghostnim/src/links.dart';
import 'package:ghostnim/src/paths.dart';
import 'package:ghostnim/src/wordsel.dart';
import 'package:path/path.dart' as p;

List<String> cellsOf(String s) => s.split('');

String word(String s, int col) {
  final (a, b) = wordAt(cellsOf(s), col);
  return s.substring(a, b + 1);
}

void main() {
  test('urlAt', () {
    expect(urlAt(cellsOf('see https://ghostty.org/docs now'), 8), 'https://ghostty.org/docs');
    expect(urlAt(cellsOf('see https://ghostty.org/docs now'), 2), '');
    expect(urlAt(cellsOf('(https://en.wikipedia.org/wiki/Nim_(lang)).'), 5),
        'https://en.wikipedia.org/wiki/Nim_(lang)');
    expect(urlAt(cellsOf('go to www.nim-lang.org, then'), 10), 'https://www.nim-lang.org');
    expect(urlAt(cellsOf('"http://a.b/c"'), 1), 'http://a.b/c');
    expect(urlAt(cellsOf('https://'), 3), '');
    expect(urlAt(cellsOf('xhttp://a.b'), 5), '');
    expect(urlAt(['h', 't', 't', 'p', ':', '/', '/', 'a', '/', '日', '', 'x'], 10), 'http://a/日x');
  });

  test('wordAt', () {
    expect(word('hello world', 1), 'hello');
    expect(word('hello world', 8), 'world');
    expect(word('vim src/ghostnim/wordsel.nim:12:3', 10), 'src/ghostnim/wordsel.nim:12:3');
    expect(word('see foo.nim.', 5), 'foo.nim');
    expect(word('see foo.nim.', 11), 'foo.nim.');
    expect(word('key: value', 1), 'key');
    expect(word('ls --color=auto -la', 5), '--color=auto');
    expect(word('mail me@example.com, ok', 9), 'me@example.com');
    expect(word('f("arg", 10)', 3), 'arg');
    expect(word('f("arg", 10)', 0), 'f');
    expect(word('a  ====  b', 5), '====');
    expect(word('a    b', 2), '    ');
    expect(word('(see https://en.wikipedia.org/wiki/Nim_(lang)).', 10),
        'https://en.wikipedia.org/wiki/Nim_(lang)');
    expect(word('x = 127.0.0.1:8080;', 6), '127.0.0.1:8080');
    expect(wordAt(['│', ' ', 'c', 'e', 'l', 'l', ' ', '│'], 3), (2, 5));
    expect(wordAt(['│', '│', 'a'], 0), (0, 1));
    expect(wordAt(['a', '日', '', 'b', ' ', 'c'], 2), (0, 3));
    expect(wordAt(['a', '日', '', 'b', ' ', 'c'], 4), (4, 4));
    expect(wordAt(['x', ' ', '日', '', ' '], 1), (1, 1));
    expect(wordAt([' ', '日', '', '本', '', ' '], 3), (1, 4));
    expect(wordAt([' ', '日', '', '本', '', ' '], 2), (1, 4));
  });

  test('pathTarget', () {
    final tmp = Directory.systemTemp.createTempSync('ghostnim-paths-test').path;
    addTearDown(() => Directory(tmp).deleteSync(recursive: true));
    Directory(p.join(tmp, 'src', 'sub')).createSync(recursive: true);
    File(p.join(tmp, 'src', 'foo.nim')).writeAsStringSync('');
    File(p.join(tmp, 'run')).writeAsStringSync('');
    expect(pathTarget('src', tmp), p.join(tmp, 'src'));
    expect(pathTarget('src/', tmp), p.join(tmp, 'src'));
    expect(pathTarget('src/sub', tmp), p.join(tmp, 'src', 'sub'));
    expect(pathTarget('src/foo.nim:12:3', tmp), p.join(tmp, 'src', 'foo.nim'));
    expect(pathTarget('src/foo.nim:12', tmp), p.join(tmp, 'src', 'foo.nim'));
    expect(pathTarget('src/foo.nim:', tmp), p.join(tmp, 'src', 'foo.nim'));
    expect(pathTarget('a/src/foo.nim', tmp), p.join(tmp, 'src', 'foo.nim'));
    expect(pathTarget('b/src', tmp), p.join(tmp, 'src'));
    expect(pathTarget('run*', tmp), p.join(tmp, 'run'));
    expect(pathTarget('..', p.join(tmp, 'src')), tmp);
    expect(pathTarget(p.join(tmp, 'src'), ''), p.join(tmp, 'src'));
    expect(pathTarget('~', tmp), p.normalize(homeDir()));
    expect(pathTarget('nope', tmp), '');
    expect(pathTarget('-la', tmp), '');
    expect(pathTarget('src', ''), '');
    expect(fileUrlPath('file:///tmp/a%20b'), '/tmp/a b');
    expect(fileUrlPath('file://host/etc/'), '/etc/');
    expect(fileUrlPath('https://x.org/'), '');
  });

  test('kdl', () {
    final nodes = parseKdl('''
// comment
font "Iosevka" /* inline */ size=13
cols 120; rows 36
flag #true
colors {
  palette 1 "#ff0000"
}
/- skipped 1
raw #"a "quoted" \\ b"#
''');
    expect(nodes.map((n) => n.name), ['font', 'cols', 'rows', 'flag', 'colors', 'raw']);
    expect(nodes[0].args.single.str, 'Iosevka');
    expect(nodes[0].prop('size')!.num, 13);
    expect(nodes[3].args.single.bval, true);
    expect(nodes[4].children.single.args.map((a) => a.kind), [KdlKind.integer, KdlKind.string]);
    expect(nodes[5].args.single.str, r'a "quoted" \ b');
    expect(() => parseKdl('font "unterminated'), throwsA(isA<KdlError>()));
  });

  test('the shipped config parses', () {
    final text = File('docs/config.kdl').readAsStringSync();
    final cfg = parseConfig(text, 'docs/config.kdl');
    expect(cfg, isNotNull);
    expect(cfg!.size, 14);
    expect(cfg.keybinds, isNotEmpty);
  });

  test('config values and keybinds', () {
    final cfg = parseConfig('''
font-size 11
command "fish" "--login"
font-shaping #false
colors { background "#101010"; palette 2 "#00ff00" }
keybinds { ctrl+shift+n new-tab; ctrl+shift+t none }
''')!;
    expect(cfg.size, 11);
    expect(cfg.command, ['fish', '--login']);
    expect(cfg.fontShaping, false);
    expect(cfg.colors.background, (0x10, 0x10, 0x10));
    expect(cfg.colors.palette, [(2, (0, 255, 0))]);
    expect(cfg.keybinds[parseChord('ctrl+shift+n')]!.action, Action.newTab);
    expect(cfg.keybinds.containsKey(parseChord('ctrl+shift+t')), false);
    expect(parseColor('#abc'), (0xaa, 0xbb, 0xcc));
    expect(parseColor('nope'), isNull);
  });
}
