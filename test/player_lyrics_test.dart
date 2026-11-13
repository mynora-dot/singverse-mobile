import 'package:flutter_test/flutter_test.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/player/player_lyrics.dart';

void main() {
  final song = Song({
    'id': 'all-night',
    'title': 'All Night',
    'artists': ['少女时代'],
  });

  test(
    'opening credits move to information while lyric timings stay intact',
    () {
      final source = parseText('lrc', '''
[00:00.00]All Night - 少女时代
[00:01.00]词：Kenzie
[00:02.00]曲：Ollipop / Daniel Caesar
[00:03.00]编曲：Ollipop / Caesar & Loui
[00:04.00]I like to party
[00:08.00]아 알고 있잖아
''');
      final display = PlayerLyrics.fromLines(source, song);
      expect(display.credits, [
        ('作词', 'Kenzie'),
        ('作曲', 'Ollipop / Daniel Caesar'),
        ('编曲', 'Ollipop / Caesar & Loui'),
      ]);
      expect(display.lines.map((l) => l.text), [
        'All Night - 少女时代',
        'I like to party',
        '아 알고 있잖아',
      ]);
      expect(identical(display.lines[1], source[4]), isTrue);
      expect(display.lines[1].startMs, 4000);
      expect(source, hasLength(6));
    },
  );

  test(
    'ordinary lyrics and credit-like lines after the first verse survive',
    () {
      final source = parseText('srt', '''
1
00:00:01,000 --> 00:00:04,000
从这里开始唱

2
00:00:05,000 --> 00:00:08,000
词：也可以是一句歌词
''');
      final display = PlayerLyrics.fromLines(source, song);
      expect(display.credits, isEmpty);
      expect(display.lines, source);
      expect(display.lines.last.endMs, 8000);
    },
  );
}
