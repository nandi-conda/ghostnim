/// Keyboard shortcuts: which key chords run which ghostnim actions.
///
/// Chords are written like `ctrl+shift+t`: any of `ctrl`, `shift`, `alt` and
/// `super`, then one key. Keys are physical keys named as on a US layout:
/// `a`-`z`, `0`-`9`, `f1`-`f25`, `enter`, `tab`, `space`, `escape`,
/// `backspace`, `delete`, `insert`, `home`, `end`, `page-up`, `page-down`,
/// `up`, `down`, `left`, `right`, punctuation such as `=`, `-`, `,`, `/`,
/// or any libghostty key name (`numpad-add`, `bracket-left`, ...).
library;

import 'keys.dart';

enum Action {
  none('none'), // unbinds the chord
  copy('copy'),
  paste('paste'),
  selectAll('select-all'),
  newTab('new-tab'),
  closeTab('close-tab'),
  nextTab('next-tab'),
  previousTab('previous-tab'),
  gotoTab('goto-tab'), // arg: tab number, from 1
  scrollPageUp('scroll-page-up'), // half a screen
  scrollPageDown('scroll-page-down'),
  scrollToTop('scroll-to-top'),
  scrollToBottom('scroll-to-bottom'),
  fontBigger('font-bigger'),
  fontSmaller('font-smaller'),
  fontReset('font-reset'),
  sendText('send-text'), // arg: text written to the program
  reloadConfig('reload-config'),
  openConfig('open-config'),
  toggleFilePane('toggle-file-pane'),
  toggleHiddenFiles('toggle-hidden-files'), // in the file pane
  openFolderInEditor('open-folder-in-editor');

  final String name_;
  const Action(this.name_);

  @override
  String toString() => name_;
}

const modCtrl = 1, modShift = 2, modAlt = 4, modSuper = 8;

class Chord {
  final int key;
  final int mods; // modCtrl | modShift | ...
  const Chord(this.key, this.mods);

  @override
  bool operator ==(Object other) => other is Chord && other.key == key && other.mods == mods;
  @override
  int get hashCode => key * 16 + mods;

  /// "Ctrl+Shift+C", for showing in the menu.
  String get label {
    final b = StringBuffer();
    if (mods & modCtrl != 0) b.write('Ctrl+');
    if (mods & modShift != 0) b.write('Shift+');
    if (mods & modAlt != 0) b.write('Alt+');
    if (mods & modSuper != 0) b.write('Super+');
    const punct = {
      Key.equal: '=', Key.minus: '-', Key.comma: ',', Key.period: '.', Key.slash: '/', //
      Key.semicolon: ';', Key.quote: "'", Key.backquote: '`', Key.bracketLeft: '[',
      Key.bracketRight: ']', Key.backslash: r'\',
    };
    final p = punct[key];
    if (p != null) return '$b$p';
    var name = Key.names[key] ?? '?';
    if (name.startsWith('Digit')) name = name.substring(5);
    if (name.startsWith('Arrow')) name = name.substring(5);
    return '$b$name';
  }
}

class Binding {
  final Action action;
  final int num; // goto-tab's tab number
  final String text; // send-text's text
  const Binding(this.action, {this.num = 0, this.text = ''});
}

typedef Keybinds = Map<Chord, Binding>;

const _keyAliases = {
  '=': Key.equal, '-': Key.minus, ',': Key.comma, '.': Key.period, '/': Key.slash, //
  ';': Key.semicolon, "'": Key.quote, '`': Key.backquote, '[': Key.bracketLeft,
  ']': Key.bracketRight, r'\': Key.backslash,
  'up': Key.arrowUp, 'down': Key.arrowDown, 'left': Key.arrowLeft, 'right': Key.arrowRight,
  'esc': Key.escape, 'return': Key.enter, 'del': Key.delete, 'ins': Key.insert,
  'pgup': Key.pageUp, 'pgdn': Key.pageDown, 'pagedown': Key.pageDown, 'pageup': Key.pageUp,
  'plus': Key.equal, 'grave': Key.backquote, 'menu': Key.contextMenu,
};

int? _parseKey(String name) {
  final n = name.toLowerCase();
  final alias = _keyAliases[n];
  if (alias != null) return alias;
  if (n.length == 1 && n.codeUnitAt(0) >= 0x30 && n.codeUnitAt(0) <= 0x39) {
    return Key.digit0 + (n.codeUnitAt(0) - 0x30);
  }
  final norm = n.replaceAll('-', '').replaceAll('_', '');
  for (final e in Key.names.entries) {
    if (e.key != Key.unidentified && e.value.toLowerCase() == norm) return e.key;
  }
  return null;
}

/// "ctrl+shift+t" → Chord. The `+`/`=` key is spelled `=` or `plus`.
Chord? parseChord(String s) {
  final parts = s.split('+');
  if (parts.isEmpty || parts.last.isEmpty) return null;
  var mods = 0;
  for (final p in parts.sublist(0, parts.length - 1)) {
    switch (p.toLowerCase()) {
      case 'ctrl' || 'control':
        mods |= modCtrl;
      case 'shift':
        mods |= modShift;
      case 'alt' || 'opt' || 'option':
        mods |= modAlt;
      case 'super' || 'meta' || 'cmd' || 'gui' || 'win':
        mods |= modSuper;
      default:
        return null;
    }
  }
  final k = _parseKey(parts.last);
  return k == null ? null : Chord(k, mods);
}

Action? parseAction(String s) {
  for (final a in Action.values) {
    if (a.name_ == s) return a;
  }
  return null;
}

Keybinds defaultKeybinds() {
  final r = <Chord, Binding>{};
  void b(String chord, Action a) => r[parseChord(chord)!] = Binding(a);
  b('ctrl+shift+c', Action.copy);
  b('ctrl+shift+v', Action.paste);
  b('ctrl+shift+t', Action.newTab);
  b('ctrl+shift+w', Action.closeTab);
  b('ctrl+tab', Action.nextTab);
  b('ctrl+shift+tab', Action.previousTab);
  b('ctrl+page-down', Action.nextTab);
  b('ctrl+page-up', Action.previousTab);
  b('shift+page-up', Action.scrollPageUp);
  b('shift+page-down', Action.scrollPageDown);
  b('ctrl+=', Action.fontBigger);
  b('ctrl+shift+=', Action.fontBigger); // ctrl++ on a US layout
  b('ctrl+numpad-add', Action.fontBigger);
  b('ctrl+-', Action.fontSmaller);
  b('ctrl+numpad-subtract', Action.fontSmaller);
  b('ctrl+0', Action.fontReset);
  b('ctrl+shift+,', Action.reloadConfig);
  b('ctrl+,', Action.openConfig);
  b('ctrl+shift+e', Action.toggleFilePane);
  b('ctrl+shift+o', Action.openFolderInEditor);
  return r;
}

/// The shortest chord bound to [action], or "" if none.
String shortcutLabel(Keybinds kb, Action action) {
  var result = '';
  for (final e in kb.entries) {
    if (e.value.action != action) continue;
    final l = e.key.label;
    if (result.isEmpty ||
        l.length < result.length ||
        (l.length == result.length && l.compareTo(result) < 0)) {
      result = l;
    }
  }
  return result;
}
