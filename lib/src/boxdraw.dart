/// Procedural drawing of box-drawing (U+2500–U+257F) and block element
/// (U+2580–U+259F) characters, so lines and blocks join seamlessly across
/// cells regardless of the font's metrics (Ghostty does the same).
library;

import 'dart:math' as math;
import 'dart:ui';

/// Arm weights for U+2500..U+257F, packed as 2 bits each: up, right, down,
/// left (0 none, 1 light, 2 heavy, 3 double). 0 means "not handled" (the
/// diagonals), which falls back to the font. The rounded corners
/// U+256D..U+2570 are drawn as arcs by [_drawArc].
const _boxArms = <int>[
  0x11,
  0x22,
  0x44,
  0x88,
  0x11,
  0x22,
  0x44,
  0x88,
  0x11,
  0x22,
  0x44,
  0x88,
  0x14,
  0x24,
  0x18,
  0x28,
  0x05,
  0x06,
  0x09,
  0x0a,
  0x50,
  0x60,
  0x90,
  0xa0,
  0x41,
  0x42,
  0x81,
  0x82,
  0x54,
  0x64,
  0x94,
  0x58,
  0x98,
  0xa4,
  0x68,
  0xa8,
  0x45,
  0x46,
  0x85,
  0x49,
  0x89,
  0x86,
  0x4a,
  0x8a,
  0x15,
  0x16,
  0x25,
  0x26,
  0x19,
  0x1a,
  0x29,
  0x2a,
  0x51,
  0x52,
  0x61,
  0x62,
  0x91,
  0x92,
  0xa1,
  0xa2,
  0x55,
  0x56,
  0x65,
  0x66,
  0x95,
  0x59,
  0x99,
  0x96,
  0xa5,
  0x5a,
  0x69,
  0xa6,
  0x6a,
  0x9a,
  0xa9,
  0xaa,
  0x11,
  0x22,
  0x44,
  0x88,
  0x33,
  0xcc,
  0x34,
  0x1c,
  0x3c,
  0x07,
  0x0d,
  0x0f,
  0x70,
  0xd0,
  0xf0,
  0x43,
  0xc1,
  0xc3,
  0x74,
  0xdc,
  0xfc,
  0x47,
  0xcd,
  0xcf,
  0x37,
  0x1d,
  0x3f,
  0x73,
  0xd1,
  0xf3,
  0x77,
  0xdd,
  0xff,
  0x14,
  0x05,
  0x41,
  0x50,
  0x00,
  0x00,
  0x00,
  0x01,
  0x40,
  0x10,
  0x04,
  0x02,
  0x80,
  0x20,
  0x08,
  0x21,
  0x48,
  0x12,
  0x84,
];

bool isSpecial(int cp) =>
    (cp >= 0x2500 && cp <= 0x257F && _boxArms[cp - 0x2500] != 0) || (cp >= 0x2580 && cp <= 0x259F);

typedef _Fill = void Function(double x, double y, double w, double h, double alpha);

/// Draw special character [cp] into the cell rectangle (x, y, w, h), which
/// should be in whole device pixels; [px] is the size of a device pixel.
void drawSpecial(Canvas canvas, int cp, double x, double y, double w, double h, Color color,
    {double px = 1}) {
  final paint = Paint()..isAntiAlias = false;
  void fill(double fx, double fy, double fw, double fh, double a) {
    if (fw <= 0 || fh <= 0) return;
    paint.color = color.withValues(alpha: color.a * a);
    canvas.drawRect(Rect.fromLTWH(fx * px, fy * px, fw * px, fh * px), paint);
  }

  // Work in device pixels so strokes stay crisp.
  final dx = (x / px).roundToDouble(), dy = (y / px).roundToDouble();
  final dw = ((x + w) / px).roundToDouble() - dx, dh = ((y + h) / px).roundToDouble() - dy;
  if (cp < 0x2580) {
    if (cp >= 0x256D && cp <= 0x2570) {
      _drawArc(canvas, cp, dx, dy, dw, dh, color, px);
    } else {
      _drawBox(cp, dx.toInt(), dy.toInt(), dw.toInt(), dh.toInt(), fill);
    }
  } else {
    _drawBlock(cp, dx.toInt(), dy.toInt(), dw.toInt(), dh.toInt(), fill);
  }
}

/// Rounded corners U+256D..U+2570: a quarter circle joining the centre
/// lines, with straight runs to the edges.
void _drawArc(
    Canvas canvas, int cp, double x, double y, double w, double h, Color color, double px) {
  final light = math.max(1, (math.min(w, h) + 4) ~/ 9).toDouble();
  final midX = x + ((w - light) / 2).floorToDouble() + light / 2;
  final midY = y + ((h - light) / 2).floorToDouble() + light / 2;
  final (sx, sy) = switch (cp) {
    0x256D => (1, 1), // ╭ right + down
    0x256E => (-1, 1), // ╮ left + down
    0x256F => (-1, -1), // ╯ left + up
    _ => (1, -1), // ╰ right + up
  };
  final rx = sx > 0 ? x + w - midX : midX - x;
  final ry = sy > 0 ? y + h - midY : midY - y;
  final r = math.max(1.0, math.min(rx, ry) - light / 2);
  final ocx = midX + sx * r, ocy = midY + sy * r;
  final path = Path()
    ..moveTo(sx > 0 ? x + w : x, midY)
    ..lineTo(ocx, midY)
    ..arcToPoint(Offset(midX, ocy), radius: Radius.circular(r), clockwise: sx * sy < 0)
    ..lineTo(midX, sy > 0 ? y + h : y);
  canvas.save();
  canvas.scale(px);
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = light
        ..color = color);
  canvas.restore();
}

