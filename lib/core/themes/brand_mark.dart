import 'package:flutter/material.dart';

/// Vector brand mark (rounded tile + "N" glyph). Colors follow the active
/// theme so the logo always matches the selected palette — no image assets.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final hsl = HSLColor.fromColor(primary);
    final deep = hsl
        .withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0))
        .toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, deep],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: CustomPaint(painter: _NPainter()),
    );
  }
}

class _NPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(w * 0.30, h * 0.72)
      ..lineTo(w * 0.30, h * 0.28)
      ..lineTo(w * 0.70, h * 0.72)
      ..lineTo(w * 0.70, h * 0.28);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
