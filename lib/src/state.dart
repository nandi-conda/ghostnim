/// What ghostnim remembers between runs, under `$XDG_STATE_HOME/ghostnim`
/// (`~/.local/state/ghostnim`): the recent folders all windows share,
/// whether the folder strip and file pane are shown, and the pane's width.
/// Also the helpers that hand things to the desktop.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'paths.dart';

const keptRecentDirs = 50; // history kept, shared by all tabs
const shownRecentDirs = 12; // folders offered in the strip (as many as fit)

String stateDir() {
  final xdg = Platform.environment['XDG_STATE_HOME'] ?? '';
  return p.join(p.isAbsolute(xdg) ? xdg : p.join(homeDir(), '.local', 'state'), 'ghostnim');
}

void _warn(String what, Object e) {
  final msg = e is FileSystemException ? e.message : '$e';
  stderr.writeln('ghostnim: can\'t save $what: $msg');
}

// --- recent folders --------------------------------------------------------------

class RecentDir {
  final String path;
  int visits; // times a tab has gone there
  int lastVisit; // when the latest was, in Unix milliseconds
  RecentDir(this.path, this.visits, this.lastVisit);
}

/// Shared by all ghostnim windows. One folder per line, most used first:
/// "VISITS LAST-VISIT-MS PATH".
String recentDirsFile() => p.join(stateDir(), 'recent-folders');

/// Exists while the recent-folders strip is turned off.
String folderBarHiddenFlag() => p.join(stateDir(), 'folder-bar-hidden');

List<RecentDir> _readRecentDirs() {
  final out = <RecentDir>[];
  try {
    for (final line in File(recentDirsFile()).readAsLinesSync()) {
      final a = line.indexOf(' ');
      final b = a < 0 ? -1 : line.indexOf(' ', a + 1);
      if (b < 0) continue;
      final path = line.substring(b + 1);
      final visits = int.tryParse(line.substring(0, a));
      final last = int.tryParse(line.substring(a + 1, b));
      if (!p.isAbsolute(path) || visits == null || last == null) continue;
      out.add(RecentDir(path, visits, last));
    }
  } on FileSystemException {
    // none yet
  }
  return out;
}

void _sortAndTrim(List<RecentDir> dirs) {
  dirs.sort((a, b) {
    final r = b.visits.compareTo(a.visits);
    return r != 0 ? r : b.lastVisit.compareTo(a.lastVisit);
  });
  if (dirs.length > keptRecentDirs) {
    // Make room by dropping the least recently visited, not the least used,
    // so new folders get a chance to build up visits.
    final byAge = [...dirs]..sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
    final cutoff = byAge[keptRecentDirs - 1].lastVisit;
    dirs.removeWhere((d) => d.lastVisit < cutoff);
  }
}

class RecentDirs {
  List<RecentDir> dirs = [];
  final List<(String, int)> _newVisits = []; // not yet in the shared file
  final List<String> _gone = []; // folders found missing, to drop from it
  String _stamp = '';

  static String _fileStamp() {
    try {
      final s = File(recentDirsFile()).statSync();
      return s.type == FileSystemEntityType.notFound ? '' : '${s.modified.microsecondsSinceEpoch}';
    } on FileSystemException {
      return '';
    }
  }

  void visit(String dir) => _newVisits.add((dir, DateTime.now().millisecondsSinceEpoch));

  void gone(String dir) => _gone.add(dir);

  /// Merge this window's new visits (and folders found gone) into the shared
  /// file, and pick up what other windows added to it. True if the list
  /// changed.
  bool sync() {
    final pending = _newVisits.isNotEmpty || _gone.isNotEmpty;
    if (!pending && _fileStamp() == _stamp) return false;
    RandomAccessFile? lock;
    if (pending) {
      try {
        Directory(stateDir()).createSync(recursive: true);
        lock = File('${recentDirsFile()}.lock').openSync(mode: FileMode.append);
        lock.lockSync(FileLock.blockingExclusive);
      } on FileSystemException {
        lock = null;
      }
    }
    final list = _readRecentDirs();
    for (final (path, at) in _newVisits) {
      final i = list.indexWhere((d) => d.path == path);
      if (i >= 0) {
        list[i].visits++;
        if (at > list[i].lastVisit) list[i].lastVisit = at;
      } else {
        list.add(RecentDir(path, 1, at));
      }
    }
    for (final g in _gone) {
      list.removeWhere((d) => d.path == g);
    }
    _sortAndTrim(list);
    if (pending) {
      _newVisits.clear();
      _gone.clear();
      final text = StringBuffer();
      for (final d in list) {
        text.writeln('${d.visits} ${d.lastVisit} ${d.path}');
      }
      final tmp = '${recentDirsFile()}.$pid';
      try {
        File(tmp).writeAsStringSync(text.toString());
        File(tmp).renameSync(recentDirsFile());
      } on FileSystemException catch (e) {
        _warn('the recent folders', e);
      }
      try {
        lock?.unlockSync();
        lock?.closeSync();
      } on FileSystemException {
        // already gone
      }
    }
    _stamp = _fileStamp();
    dirs = list;
    return true;
  }
}

