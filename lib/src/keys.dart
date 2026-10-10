/// GhosttyKey values (W3C UI Events KeyboardEvent.code), generated from
/// include/ghostty/vt/key/event.h.
library;

abstract final class Key {
  static const unidentified = 0;
  static const backquote = 1;
  static const backslash = 2;
  static const bracketLeft = 3;
  static const bracketRight = 4;
  static const comma = 5;
  static const digit0 = 6;
  static const digit1 = 7;
  static const digit2 = 8;
  static const digit3 = 9;
  static const digit4 = 10;
  static const digit5 = 11;
  static const digit6 = 12;
  static const digit7 = 13;
  static const digit8 = 14;
  static const digit9 = 15;
  static const equal = 16;
  static const intlBackslash = 17;
  static const intlRo = 18;
  static const intlYen = 19;
  static const a = 20;
  static const b = 21;
  static const c = 22;
  static const d = 23;
  static const e = 24;
  static const f = 25;
  static const g = 26;
  static const h = 27;
  static const i = 28;
  static const j = 29;
  static const k = 30;
  static const l = 31;
  static const m = 32;
  static const n = 33;
  static const o = 34;
  static const p = 35;
  static const q = 36;
  static const r = 37;
  static const s = 38;
  static const t = 39;
  static const u = 40;
  static const v = 41;
  static const w = 42;
  static const x = 43;
  static const y = 44;
  static const z = 45;
  static const minus = 46;
  static const period = 47;
  static const quote = 48;
  static const semicolon = 49;
  static const slash = 50;
  static const altLeft = 51;
  static const altRight = 52;
  static const backspace = 53;
  static const capsLock = 54;
  static const contextMenu = 55;
  static const controlLeft = 56;
  static const controlRight = 57;
  static const enter = 58;
  static const metaLeft = 59;
  static const metaRight = 60;
  static const shiftLeft = 61;
  static const shiftRight = 62;
  static const space = 63;
  static const tab = 64;
  static const convert = 65;
  static const kanaMode = 66;
  static const nonConvert = 67;
  static const delete = 68;
  static const end = 69;
  static const help = 70;
  static const home = 71;
  static const insert = 72;
  static const pageDown = 73;
  static const pageUp = 74;
  static const arrowDown = 75;
  static const arrowLeft = 76;
  static const arrowRight = 77;
  static const arrowUp = 78;
  static const numLock = 79;
  static const numpad0 = 80;
  static const numpad1 = 81;
  static const numpad2 = 82;
  static const numpad3 = 83;
  static const numpad4 = 84;
  static const numpad5 = 85;
  static const numpad6 = 86;
  static const numpad7 = 87;
  static const numpad8 = 88;
  static const numpad9 = 89;
  static const numpadAdd = 90;
  static const numpadBackspace = 91;
  static const numpadClear = 92;
  static const numpadClearEntry = 93;
  static const numpadComma = 94;
  static const numpadDecimal = 95;
  static const numpadDivide = 96;
  static const numpadEnter = 97;
  static const numpadEqual = 98;
  static const numpadMemoryAdd = 99;
  static const numpadMemoryClear = 100;
  static const numpadMemoryRecall = 101;
  static const numpadMemoryStore = 102;
  static const numpadMemorySubtract = 103;
  static const numpadMultiply = 104;
  static const numpadParenLeft = 105;
  static const numpadParenRight = 106;
  static const numpadSubtract = 107;
  static const numpadSeparator = 108;
  static const numpadUp = 109;
  static const numpadDown = 110;
  static const numpadRight = 111;
  static const numpadLeft = 112;
  static const numpadBegin = 113;
  static const numpadHome = 114;
  static const numpadEnd = 115;
  static const numpadInsert = 116;
  static const numpadDelete = 117;
  static const numpadPageUp = 118;
  static const numpadPageDown = 119;
  static const escape = 120;
  static const f1 = 121;
  static const f2 = 122;
  static const f3 = 123;
  static const f4 = 124;
  static const f5 = 125;
  static const f6 = 126;
  static const f7 = 127;
  static const f8 = 128;
  static const f9 = 129;
  static const f10 = 130;
  static const f11 = 131;
  static const f12 = 132;
  static const f13 = 133;
  static const f14 = 134;
  static const f15 = 135;
  static const f16 = 136;
  static const f17 = 137;
  static const f18 = 138;
  static const f19 = 139;
  static const f20 = 140;
  static const f21 = 141;
  static const f22 = 142;
  static const f23 = 143;
  static const f24 = 144;
  static const f25 = 145;
  static const fn = 146;
  static const fnLock = 147;
  static const printScreen = 148;
  static const scrollLock = 149;
  static const pause = 150;
  static const browserBack = 151;
  static const browserFavorites = 152;
  static const browserForward = 153;
  static const browserHome = 154;
  static const browserRefresh = 155;
  static const browserSearch = 156;
  static const browserStop = 157;
  static const eject = 158;
  static const launchApp1 = 159;
  static const launchApp2 = 160;
  static const launchMail = 161;
  static const mediaPlayPause = 162;
  static const mediaSelect = 163;
  static const mediaStop = 164;
  static const mediaTrackNext = 165;
  static const mediaTrackPrevious = 166;
  static const power = 167;
  static const sleep = 168;
  static const audioVolumeDown = 169;
  static const audioVolumeMute = 170;
  static const audioVolumeUp = 171;
  static const wakeUp = 172;
  static const copy = 173;
  static const cut = 174;
  static const paste = 175;

