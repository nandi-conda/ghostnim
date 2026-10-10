/// Dart bindings for libghostty-vt, the C API of Ghostty's terminal core.
///
/// Only the subset of the API ghostnim needs is bound here. Struct layouts
/// follow the headers in `include/ghostty/vt` at the commit pinned in
/// `scripts/build-libghostty-vt.sh`.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef GhosttyTerminal = Pointer<Void>;
typedef GhosttyRenderState = Pointer<Void>;
typedef GhosttyRowIterator = Pointer<Void>;
typedef GhosttyRowCells = Pointer<Void>;
typedef GhosttyKeyEncoder = Pointer<Void>;
typedef GhosttyKeyEvent = Pointer<Void>;
typedef GhosttyMouseEncoder = Pointer<Void>;
typedef GhosttyMouseEvent = Pointer<Void>;
typedef GhosttyFormatter = Pointer<Void>;

final class GhosttyString extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int len;
}

final class GhosttyBuffer extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int cap;
  @Size()
  external int len;
}

final class GhosttyColorRgb extends Struct {
  @Uint8()
  external int r;
  @Uint8()
  external int g;
  @Uint8()
  external int b;
}

final class GhosttyStyleColorValue extends Union {
  @Uint8()
  external int palette;
  external GhosttyColorRgb rgb;
  @Uint64()
  external int padding;
}

final class GhosttyStyleColor extends Struct {
  @Int32()
  external int tag;
  external GhosttyStyleColorValue value;
}

final class GhosttyStyle extends Struct {
  @Size()
  external int size;
  external GhosttyStyleColor fgColor;
  external GhosttyStyleColor bgColor;
  external GhosttyStyleColor underlineColor;
  @Bool()
  external bool bold;
  @Bool()
  external bool italic;
  @Bool()
  external bool faint;
  @Bool()
  external bool blink;
  @Bool()
  external bool inverse;
  @Bool()
  external bool invisible;
  @Bool()
  external bool strikethrough;
  @Bool()
  external bool overline;
  @Int32()
  external int underline;
}

final class GhosttyRenderStateColors extends Struct {
  @Size()
  external int size;
  external GhosttyColorRgb background;
  external GhosttyColorRgb foreground;
  external GhosttyColorRgb cursor;
  @Bool()
  external bool cursorHasValue;
  @Array(256)
  external Array<GhosttyColorRgb> palette;
}

final class GhosttyRenderStateCursor extends Struct {
  @Size()
  external int size;
  @Bool()
  external bool viewportHasValue;
  @Uint16()
  external int viewportX;
  @Uint16()
  external int viewportY;
  @Bool()
  external bool wideTail;
  @Bool()
  external bool visible;
  @Bool()
  external bool blinking;
  @Bool()
  external bool passwordInput;
  @Int32()
  external int visualStyle;
}

final class GhosttyRenderStateRowSelection extends Struct {
  @Size()
  external int size;
  @Uint16()
  external int startX;
  @Uint16()
  external int endX;
}

final class GhosttyPointCoordinate extends Struct {
  @Uint16()
  external int x;
  @Uint32()
  external int y;
}

final class GhosttyPointValue extends Union {
  external GhosttyPointCoordinate coordinate;
  @Array(2)
  external Array<Uint64> padding;
}

final class GhosttyPoint extends Struct {
  @Int32()
  external int tag;
  external GhosttyPointValue value;
}

final class GhosttyGridRef extends Struct {
  @Size()
  external int size;
  external Pointer<Void> node;
  @Uint16()
  external int x;
  @Uint16()
  external int y;
}

final class GhosttySelection extends Struct {
  @Size()
  external int size;
  external GhosttyGridRef start;
  external GhosttyGridRef end;
  @Bool()
  external bool rectangle;
}

final class GhosttyScrollViewportValue extends Union {
  @IntPtr()
  external int delta;
  @Size()
  external int row;
  @Array(2)
  external Array<Uint64> padding;
}

final class GhosttyScrollViewport extends Struct {
  @Int32()
  external int tag;
  external GhosttyScrollViewportValue value;
}

final class GhosttyModeConfig extends Struct {
  @Uint16()
  external int mode;
  @Bool()
  external bool value;
}

final class GhosttyMousePosition extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