void _drawBox(int cp, int x, int y, int w, int h, _Fill fill) {
  final arms = _boxArms[cp - 0x2500];
  final up = (arms >> 6) & 3, right = (arms >> 4) & 3, down = (arms >> 2) & 3, left = arms & 3;
  final light = math.max(1, (math.min(w, h) + 4) ~/ 9);
  final heavy = light * 2;
  int thick(int weight) => switch (weight) { 0 => 0, 1 => light, 2 => heavy, _ => light * 3 };
  final cx = x + (w - light) ~/ 2; // left edge of a light vertical stroke
  final cy = y + (h - light) ~/ 2; // top edge of a light horizontal stroke
  // How far the horizontal / vertical arms must reach past the centre so
  // they meet the perpendicular strokes without gaps.
  final vReach = math.max(thick(up), thick(down));
  final hReach = math.max(thick(left), thick(right));

  void hArm(int x0, int x1, int weight) {
    final t = thick(weight);
    final top = cy + light ~/ 2 - t ~/ 2;
    if (weight == 3) {
      fill(x0.toDouble(), top.toDouble(), (x1 - x0).toDouble(), light.toDouble(), 1);
      fill(x0.toDouble(), (top + 2 * light).toDouble(), (x1 - x0).toDouble(), light.toDouble(), 1);
    } else {
      fill(x0.toDouble(), top.toDouble(), (x1 - x0).toDouble(), t.toDouble(), 1);
    }
  }

  void vArm(int y0, int y1, int weight) {
    final t = thick(weight);
    final lft = cx + light ~/ 2 - t ~/ 2;
    if (weight == 3) {
      fill(lft.toDouble(), y0.toDouble(), light.toDouble(), (y1 - y0).toDouble(), 1);
      fill((lft + 2 * light).toDouble(), y0.toDouble(), light.toDouble(), (y1 - y0).toDouble(), 1);
    } else {
      fill(lft.toDouble(), y0.toDouble(), t.toDouble(), (y1 - y0).toDouble(), 1);
    }
  }

  final midX = cx + light ~/ 2;
  final midY = cy + light ~/ 2;
  if (left > 0) hArm(x, midX + (vReach > 0 ? (vReach + 1) ~/ 2 : (light + 1) ~/ 2), left);
  if (right > 0) hArm(midX - (vReach > 0 ? vReach ~/ 2 : light ~/ 2), x + w, right);
  if (up > 0) vArm(y, midY + (hReach > 0 ? (hReach + 1) ~/ 2 : (light + 1) ~/ 2), up);
  if (down > 0) vArm(midY - (hReach > 0 ? hReach ~/ 2 : light ~/ 2), y + h, down);
}

void _drawBlock(int cp, int x, int y, int w, int h, _Fill fill) {
  final hw = w ~/ 2, hh = h ~/ 2;
  void f(int fx, int fy, int fw, int fh, [double a = 1]) =>
      fill(fx.toDouble(), fy.toDouble(), fw.toDouble(), fh.toDouble(), a);
  void quad(bool ul, bool ur, bool ll, bool lr) {
    if (ul) f(x, y, hw, hh);
    if (ur) f(x + hw, y, w - hw, hh);
    if (ll) f(x, y + hh, hw, h - hh);
    if (lr) f(x + hw, y + hh, w - hw, h - hh);
  }

  if (cp == 0x2580) {
    f(x, y, w, hh); // upper half
  } else if (cp >= 0x2581 && cp <= 0x2587) {
    final eh = h * (cp - 0x2580) ~/ 8; // lower n/8
    f(x, y + h - eh, w, eh);
  } else if (cp == 0x2588) {
    f(x, y, w, h); // full block
  } else if (cp >= 0x2589 && cp <= 0x258F) {
    f(x, y, w * (0x2590 - cp) ~/ 8, h); // left n/8
  } else {
    switch (cp) {
      case 0x2590:
        f(x + hw, y, w - hw, h); // right half
      case 0x2591:
        f(x, y, w, h, 0.25); // light shade
      case 0x2592:
        f(x, y, w, h, 0.5); // medium shade
      case 0x2593:
        f(x, y, w, h, 0.75); // dark shade
      case 0x2594:
        f(x, y, w, math.max(1, h ~/ 8)); // upper 1/8
      case 0x2595:
        f(x + w - math.max(1, w ~/ 8), y, math.max(1, w ~/ 8), h);
      case 0x2596:
        quad(false, false, true, false);
      case 0x2597:
        quad(false, false, false, true);
      case 0x2598:
        quad(true, false, false, false);
      case 0x2599:
        quad(true, false, true, true);
      case 0x259A:
        quad(true, false, false, true);
      case 0x259B:
        quad(true, true, true, false);
      case 0x259C:
        quad(true, true, false, true);
      case 0x259D:
        quad(false, true, false, false);
      case 0x259E:
        quad(false, true, true, false);
      case 0x259F:
        quad(false, true, true, true);
    }
  }
}
