/// The config file, in KDL: `$XDG_CONFIG_HOME/ghostnim/config.kdl` (or
/// `~/.config/ghostnim/config.kdl`). Each setting is a node named after the
/// matching command-line option; the command line wins over the file.
///
///   font "Monaspace Neon"
///   font-size 13
///   font-shaping #false        // no ligatures or contextual alternates
///   cols 120
///   rows 36
///   scrollback 50000
///   command "fish" "--login"
///   working-directory "~/code"
///   inherit-directory #false   // new tabs start in working-directory too
///   copy-on-select #false      // selecting text doesn't copy it
///
/// Colours go in a `colors` block, as "#rrggbb" or "#rgb", and shortcuts in
/// a `keybinds` block; see docs/config.kdl.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'kdl.dart';
import 'keybinds.dart';
import 'paths.dart' show expandTilde, homeDir;

typedef Rgb = (int, int, int);

class Colors {
  /// Unset colours keep libghostty's (or, for selection, ghostnim's) defaults.
  Rgb? foreground, background, cursor;
  Rgb? selectionForeground, selectionBackground;

  /// Palette index overrides, in order.
  final List<(int, Rgb)> palette = [];
}

class Config {
  String font = '';
  int size = 14;
  int cols = 100, rows = 30;
  int scrollback = 10000;
  List<String> command = [];

  /// Where the first tab starts; "" = inherit.
  String workingDirectory = '';

  /// New tabs start in the current tab's directory.
  bool inheritDirectory = true;

  /// Ligatures and contextual alternates.
  bool fontShaping = true;

  /// Selecting text copies it to the clipboard.
  bool copyOnSelect = true;
  Colors colors = Colors();
  Keybinds keybinds = defaultKeybinds();
}

String configPath() {
  final xdg = Platform.environment['XDG_CONFIG_HOME'] ?? '';
  final base = p.isAbsolute(xdg) ? xdg : p.join(homeDir(), '.config');
  return p.join(base, 'ghostnim', 'config.kdl');
}

/// The file to read: [path] if given, else the default location.
String configFile([String path = '']) => path.isNotEmpty ? path : configPath();

void _warn(String path, int line, String msg) {
  stderr.writeln('ghostnim: $path:$line: $msg');
}

