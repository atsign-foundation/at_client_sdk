import 'package:flutter/material.dart';

class RPSCustomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    path.moveTo(size.width * 0.4984829, size.height * 0.5929065);
    path.arcToPoint(Offset(size.width * 0.7102083, size.height * 0.4184499),
        radius:
            Radius.elliptical(size.width * 0.2113654, size.height * 0.1741599),
        rotation: 0,
        largeArc: false,
        clockwise: false);
    path.arcToPoint(Offset(size.width * 0.4984829, size.height * 0.2377643),
        radius:
            Radius.elliptical(size.width * 0.2178452, size.height * 0.1794991),
        rotation: 0,
        largeArc: false,
        clockwise: false);
    path.arcToPoint(Offset(size.width * 0.2867575, size.height * 0.4122209),
        radius:
            Radius.elliptical(size.width * 0.2113654, size.height * 0.1741599),
        rotation: 0,
        largeArc: false,
        clockwise: false);
    path.arcToPoint(Offset(size.width * 0.4984829, size.height * 0.5929065),
        radius:
            Radius.elliptical(size.width * 0.2231936, size.height * 0.1839061),
        rotation: 0,
        largeArc: false,
        clockwise: false);
    path.close();
    path.moveTo(size.width * 0.1430702, size.height * 0.1193695);
    path.arcToPoint(Offset(size.width * 0.8536899, size.height * 0.7050299),
        radius:
            Radius.elliptical(size.width * 0.5025971, size.height * 0.4141277),
        rotation: 0,
        largeArc: true,
        clockwise: true);
    path.lineTo(size.width * 0.4984829, size.height * 0.9978813);
    path.lineTo(size.width * 0.1430702, size.height * 0.7050299);
    path.arcToPoint(Offset(size.width * 0.1430702, size.height * 0.1193695),
        radius:
            Radius.elliptical(size.width * 0.5163281, size.height * 0.4254418),
        rotation: 0,
        largeArc: false,
        clockwise: true);
    path.close();

    var paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xfffc7a30).withOpacity(1.0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