  /// Each key's name as in event.h, e.g. "BracketLeft".
  static const names = <int, String>{
    0: 'Unidentified',
    1: 'Backquote',
    2: 'Backslash',
    3: 'BracketLeft',
    4: 'BracketRight',
    5: 'Comma',
    6: 'Digit0',
    7: 'Digit1',
    8: 'Digit2',
    9: 'Digit3',
    10: 'Digit4',
    11: 'Digit5',
    12: 'Digit6',
    13: 'Digit7',
    14: 'Digit8',
    15: 'Digit9',
    16: 'Equal',
    17: 'IntlBackslash',
    18: 'IntlRo',
    19: 'IntlYen',
    20: 'A',
    21: 'B',
    22: 'C',
    23: 'D',
    24: 'E',
    25: 'F',
    26: 'G',
    27: 'H',
    28: 'I',
    29: 'J',
    30: 'K',
    31: 'L',
    32: 'M',
    33: 'N',
    34: 'O',
    35: 'P',
    36: 'Q',
    37: 'R',
    38: 'S',
    39: 'T',
    40: 'U',
    41: 'V',
    42: 'W',
    43: 'X',
    44: 'Y',
    45: 'Z',
    46: 'Minus',
    47: 'Period',
    48: 'Quote',
    49: 'Semicolon',
    50: 'Slash',
    51: 'AltLeft',
    52: 'AltRight',
    53: 'Backspace',
    54: 'CapsLock',
    55: 'ContextMenu',
    56: 'ControlLeft',
    57: 'ControlRight',
    58: 'Enter',
    59: 'MetaLeft',
    60: 'MetaRight',
    61: 'ShiftLeft',
    62: 'ShiftRight',
    63: 'Space',
    64: 'Tab',
    65: 'Convert',
    66: 'KanaMode',
    67: 'NonConvert',
    68: 'Delete',
    69: 'End',
    70: 'Help',
    71: 'Home',
    72: 'Insert',
    73: 'PageDown',
    74: 'PageUp',
    75: 'ArrowDown',
    76: 'ArrowLeft',
    77: 'ArrowRight',
    78: 'ArrowUp',
    79: 'NumLock',
    80: 'Numpad0',
    81: 'Numpad1',
    82: 'Numpad2',
    83: 'Numpad3',
    84: 'Numpad4',
    85: 'Numpad5',
    86: 'Numpad6',
    87: 'Numpad7',
    88: 'Numpad8',
    89: 'Numpad9',
    90: 'NumpadAdd',
    91: 'NumpadBackspace',
    92: 'NumpadClear',
    93: 'NumpadClearEntry',
    94: 'NumpadComma',
    95: 'NumpadDecimal',
    96: 'NumpadDivide',
    97: 'NumpadEnter',
    98: 'NumpadEqual',
    99: 'NumpadMemoryAdd',
    100: 'NumpadMemoryClear',
    101: 'NumpadMemoryRecall',
    102: 'NumpadMemoryStore',
    103: 'NumpadMemorySubtract',
    104: 'NumpadMultiply',
    105: 'NumpadParenLeft',
    106: 'NumpadParenRight',
    107: 'NumpadSubtract',
    108: 'NumpadSeparator',
    109: 'NumpadUp',
    110: 'NumpadDown',
    111: 'NumpadRight',
    112: 'NumpadLeft',
    113: 'NumpadBegin',
    114: 'NumpadHome',
    115: 'NumpadEnd',
    116: 'NumpadInsert',
    117: 'NumpadDelete',
    118: 'NumpadPageUp',
    119: 'NumpadPageDown',
    120: 'Escape',
    121: 'F1',
    122: 'F2',
    123: 'F3',
    124: 'F4',
    125: 'F5',
    126: 'F6',
    127: 'F7',
    128: 'F8',
    129: 'F9',
    130: 'F10',
    131: 'F11',
    132: 'F12',
    133: 'F13',
    134: 'F14',
    135: 'F15',
    136: 'F16',
    137: 'F17',
    138: 'F18',
    139: 'F19',
    140: 'F20',
    141: 'F21',
    142: 'F22',
    143: 'F23',
    144: 'F24',
    145: 'F25',
    146: 'Fn',
    147: 'FnLock',
    148: 'PrintScreen',
    149: 'ScrollLock',
    150: 'Pause',
    151: 'BrowserBack',
    152: 'BrowserFavorites',
    153: 'BrowserForward',
    154: 'BrowserHome',
    155: 'BrowserRefresh',
    156: 'BrowserSearch',
    157: 'BrowserStop',
    158: 'Eject',
    159: 'LaunchApp1',
    160: 'LaunchApp2',
    161: 'LaunchMail',
    162: 'MediaPlayPause',
    163: 'MediaSelect',
    164: 'MediaStop',
    165: 'MediaTrackNext',
    166: 'MediaTrackPrevious',
    167: 'Power',
    168: 'Sleep',
    169: 'AudioVolumeDown',
    170: 'AudioVolumeMute',
    171: 'AudioVolumeUp',
    172: 'WakeUp',
    173: 'Copy',
    174: 'Cut',
    175: 'Paste',
  };
}
