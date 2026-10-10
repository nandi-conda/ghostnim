/// Finding file and directory paths in terminal text, for Ctrl+click, plus
/// small path helpers.
///
/// The word under the pointer (see wordsel) counts as a path when it names
/// something that exists, relative to the tab's working directory. A few
/// decorations programs add are looked through: `:line:col` after a file name
/// (compilers, grep -n), `a/` and `b/` in git diffs, and the `*` / `@` that
/// `ls -F` puts after executables and symlinks.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

String homeDir() => Platform.environment['HOME'] ?? '/';

String expandTilde(String path) {
  if (path == '~') return homeDir();
  if (path.startsWith('~/')) return p.join(homeDir(), path.substring(2));
  return path;
}

bool dirExists(String path) => path.isNotEmpty && Directory(path).existsSync();

bool fileExists(String path) => path.isNotEmpty && File(path).existsSync();

/// Quote [s] for a POSIX shell when it needs it.
String quoteShell(String s) {
  if (s.isNotEmpty && RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(s)) return s;
  return "'${s.replaceAll("'", r"'\''")}'";
}

/// "foo.nim:12:3" -> "foo.nim", "foo.nim:12" -> "foo.nim", "foo:" -> "foo".
String _stripLineCol(String s) {
  var r = s;
  for (var k = 0; k < 2; k++) {
    final i = r.lastIndexOf(':');
    if (i <= 0) break;
    final tail = r.substring(i + 1);
    if (tail.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(tail)) break;
    r = r.substring(0, i);
  }
  return r;
}

List<String> _candidates(String word) {
  final r = [word];
  final noLine = _stripLineCol(word);
  if (noLine != word) r.add(noLine);
  for (final s in [word, noLine]) {
    if (s.length > 2 && (s[0] == 'a' || s[0] == 'b') && s[1] == '/') r.add(s.substring(2));
    if (s.length > 1 && (s.endsWith('*') || s.endsWith('@'))) r.add(s.substring(0, s.length - 1));
  }
  return r;
}

/// The absolute path that [word] names, if that file or directory exists
/// (relative paths are taken from [cwd]), else "".
String pathTarget(String word, String cwd) {
  if (word.isEmpty || word.startsWith('-') || word.contains('\x00')) return '';
  for (final c in _candidates(word)) {
    var path = expandTilde(c);
    if (!p.isAbsolute(path)) {
      if (cwd.isEmpty) continue;
      path = p.join(cwd, path);
    }
    if (dirExists(path) || fileExists(path)) return p.normalize(path);
  }
  return '';
}

/// The local path of a file:// URL (as `ls --hyperlink` prints), or "".
String fileUrlPath(String url) {
  if (!url.toLowerCase().startsWith('file://')) return '';
  final slash = url.indexOf('/', 'file://'.length);
  if (slash < 0) return '';
  try {
    return Uri.decodeComponent(url.substring(slash));
  } on ArgumentError {
    return url.substring(slash);
  }
}
