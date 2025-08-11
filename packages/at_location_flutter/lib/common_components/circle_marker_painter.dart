import 'package:flutter/material.dart';

class CircleMarkerPainter extends CustomPainter {
  Color? color;
  PaintingStyle? paintingStyle;
  CircleMarkerPainter({this.color, this.paintingStyle});
  final _paint = Paint()
    ..color = Colors.orange
    ..strokeWidth = 5
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    _paint.color = color ?? Colors.orange;
    _paint.style = paintingStyle ?? PaintingStyle.stroke;
    canvas.drawOval(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