// --- file pane and folder strip ------------------------------------------------------

/// "on WIDTH" or "off WIDTH", plus "hidden" when it lists dotfiles.
String _filePaneFile() => p.join(stateDir(), 'file-pane');

({bool on, double width, bool hidden}) loadPaneState(double defaultWidth) {
  try {
    final parts = File(_filePaneFile()).readAsStringSync().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final w = double.tryParse(parts[1]);
      return (
        on: parts[0] == 'on',
        width: w == null || w < 1 ? defaultWidth : w,
        hidden: parts.skip(2).contains('hidden'),
      );
    }
  } on FileSystemException {
    // defaults
  }
  return (on: false, width: defaultWidth, hidden: false);
}

void savePaneState({required bool on, required double width, required bool hidden}) {
  try {
    Directory(stateDir()).createSync(recursive: true);
    File(_filePaneFile())
        .writeAsStringSync('${on ? 'on' : 'off'} ${width.round()}${hidden ? ' hidden' : ''}\n');
  } on FileSystemException catch (e) {
    _warn('the file manager setting', e);
  }
}

bool folderBarShown() => !File(folderBarHiddenFlag()).existsSync();

void saveFolderBar(bool on) {
  try {
    if (on) {
      final f = File(folderBarHiddenFlag());
      if (f.existsSync()) f.deleteSync();
    } else {
      Directory(stateDir()).createSync(recursive: true);
      File(folderBarHiddenFlag()).writeAsStringSync('');
    }
  } on FileSystemException catch (e) {
    _warn('the folder bar setting', e);
  }
}

// --- the desktop ---------------------------------------------------------------------

bool _onPath(String exe) {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isNotEmpty && File(p.join(dir, exe)).existsSync()) return true;
  }
  return false;
}

bool get canXdgOpen => _onPath('xdg-open');

/// Hand a file or URL to the desktop (xdg-open).
void openExternal(String target) {
  if (!canXdgOpen) {
    stderr.writeln("ghostnim: can't open $target: xdg-open not found");
    return;
  }
  Process.start('xdg-open', [target], mode: ProcessStartMode.detached);
}

String defaultShell() {
  final sh = Platform.environment['SHELL'] ?? '';
  if (sh.isNotEmpty) return sh;
  try {
    final uid = Process.runSync('id', ['-un']).stdout.toString().trim();
    for (final line in File('/etc/passwd').readAsLinesSync()) {
      final f = line.split(':');
      if (f.length >= 7 && f[0] == uid && f[6].isNotEmpty) return f[6];
    }
  } catch (_) {
    // fall through
  }
  return '/bin/sh';
}

String? _shellEditorCache;

/// $VISUAL or $EDITOR as the user's interactive shell sets them. Started from
/// a desktop launcher, ghostnim doesn't inherit what ~/.bashrc and friends
/// export, so ask the shell (once).
String shellEditor() {
  if (_shellEditorCache != null) return _shellEditorCache!;
  var visual = '', editor = '';
  try {
    final args = ['-ic', 'env'];
    final r = _onPath('timeout')
        ? Process.runSync('timeout', ['3', defaultShell(), ...args], stdoutEncoding: systemEncoding)
        : Process.runSync(defaultShell(), args);
    for (final line in r.stdout.toString().split('\n')) {
      if (line.startsWith('VISUAL=')) visual = line.substring(7);
      if (line.startsWith('EDITOR=')) editor = line.substring(7);
    }
  } catch (_) {
    // no shell to ask
  }
  return _shellEditorCache = visual.isNotEmpty ? visual : editor;
}

/// The command that runs $VISUAL or $EDITOR (from our environment, else the
/// user's shell, else [fallback]) on [path], or null when there's nothing to
/// run. Through sh so an $EDITOR with arguments ("code --wait") works; if
/// the editor fails, the tab stays open to show why instead of vanishing.
List<String>? editorCommand(String path, {String fallback = ''}) {
  var editor = Platform.environment['VISUAL'] ?? '';
  if (editor.isEmpty) editor = Platform.environment['EDITOR'] ?? '';
  if (editor.isEmpty) editor = shellEditor();
  if (editor.isEmpty) editor = fallback;
  if (editor.isEmpty) return null;
  const script =
      r'''eval "$0 \"\$1\"" || { s=$?; printf '\n[%s exited with status %d; press Enter]' "$0" "$s"; read _; exit "$s"; }''';
  return ['/bin/sh', '-c', script, editor, path];
}
