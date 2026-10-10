/// The command line, and how it combines with the config file.
library;

import 'dart:io';

import 'config.dart';
import 'keybinds.dart';
import 'paths.dart';
import 'state.dart';

const version = '0.2.0';

const usage = '''
ghostnim $version - a Flutter terminal powered by libghostty-vt

Usage: ghostnim [options] [-e command [args...]]

Options:
  -c, --config FILE      config file  [\$XDG_CONFIG_HOME/ghostnim/config.kdl]
  -f, --font NAME|PATH   font family or font file              [Monaspace Neon Frozen]
  -s, --size N           font size in points                      [14]
      --no-font-shaping  draw characters one by one: no ligatures or
                         contextual alternates
      --cols N           initial columns                          [100]
      --rows N           initial rows                             [30]
      --scrollback N     scrollback lines                         [10000]
  -d, --working-directory DIR  start the first tab in DIR  [current directory]
      --no-inherit-directory   start new tabs in the working directory too,
                         not in the current tab's directory
  -e, --exec CMD ...     run CMD instead of \$SHELL (must be last)
  -h, --help             show this help

Keys (defaults; change them in the config file's keybinds block):
  Ctrl+Shift+T / Ctrl+Shift+W   new tab / close tab
  Ctrl+Tab / Ctrl+Shift+Tab     next / previous tab (also Ctrl+PageDown/PageUp)
  Ctrl+Shift+C / Ctrl+Shift+V   copy selection / paste
  Shift+PageUp / Shift+PageDown scroll back / forward
  Ctrl+= / Ctrl+- / Ctrl+0      bigger / smaller / reset font (also Ctrl++)
  Ctrl+,                        open the config file in \$VISUAL/\$EDITOR
  Ctrl+Shift+E                  show and focus / hide the file manager
  Ctrl+Shift+O                  open the current folder in \$VISUAL/\$EDITOR
  Ctrl+Shift+,                  reload the config file (also automatic on save)

Every option except --config and --help can also be set in the config file
(KDL): `font "Iosevka"`, `font-size 13`, `font-shaping #false`, `cols 120`,
`rows 36`, `scrollback 50000`, `command "fish" "--login"`,
`working-directory "~/code"`, `inherit-directory #false`,
`copy-on-select #false`, plus `colors { ... }` and `keybinds { ... }` blocks.
The command line wins.
''';

/// What the command line set. It wins over the config file, on every reload
/// too; empty/zero fields were not given.
class Cli {
  String configPath = '', font = '', workingDirectory = '';
  int size = 0, cols = 0, rows = 0;
  int scrollback = -1; // -1 when not given
  List<String> command = [];
  bool noInheritDirectory = false;
  bool noFontShaping = false;
}

class Options {
  String font;
  int size;
  int cols, rows;
  int scrollback;
  List<String> command;
  String workingDirectory;
  bool inheritDirectory;
  bool fontShaping;
  bool copyOnSelect;
  Colors colors;
  Keybinds keybinds;
  Options({
    required this.font,
    required this.size,
    required this.cols,
    required this.rows,
    required this.scrollback,
    required this.command,
    required this.workingDirectory,
    required this.inheritDirectory,
    required this.fontShaping,
    required this.copyOnSelect,
    required this.colors,
    required this.keybinds,
  });
}

Never _quit(String msg, [int code = 2]) {
  stderr.writeln(msg);
  exit(code);
}

Cli parseCli(List<String> args) {
  final cli = Cli();
  var i = 0;
  String need() {
    i++;
    if (i >= args.length) _quit('ghostnim: missing value for ${args[i - 1]}');
    return args[i];
  }

  int needInt() {
    final s = need();
    return int.tryParse(s) ?? _quit('ghostnim: not a number for ${args[i - 1]}: $s');
  }

  while (i < args.length) {
    final a = args[i];
    switch (a) {
      case '-h' || '--help':
        stdout.write(usage);
        exit(0);
      case '-c' || '--config':
        cli.configPath = need();
      case '-f' || '--font':
        cli.font = need();
      case '-s' || '--size':
        cli.size = needInt();
      case '--cols':
        cli.cols = needInt();
      case '--rows':
        cli.rows = needInt();
      case '--scrollback':
        cli.scrollback = needInt();
      case '-d' || '--working-directory':
        cli.workingDirectory = expandTilde(need());
        if (!dirExists(cli.workingDirectory)) {
          _quit('ghostnim: no such directory: ${cli.workingDirectory}');
        }
      case '--no-inherit-directory':
        cli.noInheritDirectory = true;
      case '--no-font-shaping':
        cli.noFontShaping = true;
      case '-e' || '--exec':
        cli.command = args.sublist(i + 1);
        return cli;
      default:
        _quit('ghostnim: unknown option $a\n\n$usage');
    }
    i++;
  }
  return cli;
}

/// Desktop launchers start programs in $HOME or /. Anywhere else (a file
/// manager's "Open Terminal Here", a shell in some project) was chosen on
/// purpose, so the first tab should start there.
bool launchedFromDesktop() {
  try {
    final cwd = Directory.current.path;
    if (cwd == '/') return true;
    return FileSystemEntity.identicalSync(cwd, homeDir());
  } on FileSystemException {
    return true;
  }
}

/// The config file's settings with the command line's on top. The config's
/// working-directory only replaces the launch directory when that's just the
/// desktop's default.
Options mergeOptions(Config cfg, Cli cli) {
  final command = cli.command.isNotEmpty ? cli.command : cfg.command;
  return Options(
    font: cli.font.isNotEmpty ? cli.font : cfg.font,
    size: cli.size > 0 ? cli.size : cfg.size,
    cols: cli.cols > 0 ? cli.cols : cfg.cols,
    rows: cli.rows > 0 ? cli.rows : cfg.rows,
    scrollback: cli.scrollback >= 0 ? cli.scrollback : cfg.scrollback,
    command: command.isNotEmpty ? command : [defaultShell()],
    workingDirectory: cli.workingDirectory.isNotEmpty
        ? cli.workingDirectory
        : launchedFromDesktop()
            ? cfg.workingDirectory
            : '',
    inheritDirectory: cfg.inheritDirectory && !cli.noInheritDirectory,
    fontShaping: cfg.fontShaping && !cli.noFontShaping,
    copyOnSelect: cfg.copyOnSelect,
    colors: cfg.colors,
    keybinds: cfg.keybinds,
  );
}
