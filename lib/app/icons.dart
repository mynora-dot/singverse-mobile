import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Custom Apple SF Symbols-inspired crisp vector icons with rounded caps,
/// balanced optical weight, and smooth geometry to replace coarse Material icons.
enum AppGlyph {
  scan,
  person,
  sliders,
  artist,
  grid,
  playlist,
  play,
  pause,
  mic,
  waveform,
  sparkles,
  search,
}

class AppVectorIcon extends StatelessWidget {
  const AppVectorIcon(
    this.glyph, {
    super.key,
    this.size = 20,
    this.color,
    this.filled = false,
    this.strokeWidth,
  });

  final AppGlyph glyph;
  final double size;
  final Color? color;
  final bool filled;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size;
    final resolvedColor =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: resolvedSize,
      child: CustomPaint(
        painter: _AppGlyphPainter(
          glyph: glyph,
          color: resolvedColor,
          filled: filled,
          strokeWidth: strokeWidth ?? (resolvedSize >= 24 ? 2.1 : 1.85),
        ),
      ),
    );
  }
}

class _AppGlyphPainter extends CustomPainter {
  const _AppGlyphPainter({
    required this.glyph,
    required this.color,
    required this.filled,
    required this.strokeWidth,
  });

  final AppGlyph glyph;
  final Color color;
  final bool filled;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(s, s);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case AppGlyph.scan:
        // Apple Camera / QR Viewfinder brackets + subtle center scan bar
        const r = 2.6;
        final path = Path()
          // Top-left bracket
          ..moveTo(3.5, 8.2)
          ..lineTo(3.5, 6.1)
          ..arcToPoint(const Offset(6.1, 3.5), radius: const Radius.circular(r))
          ..lineTo(8.2, 3.5)
          // Top-right bracket
          ..moveTo(15.8, 3.5)
          ..lineTo(17.9, 3.5)
          ..arcToPoint(
            const Offset(20.5, 6.1),
            radius: const Radius.circular(r),
          )
          ..lineTo(20.5, 8.2)
          // Bottom-right bracket
          ..moveTo(20.5, 15.8)
          ..lineTo(20.5, 17.9)
          ..arcToPoint(
            const Offset(17.9, 20.5),
            radius: const Radius.circular(r),
          )
          ..lineTo(15.8, 20.5)
          // Bottom-left bracket
          ..moveTo(8.2, 20.5)
          ..lineTo(6.1, 20.5)
          ..arcToPoint(
            const Offset(3.5, 17.9),
            radius: const Radius.circular(r),
          )
          ..lineTo(3.5, 15.8);
        canvas.drawPath(path, stroke);
        // Inner horizontal scan beam
        canvas.drawLine(
          const Offset(7.2, 12.0),
          const Offset(16.8, 12.0),
          stroke,
        );