final class GhosttyMouseEncoderSize extends Struct {
  @Size()
  external int size;
  @Uint32()
  external int screenWidth;
  @Uint32()
  external int screenHeight;
  @Uint32()
  external int cellWidth;
  @Uint32()
  external int cellHeight;
  @Uint32()
  external int paddingTop;
  @Uint32()
  external int paddingBottom;
  @Uint32()
  external int paddingRight;
  @Uint32()
  external int paddingLeft;
}

final class GhosttyFormatterScreenExtra extends Struct {
  @Size()
  external int size;
  @Bool()
  external bool cursor;
  @Bool()
  external bool style;
  @Bool()
  external bool hyperlink;
  @Bool()
  external bool protection;
  @Bool()
  external bool kittyKeyboard;
  @Bool()
  external bool charsets;
}

final class GhosttyFormatterTerminalExtra extends Struct {
  @Size()
  external int size;
  @Bool()
  external bool palette;
  @Bool()
  external bool modes;
  @Bool()
  external bool scrollingRegion;
  @Bool()
  external bool tabstops;
  @Bool()
  external bool pwd;
  @Bool()
  external bool keyboard;
  external GhosttyFormatterScreenExtra screen;
}

final class GhosttyFormatterTerminalOptions extends Struct {
  @Size()
  external int size;
  @Int32()
  external int emit;
  @Bool()
  external bool unwrap;
  @Bool()
  external bool trim;
  external GhosttyFormatterTerminalExtra extra;
  external Pointer<GhosttySelection> selection;
}

// --- constants ---------------------------------------------------------------

const ghosttySuccess = 0;
const ghosttyOutOfSpace = -3;
const ghosttyNoValue = -4;

const styleColorNone = 0;
const styleColorPalette = 1;
const styleColorRgb = 2;

const sgrUnderlineNone = 0;
const sgrUnderlineSingle = 1;
const sgrUnderlineDouble = 2;
const sgrUnderlineCurly = 3;

// GhosttyTerminalOption
const termOptUserdata = 0;
const termOptWritePty = 1;
const termOptBell = 2;
const termOptTitleChanged = 5;
const termOptColorForeground = 11;
const termOptColorBackground = 12;
const termOptColorCursor = 13;
const termOptColorPalette = 14;
const termOptSelection = 21;
const termOptScrollbackMaxLines = 28;

// GhosttyTerminalData
const termDataCols = 1;
const termDataRows = 2;
const termDataMouseTracking = 11;
const termDataTitle = 12;
const termDataColorPaletteDefault = 25;
const termDataSelection = 31;
const termDataMode = 37;

const scrollViewportTop = 0;
const scrollViewportBottom = 1;
const scrollViewportDelta = 2;

const pointTagActive = 0;
const pointTagViewport = 1;
const pointTagScreen = 2;

const renderDirtyFalse = 0;
const renderDirtyPartial = 1;
const renderDirtyFull = 2;

const cursorBar = 0;
const cursorBlock = 1;
const cursorUnderline = 2;
const cursorBlockHollow = 3;

const renderDataCols = 1;
const renderDataRows = 2;
const renderDataDirty = 3;
const renderDataRowIterator = 4;
const renderDataCursor = 18;
const renderDataColors = 19;

const rowDataDirty = 1;
const rowDataCells = 3;
const rowDataSelection = 4;

const cellsDataRaw = 1;
const cellsDataStyle = 2;
const cellsDataGraphemesLen = 3;
const cellsDataBgColor = 5;
const cellsDataFgColor = 6;
const cellsDataGraphemesUtf8 = 9;

const rowOptionDirty = 0;

const rowDataWrap = 1;

const cellDataWide = 3;
const cellWideNarrow = 0;
const cellWideWide = 1;
const cellWideSpacerTail = 2;

const keyActionRelease = 0;
const keyActionPress = 1;
const keyActionRepeat = 2;

const modsShift = 1 << 0;
const modsCtrl = 1 << 1;
const modsAlt = 1 << 2;
const modsSuper = 1 << 3;
const modsCapsLock = 1 << 4;
const modsNumLock = 1 << 5;

const mouseActionPress = 0;
const mouseActionRelease = 1;
const mouseActionMotion = 2;
const mouseButtonLeft = 1;
const mouseButtonRight = 2;
const mouseButtonMiddle = 3;
const mouseButtonFour = 4; // wheel up
const mouseButtonFive = 5; // wheel down
const mouseEncoderOptSize = 2;
const mouseEncoderOptAnyButtonPressed = 3;

const formatterFormatPlain = 0;

/// `ghostty_mode_new`, a static inline function in the header.
int ghosttyMode(int value, bool ansi) => (value & 0x7FFF) | ((ansi ? 1 : 0) << 15);

