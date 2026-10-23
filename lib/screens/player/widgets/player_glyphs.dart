import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PlayerGlyphType {
  back,
  lock,
  lockOpen,
  aspectFill,
  aspectFit,
  fullscreenEnter,
  fullscreenExit,
  volume,
  volumeMute,
  audioTrack,
  subtitle,
  playlist,
  previous,
  next,
  seekBack,
  seekForward,
  play,
  pause,
  wifi,
  cellular,
  ethernet,
}

class PlayerGlyph extends StatelessWidget {
  final PlayerGlyphType type;
  final double size;
  final Color color;

  const PlayerGlyph(
    this.type, {
    super.key,
    this.size = 24,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PlayerGlyphPainter(type, color),
    );
  }
}

class _PlayerGlyphPainter extends CustomPainter {
  final PlayerGlyphType type;
  final Color color;

  _PlayerGlyphPainter(this.type, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);
    void polyline(List<Offset> points) =>
        canvas.drawPath(Path()..addPolygon(points, false), stroke);
    void solid(List<Offset> points) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, stroke);
      canvas.drawPath(path, fill);
    }

    void outline(List<Offset> points) =>
        canvas.drawPath(Path()..addPolygon(points, true), stroke);

    void mirrored(void Function() draw) {
      canvas.save();
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
      draw();
      canvas.restore();
    }

    void lockBody() {
      canvas.drawRRect(
        RRect.fromLTRBR(4, 10.5, 20, 21, const Radius.circular(2.5)),
        stroke,
      );
      line(12, 14.5, 12, 17);
    }

    void speaker() => solid(const [
      Offset(4, 9.5),
      Offset(7.5, 9.5),
      Offset(12, 5.5),
      Offset(12, 18.5),
      Offset(7.5, 14.5),
      Offset(4, 14.5),
    ]);

    void previous() {
      canvas.drawRRect(
        RRect.fromLTRBR(3.5, 3.5, 6.5, 20.5, const Radius.circular(1.5)),
        fill,
      );
      solid(const [Offset(19.5, 4.5), Offset(9.5, 12), Offset(19.5, 19.5)]);
    }

    void seekBack() {
      const center = Offset(12, 13);
      const radius = 9.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 5 / 3,
        false,
        stroke,
      );
      const tipY = 13 - radius;
      solid(const [
        Offset(8.5, tipY),
        Offset(12, tipY - 2.5),
        Offset(12, tipY + 2.5),
      ]);
    }

    switch (type) {
      case PlayerGlyphType.back:
        polyline(const [Offset(14.5, 5), Offset(7.5, 12), Offset(14.5, 19)]);
      case PlayerGlyphType.lock:
        lockBody();
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 10.5)
            ..lineTo(7.5, 7.5)
            ..arcToPoint(
              const Offset(16.5, 7.5),
              radius: const Radius.circular(4.5),
            )
            ..lineTo(16.5, 10.5),
          stroke,
        );
      case PlayerGlyphType.lockOpen:
        lockBody();
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 10.5)
            ..lineTo(7.5, 7.5)
            ..arcToPoint(
              const Offset(16.3, 6.4),
              radius: const Radius.circular(4.5),
            ),
          stroke,
        );
      case PlayerGlyphType.aspectFill:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 21, 21, const Radius.circular(3.5)),
          stroke,
        );
        line(8, 16, 16, 8);
        polyline(const [Offset(12, 8), Offset(16, 8), Offset(16, 12)]);
        polyline(const [Offset(8, 12), Offset(8, 16), Offset(12, 16)]);
      case PlayerGlyphType.aspectFit:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 21, 21, const Radius.circular(3.5)),
          stroke,
        );
        line(17, 7, 13, 11);
        polyline(const [Offset(13, 7.5), Offset(13, 11), Offset(16.5, 11)]);
        line(7, 17, 11, 13);
        polyline(const [Offset(7.5, 13), Offset(11, 13), Offset(11, 16.5)]);
      case PlayerGlyphType.fullscreenEnter:
        polyline(const [Offset(3, 8), Offset(3, 3), Offset(8, 3)]);
        polyline(const [Offset(16, 3), Offset(21, 3), Offset(21, 8)]);
        polyline(const [Offset(21, 16), Offset(21, 21), Offset(16, 21)]);
        polyline(const [Offset(8, 21), Offset(3, 21), Offset(3, 16)]);
      case PlayerGlyphType.fullscreenExit:
        polyline(const [Offset(3, 8), Offset(8, 8), Offset(8, 3)]);
        polyline(const [Offset(16, 3), Offset(16, 8), Offset(21, 8)]);
        polyline(const [Offset(21, 16), Offset(16, 16), Offset(16, 21)]);
        polyline(const [Offset(8, 21), Offset(8, 16), Offset(3, 16)]);
      case PlayerGlyphType.volume:
        speaker();
        const center = Offset(12, 12);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 4),
          -math.pi / 4,
          math.pi / 2,
          false,
          stroke,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 8),
          -math.pi * 5 / 18,
          math.pi * 5 / 9,
          false,
          stroke,
        );
      case PlayerGlyphType.volumeMute:
        speaker();
        line(15.5, 9.5, 20.5, 14.5);
        line(20.5, 9.5, 15.5, 14.5);
      case PlayerGlyphType.audioTrack:
        const bars = [
          (3.0, 3.0),
          (7.5, 6.0),
          (12.0, 9.0),
          (16.5, 6.0),
          (21.0, 3.0),
        ];
        for (final (x, half) in bars) {
          line(x, 12 - half, x, 12 + half);
        }
      case PlayerGlyphType.subtitle:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 21, 21, const Radius.circular(3.5)),
          stroke,
        );
        line(7, 10, 9, 10);
        line(12, 10, 17, 10);
        line(7, 15, 13, 15);
        line(16, 15, 17, 15);
      case PlayerGlyphType.playlist:
        solid(const [Offset(3, 2.5), Offset(8, 5.75), Offset(3, 9)]);
        line(12, 5.75, 21, 5.75);
        line(3, 13, 21, 13);
        line(3, 20.5, 21, 20.5);
      case PlayerGlyphType.previous:
        previous();
      case PlayerGlyphType.next:
        mirrored(previous);
      case PlayerGlyphType.seekBack:
        seekBack();
      case PlayerGlyphType.seekForward:
        mirrored(seekBack);
      case PlayerGlyphType.play:
        solid(const [Offset(6, 3), Offset(20, 12), Offset(6, 21)]);
      case PlayerGlyphType.wifi:
        const center = Offset(12, 19.5);
        for (final radius in const [5.0, 10.0, 15.0]) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius),
            -math.pi * 3 / 4,
            math.pi / 2,
            false,
            stroke,
          );
        }
        canvas.drawCircle(center, 1.8, fill);
      case PlayerGlyphType.cellular:
        for (final (x, top) in const [
          (3.0, 15.0),
          (8.5, 11.0),
          (14.0, 7.0),
          (19.5, 3.0),
        ]) {
          canvas.drawRRect(
            RRect.fromLTRBR(x, top, x + 3, 21, const Radius.circular(1)),
            fill,
          );
        }
      case PlayerGlyphType.ethernet:
        outline(const [
          Offset(3, 9),
          Offset(7.5, 9),
          Offset(7.5, 5),
          Offset(16.5, 5),
          Offset(16.5, 9),
          Offset(21, 9),
          Offset(21, 20),
          Offset(3, 20),
        ]);
        line(9, 14, 9, 16.5);
        line(12, 14, 12, 16.5);
        line(15, 14, 15, 16.5);
      case PlayerGlyphType.pause:
        canvas.drawRRect(
          RRect.fromLTRBR(5, 2, 10.5, 22, const Radius.circular(1.5)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(13.5, 2, 19, 22, const Radius.circular(1.5)),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_PlayerGlyphPainter old) =>
      old.type != type || old.color != color;
}