      case AppGlyph.person:
      case AppGlyph.artist:
        // Apple SF person.crop / artist silhouette with refined proportions
        canvas.drawCircle(const Offset(12, 7.8), 3.6, filled ? fill : stroke);
        final body = Path()
          ..moveTo(5.2, 19.6)
          ..cubicTo(5.8, 15.6, 8.5, 14.1, 12.0, 14.1)
          ..cubicTo(15.5, 14.1, 18.2, 15.6, 18.8, 19.6);
        if (filled) {
          body.close();
          canvas.drawPath(body, fill);
        } else {
          canvas.drawPath(body, stroke);
        }
        if (glyph == AppGlyph.artist) {
          // Small musical sparkle badge on top-right for Artist
          final note = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = (strokeWidth * .82) / s
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            const Offset(18.2, 5.2),
            const Offset(18.2, 9.6),
            note,
          );
          canvas.drawLine(
            const Offset(18.2, 5.2),
            const Offset(20.4, 4.5),
            note,
          );
          canvas.drawCircle(const Offset(17.2, 9.8), 1.25, fill);
        }

      case AppGlyph.sliders:
        // Apple SF slider.horizontal.3 with crisp pill knobs
        final railPaint = Paint()
          ..color = color.withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeWidth * .92) / s
          ..strokeCap = StrokeCap.round;
        // Top line (knob on left-mid)
        canvas.drawLine(
          const Offset(4, 6.5),
          const Offset(7.2, 6.5),
          railPaint,
        );
        canvas.drawLine(
          const Offset(11.6, 6.5),
          const Offset(20, 6.5),
          railPaint,
        );
        canvas.drawCircle(const Offset(9.4, 6.5), 2.1, stroke);
        // Middle line (knob on right-mid)
        canvas.drawLine(const Offset(4, 12), const Offset(12.8, 12), railPaint);
        canvas.drawLine(
          const Offset(17.2, 12),
          const Offset(20, 12),
          railPaint,
        );
        canvas.drawCircle(const Offset(15.0, 12), 2.1, stroke);
        // Bottom line (knob on left-mid)
        canvas.drawLine(
          const Offset(4, 17.5),
          const Offset(8.2, 17.5),
          railPaint,
        );
        canvas.drawLine(
          const Offset(12.6, 17.5),
          const Offset(20, 17.5),
          railPaint,
        );
        canvas.drawCircle(const Offset(10.4, 17.5), 2.1, stroke);

      case AppGlyph.grid:
        // Apple SF square.grid.2x2 with squircle corners
        for (final rect in const [
          Rect.fromLTWH(3.6, 3.6, 7.2, 7.2),
          Rect.fromLTWH(13.2, 3.6, 7.2, 7.2),
          Rect.fromLTWH(3.6, 13.2, 7.2, 7.2),
          Rect.fromLTWH(13.2, 13.2, 7.2, 7.2),
        ]) {
          final rrect = RRect.fromRectAndRadius(
            rect,
            const Radius.circular(2.4),
          );
          canvas.drawRRect(rrect, filled ? fill : stroke);
        }

      case AppGlyph.playlist:
        // Apple Music music.note.list: three clean horizontal bars + beamed eighth note
        canvas.drawLine(
          const Offset(3.5, 6.5),
          const Offset(13.5, 6.5),
          stroke,
        );
        canvas.drawLine(
          const Offset(3.5, 11.5),
          const Offset(11.5, 11.5),
          stroke,
        );
        canvas.drawLine(
          const Offset(3.5, 16.5),
          const Offset(10.0, 16.5),
          stroke,
        );
        final stem = Path()
          ..moveTo(16.6, 16.8)
          ..lineTo(16.6, 6.2)
          ..lineTo(20.6, 5.0)
          ..lineTo(20.6, 8.2)
          ..lineTo(16.6, 9.4);
        canvas.drawPath(stem, stroke);
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(14.8, 17.2),
            width: 4.2,
            height: 3.3,
          ),
          fill,
        );

      case AppGlyph.play:
        // Smooth rounded triangle (Apple Music play.fill)
        final path = Path()
          ..moveTo(7.4, 5.2)
          ..quadraticBezierTo(7.4, 4.0, 8.5, 4.6)
          ..lineTo(18.6, 10.9)
          ..quadraticBezierTo(19.8, 11.65, 18.6, 12.4)
          ..lineTo(8.5, 18.7)
          ..quadraticBezierTo(7.4, 19.3, 7.4, 18.1)
          ..close();
        canvas.drawPath(path, fill);

      case AppGlyph.pause:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(6.5, 5.0, 3.8, 14.0),
            const Radius.circular(1.6),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(13.7, 5.0, 3.8, 14.0),
            const Radius.circular(1.6),
          ),
          fill,
        );

      case AppGlyph.mic:
        // Apple SF music.mic / mic.fill
        final capsule = RRect.fromRectAndRadius(
          const Rect.fromLTWH(9.0, 3.4, 6.0, 10.2),
          const Radius.circular(3.0),
        );
        canvas.drawRRect(capsule, filled ? fill : stroke);
        final cradle = Path()
          ..addArc(const Rect.fromLTWH(5.6, 7.2, 12.8, 9.8), 0, math.pi);
        canvas.drawPath(cradle, stroke);
        canvas.drawLine(const Offset(12, 17.2), const Offset(12, 20.4), stroke);
        canvas.drawLine(
          const Offset(8.8, 20.4),
          const Offset(15.2, 20.4),
          stroke,
        );

      case AppGlyph.waveform:
        // Apple SF waveform (5 symmetric rounded acoustic bars)
        final barPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = (filled ? 2.35 : 2.0) / s
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          const Offset(4.2, 10.2),
          const Offset(4.2, 13.8),
          barPaint,
        );
        canvas.drawLine(
          const Offset(8.1, 7.0),
          const Offset(8.1, 17.0),
          barPaint,
        );
        canvas.drawLine(
          const Offset(12.0, 4.0),
          const Offset(12.0, 20.0),
          barPaint,
        );
        canvas.drawLine(
          const Offset(15.9, 6.5),
          const Offset(15.9, 17.5),
          barPaint,
        );
        canvas.drawLine(
          const Offset(19.8, 9.6),
          const Offset(19.8, 14.4),
          barPaint,
        );

      case AppGlyph.sparkles:
        // Apple SF sparkles four-point star
        final star = Path()
          ..moveTo(12, 2.5)
          ..quadraticBezierTo(12.6, 9.4, 14.6, 11.4)
          ..quadraticBezierTo(16.6, 12.0, 21.5, 12.0)
          ..quadraticBezierTo(16.6, 12.0, 14.6, 12.6)
          ..quadraticBezierTo(12.6, 14.6, 12, 21.5)
          ..quadraticBezierTo(11.4, 14.6, 9.4, 12.6)
          ..quadraticBezierTo(7.4, 12.0, 2.5, 12.0)
          ..quadraticBezierTo(7.4, 12.0, 9.4, 11.4)
          ..quadraticBezierTo(11.4, 9.4, 12, 2.5)
          ..close();
        canvas.drawPath(star, fill);

      case AppGlyph.search:
        canvas.drawCircle(const Offset(10.6, 10.6), 6.2, stroke);
        canvas.drawLine(
          const Offset(15.2, 15.2),
          const Offset(19.8, 19.8),
          stroke,
        );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.filled != filled ||
      oldDelegate.strokeWidth != strokeWidth;
}
