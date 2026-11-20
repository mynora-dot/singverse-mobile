import 'package:flutter_test/flutter_test.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:singverse_mobile/features/player/player_lyrics.dart';

void main() {
  final song = Song({
    'id': 'all-night',
    'title': 'All Night',
    'artists': ['少女时代'],
  });

  test('plain lyrics retain their text without inventing timestamps', () {
    for (final format in ['text', 'lrc']) {
      final source = parseText(
        format,
        '\uFEFF[ti:测试歌曲]\r\n[ar:测试歌手]\r\n\r\n第一句歌词\r\n第二句歌词\r\n',
      );
      expect(source.map((line) => line.text), ['第一句歌词', '第二句歌词']);
      expect(source.every((line) => line.startMs == null), isTrue);
      expect(source.every((line) => line.endMs == null), isTrue);
    }
    expect(parseText('text', ' \n[ti:测试歌曲]\n[offset:0]\n'), isEmpty);
  });

  test('timed tracks take priority over a plain lyric fallback', () {
    final display = PlayerLyrics.fromTracks([
      {'format': 'text', 'text': '纯文本歌词'},
      {'format': 'srt', 'text': '1\n00:00:02,000 --> 00:00:05,000\n同步歌词'},
    ], song);
    expect(display.lines.single.text, '同步歌词');
    expect(display.lines.single.startMs, 2000);
    expect(display.lines.single.endMs, 5000);
  });

  test('empty timed tracks do not hide plain lyrics and opening credits', () {
    final display = PlayerLyrics.fromTracks([
      {'format': 'lrc', 'text': '[00:00.00]'},
      {'format': 'text', 'text': '作词：词作者\n第一句歌词\n第二句歌词'},
    ], song);
    expect(display.credits, [('作词', '词作者')]);
    expect(display.lines.map((line) => line.text), ['第一句歌词', '第二句歌词']);
    expect(display.lines.every((line) => line.startMs == null), isTrue);
    expect(PlayerLyrics.fromTracks([], song).lines, isEmpty);
  });

  test('comma LRC timestamps remain synchronized', () {
    final lines = parseText('lrc', '[00:01,200]第一句歌词');
    expect(lines.single.startMs, 1200);
    expect(lines.single.text, '第一句歌词');
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