/// "#rrggbb" or "#rgb" (the leading # is optional).
Rgb? parseColor(String s) {
  var h = s.startsWith('#') ? s.substring(1) : s;
  if ((h.length != 3 && h.length != 6) || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
  if (h.length == 3) h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
  int at(int i) => int.parse(h.substring(i, i + 2), radix: 16);
  return (at(0), at(2), at(4));
}

class _Skip implements Exception {}

void _parseColors(Colors c, List<KdlNode> nodes, String path) {
  for (final n in nodes) {
    Never bad(String msg) {
      _warn(path, n.line, 'colors: ${n.name}: $msg');
      throw _Skip();
    }

    Rgb? color(KdlVal v) => v.kind == KdlKind.string ? parseColor(v.str) : null;
    const colorHint = 'expected a colour like "#1a1b26", got ';
    try {
      if (n.props.isNotEmpty || n.children.isNotEmpty) bad('unexpected properties or block');
      if (n.name == 'palette') {
        if (n.args.length != 2 || n.args[0].kind != KdlKind.integer) {
          bad('expected an index and a colour, like: palette 1 "#f7768e"');
        }
        final i = n.args[0].num;
        if (i < 0 || i > 255) bad('index must be between 0 and 255');
        final col = color(n.args[1]);
        if (col == null) bad('$colorHint${n.args[1]}');
        c.palette.add((i, col));
        continue;
      }
      if (n.args.length != 1) bad('expected exactly one colour');
      final col = color(n.args[0]);
      if (col == null) bad('$colorHint${n.args[0]}');
      switch (n.name) {
        case 'foreground':
          c.foreground = col;
        case 'background':
          c.background = col;
        case 'cursor':
          c.cursor = col;
        case 'selection-foreground':
          c.selectionForeground = col;
        case 'selection-background':
          c.selectionBackground = col;
        default:
          bad('unknown colour');
      }
    } on _Skip {
      continue;
    }
  }
}

void _parseKeybinds(Keybinds kb, KdlNode n, String path) {
  if (n.args.isNotEmpty) _warn(path, n.line, 'keybinds: expected a { ... } block');
  for (final (k, v) in n.props) {
    if (k == 'clear-defaults' && v.kind == KdlKind.boolean) {
      if (v.bval) kb.clear();
    } else {
      _warn(path, n.line, 'keybinds: unknown property $k');
    }
  }
  for (final b in n.children) {
    Never bad(String msg) {
      _warn(path, b.line, 'keybinds: ${b.name}: $msg');
      throw _Skip();
    }

    try {
      final chord = parseChord(b.name);
      if (chord == null) bad('not a key chord like ctrl+shift+t');
      if (b.args.isEmpty || b.args[0].kind != KdlKind.string) bad('expected an action');
      final action = parseAction(b.args[0].str);
      if (action == null) bad('unknown action ${b.args[0]}');
      final rest = b.args.sublist(1);
      Binding binding;
      switch (action) {
        case Action.gotoTab:
          if (rest.length != 1 || rest[0].kind != KdlKind.integer || rest[0].num < 1) {
            bad('expected a tab number, like: goto-tab 1');
          }
          binding = Binding(action, num: rest[0].num);
        case Action.sendText:
          if (rest.length != 1 || rest[0].kind != KdlKind.string) {
            bad(r'expected the text to send, like: send-text "\n"');
          }
          binding = Binding(action, text: rest[0].str);
        default:
          if (rest.isNotEmpty) bad('$action takes no arguments');
          binding = Binding(action);
      }
      if (action == Action.none) {
        kb.remove(chord);
      } else {
        kb[chord] = binding;
      }
    } on _Skip {
      continue;
    }
  }
}

/// Apply the settings in [text] over the defaults. Problems are reported on
/// stderr and skipped, so a typo never keeps the terminal from starting.
/// Returns null if the file isn't valid KDL at all.
Config? parseConfig(String text, [String path = 'config.kdl']) {
  final result = Config();
  List<KdlNode> nodes;
  try {
    nodes = parseKdl(text);
  } on KdlError catch (e) {
    _warn(path, e.line, '${e.message}; ignoring the config file');
    return null;
  }

  for (final n in nodes) {
    Never bad(String msg) {
      _warn(path, n.line, '${n.name}: $msg');
      throw _Skip();
    }

    KdlVal oneArg() {
      if (n.args.length != 1 || n.props.isNotEmpty || n.children.isNotEmpty) {
        bad('expected exactly one value');
      }
      return n.args[0];
    }

    String strArg() {
      final v = oneArg();
      if (v.kind != KdlKind.string) bad('expected a string, got $v');
      return v.str;
    }

    int intArg(int lo, int hi) {
      final v = oneArg();
      if (v.kind != KdlKind.integer) bad('expected a whole number, got $v');
      if (v.num < lo || v.num > hi) bad('must be between $lo and $hi');
      return v.num;
    }

    bool boolArg() {
      final v = oneArg();
      if (v.kind != KdlKind.boolean) bad('expected #true or #false, got $v');
      return v.bval;
    }

    try {
      switch (n.name) {
        case 'font':
          result.font = strArg();
        case 'font-size':
          result.size = intArg(4, 200);
        case 'font-shaping':
          result.fontShaping = boolArg();
        case 'cols':
          result.cols = intArg(10, 1000);
        case 'rows':
          result.rows = intArg(2, 1000);
        case 'scrollback':
          result.scrollback = intArg(0, 10000000);
        case 'command':
          if (n.args.isEmpty || n.props.isNotEmpty || n.children.isNotEmpty) {
            bad('expected the program and its arguments');
          }
          if (n.args.any((a) => a.kind != KdlKind.string)) bad('expected strings');
          result.command = [for (final a in n.args) a.str];
        case 'working-directory':
          final dir = expandTilde(strArg());
          if (!Directory(dir).existsSync()) bad('no such directory: $dir');
          result.workingDirectory = dir;
        case 'inherit-directory':
          result.inheritDirectory = boolArg();
        case 'copy-on-select':
          result.copyOnSelect = boolArg();
        case 'keybinds':
          _parseKeybinds(result.keybinds, n, path);
        case 'colors':
          if (n.args.isNotEmpty || n.props.isNotEmpty) bad('expected a { ... } block of colours');
          _parseColors(result.colors, n.children, path);
        default:
          bad('unknown setting');
      }
    } on _Skip {
      continue;
    }
  }
  return result;
}

/// Read the config file at [path], or the default location. A missing file
/// at the default location is fine; a missing explicit one is an error.
Config loadConfig([String path = '']) {
  final f = configFile(path);
  if (!File(f).existsSync()) {
    if (path.isNotEmpty) {
      stderr.writeln('ghostnim: config file not found: $path');
      exit(2);
    }
    return Config();
  }
  try {
    return parseConfig(File(f).readAsStringSync(), f) ?? Config();
  } on FileSystemException catch (e) {
    _warn(f, 0, e.message);
    return Config();
  }
}

/// Like loadConfig, for a reload: null if the file can't be read or isn't
/// valid KDL, so a half-saved file doesn't reset everything to defaults. A
/// deleted file means the defaults.
Config? reloadConfig([String path = '']) {
  final f = configFile(path);
  if (!File(f).existsSync()) return Config();
  try {
    return parseConfig(File(f).readAsStringSync(), f);
  } on FileSystemException catch (e) {
    _warn(f, 0, e.message);
    return null;
  }
}

/// Create [path] from the commented defaults if it doesn't exist. False if it
/// couldn't be created.
bool ensureConfigFile(String path, String defaultText) {
  if (File(path).existsSync()) return true;
  try {
    Directory(p.dirname(path)).createSync(recursive: true);
    File(path).writeAsStringSync(defaultText);
    return true;
  } on FileSystemException catch (e) {
    _warn(path, 0, 'could not create: ${e.message}');
    return false;
  }
}

/// Cheap change detection for the config file.
String configStamp(String path) {
  try {
    final s = File(path).statSync();
    if (s.type == FileSystemEntityType.notFound) return '';
    return '${s.modified.millisecondsSinceEpoch}:${s.size}';
  } on FileSystemException {
    return '';
  }
}
