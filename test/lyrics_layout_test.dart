import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/player/player_page.dart';

class _CountingTextScaler extends TextScaler {
  const _CountingTextScaler(this.onScale);
  final VoidCallback onScale;

  @override
  double scale(double fontSize) {
    onScale();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}

void main() {
  testWidgets(
    'progress reuses lyric geometry while track and layout changes remeasure it',
    (tester) async {
      var scaleCalls = 0;
      final scaler = _CountingTextScaler(() => scaleCalls++);
      final lines = List.generate(
        120,
        (index) => TextLine(index * 2000, null, '第 $index 句：熟悉的旋律还在身边'),
      );
      Future<void> show({
        int position = 2000,
        double width = 360,
        bool stage = false,
        List<TextLine>? track,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: scaler),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    height: 240,
                    child: LyricsView(
                      lines: track ?? lines,
                      positionMs: position,
                      senior: false,
                      stage: stage,
                      enabled: true,
                      onSeek: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      expect(scaleCalls, greaterThanOrEqualTo(lines.length));
      scaleCalls = 0;
      await show(position: 2400);
      expect(
        scaleCalls,
        lessThan(lines.length),
        reason: 'A progress tick must not measure every line in the song.',
      );
      for (final change in ['width', 'style', 'track']) {
        scaleCalls = 0;
        await show(
          width: 280,
          stage: change != 'width',
          track: change == 'track'
              ? [
                  ...lines.take(1),
                  const TextLine(2000, null, '切换歌词后，这一句需要完整换行显示，时间戳保持相同'),
                  ...lines.skip(2),
                ]
              : null,
        );
        expect(scaleCalls, greaterThanOrEqualTo(lines.length), reason: change);
        final active = find.byKey(const ValueKey('lyrics-line-1'));
        expect(active, findsOneWidget);
        final text = tester.getRect(active);
        final viewport = tester.getRect(
          find.byKey(const ValueKey('lyrics-viewport')),
        );
        expect(text.top, greaterThanOrEqualTo(viewport.top));
        expect(text.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
