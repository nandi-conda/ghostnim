/// Translation from Flutter keyboard state to libghostty-vt key events.
library;

import 'package:flutter/services.dart';

import 'keys.dart';
import 'vt.dart';

/// Map a physical key (USB HID usage, as SDL scancodes are) to a GhosttyKey
/// (W3C UI Events KeyboardEvent.code).
int toGhosttyKey(PhysicalKeyboardKey physical) {
  final usage = physical.usbHidUsage;
  if (usage >> 16 != 0x07) return Key.unidentified;
  final sc = usage & 0xFFFF;
  if (sc >= 4 && sc <= 29) return Key.a + (sc - 4); // A..Z
  if (sc >= 30 && sc <= 38) return Key.digit1 + (sc - 30); // 1..9
  if (sc >= 58 && sc <= 69) return Key.f1 + (sc - 58); // F1..F12
  if (sc >= 89 && sc <= 97) return Key.numpad1 + (sc - 89); // KP 1..9
  if (sc >= 104 && sc <= 115) return Key.f13 + (sc - 104); // F13..F24
  return switch (sc) {
    39 => Key.digit0,
    40 => Key.enter,
    41 => Key.escape,
    42 => Key.backspace,
    43 => Key.tab,
    44 => Key.space,
    45 => Key.minus,
    46 => Key.equal,
    47 => Key.bracketLeft,
    48 => Key.bracketRight,
    49 || 50 => Key.backslash,
    51 => Key.semicolon,
    52 => Key.quote,
    53 => Key.backquote,
    54 => Key.comma,
    55 => Key.period,
    56 => Key.slash,
    57 => Key.capsLock,
    70 => Key.printScreen,
    71 => Key.scrollLock,
    72 => Key.pause,
    73 => Key.insert,
    74 => Key.home,
    75 => Key.pageUp,
    76 => Key.delete,
    77 => Key.end,
    78 => Key.pageDown,
    79 => Key.arrowRight,
    80 => Key.arrowLeft,
    81 => Key.arrowDown,
    82 => Key.arrowUp,
    83 => Key.numLock,
    84 => Key.numpadDivide,
    85 => Key.numpadMultiply,
    86 => Key.numpadSubtract,
    87 => Key.numpadAdd,
    88 => Key.numpadEnter,
    98 => Key.numpad0,
    99 => Key.numpadDecimal,
    100 => Key.intlBackslash,
    101 => Key.contextMenu,
    103 => Key.numpadEqual,
    224 => Key.controlLeft,
    225 => Key.shiftLeft,
    226 => Key.altLeft,
    227 => Key.metaLeft,
    228 => Key.controlRight,
    229 => Key.shiftRight,
    230 => Key.altRight,
    231 => Key.metaRight,
    _ => Key.unidentified,
  };
}

/// The modifiers held right now, as GhosttyMods.
int currentMods() {
  final kb = HardwareKeyboard.instance;
  var m = 0;
  if (kb.isShiftPressed) m |= modsShift;
  if (kb.isControlPressed) m |= modsCtrl;
  if (kb.isAltPressed) m |= modsAlt;
  if (kb.isMetaPressed) m |= modsSuper;
  if (kb.lockModesEnabled.contains(KeyboardLockMode.capsLock)) m |= modsCapsLock;
  if (kb.lockModesEnabled.contains(KeyboardLockMode.numLock)) m |= modsNumLock;
  return m;
}

/// The layout's unshifted character for a key, or 0 for keys that don't
/// type one. Flutter's logical key ids for printable keys are their
/// (lowercase) Unicode code point.
int unshiftedCodepoint(LogicalKeyboardKey logical) {
  final id = logical.keyId;
  if (id & LogicalKeyboardKey.planeMask != LogicalKeyboardKey.unicodePlane) return 0;
  final cp = id & LogicalKeyboardKey.valueMask;
  if (cp < 0x20 || cp == 0x7f) return 0;
  return cp;
}