// --- functions ---------------------------------------------------------------

typedef WritePtyNative = Void Function(GhosttyTerminal, Pointer<Void>, Pointer<Uint8>, Size);
typedef TerminalCallbackNative = Void Function(GhosttyTerminal, Pointer<Void>);

/// The directory holding the running executable's bundled libraries.
String _bundleLibDir() => p.join(p.dirname(Platform.resolvedExecutable), 'lib');

DynamicLibrary _open() {
  final env = Platform.environment['GHOSTTY_VT_LIBRARY'];
  final candidates = [
    if (env != null && env.isNotEmpty) env,
    p.join(_bundleLibDir(), 'libghostty-vt.so'),
    'libghostty-vt.so',
    'libghostty-vt.so.0',
  ];
  Object? last;
  for (final c in candidates) {
    try {
      return DynamicLibrary.open(c);
    } catch (e) {
      last = e;
    }
  }
  throw StateError('could not load libghostty-vt: $last');
}

final DynamicLibrary _lib = _open();

class Vt {
  Vt._();

  static final free = _lib.lookupFunction<Void Function(Pointer<Void>, Pointer<Void>, Size),
      void Function(Pointer<Void>, Pointer<Void>, int)>('ghostty_free');

  // Terminal
  static final terminalNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyTerminal>, Uint16, Uint16),
      int Function(Pointer<Void>, Pointer<GhosttyTerminal>, int, int)>('ghostty_terminal_new');
  static final terminalFree =
      _lib.lookupFunction<Void Function(GhosttyTerminal), void Function(GhosttyTerminal)>(
          'ghostty_terminal_free');
  static final terminalResize = _lib.lookupFunction<
      Int32 Function(GhosttyTerminal, Uint16, Uint16, Uint32, Uint32),
      int Function(GhosttyTerminal, int, int, int, int)>('ghostty_terminal_resize');
  static final terminalSet = _lib.lookupFunction<
      Int32 Function(GhosttyTerminal, Int32, Pointer<Void>),
      int Function(GhosttyTerminal, int, Pointer<Void>)>('ghostty_terminal_set');
  static final terminalGet = _lib.lookupFunction<
      Int32 Function(GhosttyTerminal, Int32, Pointer<Void>),
      int Function(GhosttyTerminal, int, Pointer<Void>)>('ghostty_terminal_get');
  static final terminalVtWrite = _lib.lookupFunction<
      Void Function(GhosttyTerminal, Pointer<Uint8>, Size),
      void Function(GhosttyTerminal, Pointer<Uint8>, int)>('ghostty_terminal_vt_write');
  static final terminalScrollViewport = _lib.lookupFunction<
      Void Function(GhosttyTerminal, GhosttyScrollViewport),
      void Function(GhosttyTerminal, GhosttyScrollViewport)>('ghostty_terminal_scroll_viewport');
  static final terminalGridRef = _lib.lookupFunction<
      Int32 Function(GhosttyTerminal, GhosttyPoint, Pointer<GhosttyGridRef>),
      int Function(
          GhosttyTerminal, GhosttyPoint, Pointer<GhosttyGridRef>)>('ghostty_terminal_grid_ref');

  static final cellGet = _lib.lookupFunction<Int32 Function(Uint64, Int32, Pointer<Void>),
      int Function(int, int, Pointer<Void>)>('ghostty_cell_get');
  static final rowGet = _lib.lookupFunction<Int32 Function(Uint64, Int32, Pointer<Void>),
      int Function(int, int, Pointer<Void>)>('ghostty_row_get');

  // Grid references
  static final gridRefCell = _lib.lookupFunction<
      Int32 Function(Pointer<GhosttyGridRef>, Pointer<Uint64>),
      int Function(Pointer<GhosttyGridRef>, Pointer<Uint64>)>('ghostty_grid_ref_cell');
  static final gridRefRow = _lib.lookupFunction<
      Int32 Function(Pointer<GhosttyGridRef>, Pointer<Uint64>),
      int Function(Pointer<GhosttyGridRef>, Pointer<Uint64>)>('ghostty_grid_ref_row');
  static final gridRefGraphemes = _lib.lookupFunction<
      Int32 Function(Pointer<GhosttyGridRef>, Pointer<Uint32>, Size, Pointer<Size>),
      int Function(Pointer<GhosttyGridRef>, Pointer<Uint32>, int,
          Pointer<Size>)>('ghostty_grid_ref_graphemes');
  static final gridRefHyperlinkUri = _lib.lookupFunction<
      Int32 Function(Pointer<GhosttyGridRef>, Pointer<Uint8>, Size, Pointer<Size>),
      int Function(Pointer<GhosttyGridRef>, Pointer<Uint8>, int,
          Pointer<Size>)>('ghostty_grid_ref_hyperlink_uri');

  // Render state
  static final renderStateNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyRenderState>),
      int Function(Pointer<Void>, Pointer<GhosttyRenderState>)>('ghostty_render_state_new');
  static final renderStateFree =
      _lib.lookupFunction<Void Function(GhosttyRenderState), void Function(GhosttyRenderState)>(
          'ghostty_render_state_free');
  static final renderStateUpdate = _lib.lookupFunction<
      Int32 Function(GhosttyRenderState, GhosttyTerminal),
      int Function(GhosttyRenderState, GhosttyTerminal)>('ghostty_render_state_update');
  static final renderStateClean =
      _lib.lookupFunction<Int32 Function(GhosttyRenderState), int Function(GhosttyRenderState)>(
          'ghostty_render_state_clean');
  static final renderStateGet = _lib.lookupFunction<
      Int32 Function(GhosttyRenderState, Int32, Pointer<Void>),
      int Function(GhosttyRenderState, int, Pointer<Void>)>('ghostty_render_state_get');
  static final rowIteratorNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyRowIterator>),
      int Function(
          Pointer<Void>, Pointer<GhosttyRowIterator>)>('ghostty_render_state_row_iterator_new');
  static final rowIteratorFree =
      _lib.lookupFunction<Void Function(GhosttyRowIterator), void Function(GhosttyRowIterator)>(
          'ghostty_render_state_row_iterator_free');
  static final rowIteratorNext =
      _lib.lookupFunction<Bool Function(GhosttyRowIterator), bool Function(GhosttyRowIterator)>(
          'ghostty_render_state_row_iterator_next');
  static final rowGetState = _lib.lookupFunction<
      Int32 Function(GhosttyRowIterator, Int32, Pointer<Void>),
      int Function(GhosttyRowIterator, int, Pointer<Void>)>('ghostty_render_state_row_get');
  static final rowCellsNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyRowCells>),
      int Function(Pointer<Void>, Pointer<GhosttyRowCells>)>('ghostty_render_state_row_cells_new');
  static final rowCellsFree =
      _lib.lookupFunction<Void Function(GhosttyRowCells), void Function(GhosttyRowCells)>(
          'ghostty_render_state_row_cells_free');
  static final rowCellsNext =
      _lib.lookupFunction<Bool Function(GhosttyRowCells), bool Function(GhosttyRowCells)>(
          'ghostty_render_state_row_cells_next');
  static final rowCellsGet = _lib.lookupFunction<
      Int32 Function(GhosttyRowCells, Int32, Pointer<Void>),
      int Function(GhosttyRowCells, int, Pointer<Void>)>('ghostty_render_state_row_cells_get');

  // Key encoding
  static final keyEncoderNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyKeyEncoder>),
      int Function(Pointer<Void>, Pointer<GhosttyKeyEncoder>)>('ghostty_key_encoder_new');
  static final keyEncoderSetoptFromTerminal = _lib.lookupFunction<
      Void Function(GhosttyKeyEncoder, GhosttyTerminal),
      void Function(
          GhosttyKeyEncoder, GhosttyTerminal)>('ghostty_key_encoder_setopt_from_terminal');
  static final keyEncoderEncode = _lib.lookupFunction<
      Int32 Function(GhosttyKeyEncoder, GhosttyKeyEvent, Pointer<Uint8>, Size, Pointer<Size>),
      int Function(GhosttyKeyEncoder, GhosttyKeyEvent, Pointer<Uint8>, int,
          Pointer<Size>)>('ghostty_key_encoder_encode');
  static final keyEventNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyKeyEvent>),
      int Function(Pointer<Void>, Pointer<GhosttyKeyEvent>)>('ghostty_key_event_new');
  static final keyEventSetAction = _lib.lookupFunction<Void Function(GhosttyKeyEvent, Int32),
      void Function(GhosttyKeyEvent, int)>('ghostty_key_event_set_action');
  static final keyEventSetKey = _lib.lookupFunction<Void Function(GhosttyKeyEvent, Int32),
      void Function(GhosttyKeyEvent, int)>('ghostty_key_event_set_key');
  static final keyEventSetMods = _lib.lookupFunction<Void Function(GhosttyKeyEvent, Uint16),
      void Function(GhosttyKeyEvent, int)>('ghostty_key_event_set_mods');
  static final keyEventSetConsumedMods = _lib.lookupFunction<Void Function(GhosttyKeyEvent, Uint16),
      void Function(GhosttyKeyEvent, int)>('ghostty_key_event_set_consumed_mods');
  static final keyEventSetUtf8 = _lib.lookupFunction<
      Void Function(GhosttyKeyEvent, Pointer<Uint8>, Size),
      void Function(GhosttyKeyEvent, Pointer<Uint8>, int)>('ghostty_key_event_set_utf8');
  static final keyEventSetUnshiftedCodepoint = _lib.lookupFunction<
      Void Function(GhosttyKeyEvent, Uint32),
      void Function(GhosttyKeyEvent, int)>('ghostty_key_event_set_unshifted_codepoint');

  // Mouse encoding
  static final mouseEncoderNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyMouseEncoder>),
      int Function(Pointer<Void>, Pointer<GhosttyMouseEncoder>)>('ghostty_mouse_encoder_new');
  static final mouseEncoderSetopt = _lib.lookupFunction<
      Void Function(GhosttyMouseEncoder, Int32, Pointer<Void>),
      void Function(GhosttyMouseEncoder, int, Pointer<Void>)>('ghostty_mouse_encoder_setopt');
  static final mouseEncoderSetoptFromTerminal = _lib.lookupFunction<
      Void Function(GhosttyMouseEncoder, GhosttyTerminal),
      void Function(
          GhosttyMouseEncoder, GhosttyTerminal)>('ghostty_mouse_encoder_setopt_from_terminal');
  static final mouseEncoderEncode = _lib.lookupFunction<
      Int32 Function(GhosttyMouseEncoder, GhosttyMouseEvent, Pointer<Uint8>, Size, Pointer<Size>),
      int Function(GhosttyMouseEncoder, GhosttyMouseEvent, Pointer<Uint8>, int,
          Pointer<Size>)>('ghostty_mouse_encoder_encode');
  static final mouseEventNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyMouseEvent>),
      int Function(Pointer<Void>, Pointer<GhosttyMouseEvent>)>('ghostty_mouse_event_new');
  static final mouseEventSetAction = _lib.lookupFunction<Void Function(GhosttyMouseEvent, Int32),
      void Function(GhosttyMouseEvent, int)>('ghostty_mouse_event_set_action');
  static final mouseEventSetButton = _lib.lookupFunction<Void Function(GhosttyMouseEvent, Int32),
      void Function(GhosttyMouseEvent, int)>('ghostty_mouse_event_set_button');
  static final mouseEventClearButton =
      _lib.lookupFunction<Void Function(GhosttyMouseEvent), void Function(GhosttyMouseEvent)>(
          'ghostty_mouse_event_clear_button');
  static final mouseEventSetMods = _lib.lookupFunction<Void Function(GhosttyMouseEvent, Uint16),
      void Function(GhosttyMouseEvent, int)>('ghostty_mouse_event_set_mods');
  static final mouseEventSetPosition = _lib.lookupFunction<
      Void Function(GhosttyMouseEvent, GhosttyMousePosition),
      void Function(GhosttyMouseEvent, GhosttyMousePosition)>('ghostty_mouse_event_set_position');

  // Paste encoding
  static final pasteEncode = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Size, Bool, Pointer<Uint8>, Size, Pointer<Size>),
      int Function(
          Pointer<Uint8>, int, bool, Pointer<Uint8>, int, Pointer<Size>)>('ghostty_paste_encode');

  // Formatter
  static final formatterTerminalNew = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<GhosttyFormatter>, GhosttyTerminal,
          GhosttyFormatterTerminalOptions),
      int Function(Pointer<Void>, Pointer<GhosttyFormatter>, GhosttyTerminal,
          GhosttyFormatterTerminalOptions)>('ghostty_formatter_terminal_new');
  static final formatterFormatAlloc = _lib.lookupFunction<
      Int32 Function(GhosttyFormatter, Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>),
      int Function(GhosttyFormatter, Pointer<Void>, Pointer<Pointer<Uint8>>,
          Pointer<Size>)>('ghostty_formatter_format_alloc');
  static final formatterFree =
      _lib.lookupFunction<Void Function(GhosttyFormatter), void Function(GhosttyFormatter)>(
          'ghostty_formatter_free');
}
