import '../../core/models.dart';

/// Display-only separation: the original text track and timestamps stay intact.
class PlayerLyrics {
  const PlayerLyrics(this.lines, this.credits);

  final List<TextLine> lines;
  final List<(String, String)> credits;

  factory PlayerLyrics.fromLines(List<TextLine> source, Song song) {
    final lines = <TextLine>[];
    final credits = <(String, String)>[];
    final credit = RegExp(r'^(作词|作曲|编曲|词|曲)\s*[:：]\s*(\S.*)$');
    final headings = {
      song.title,
      song.artist,
      '${song.title} - ${song.artist}',
    };
    var intro = true;
    for (final line in source) {
      final text = line.text.trim();
      final match = intro ? credit.firstMatch(text) : null;
      if (match != null) {
        final label = switch (match[1]) {
          '词' => '作词',
          '曲' => '作曲',
          _ => match[1]!,
        };
        final value = (label, match[2]!.trim());
        if (!credits.contains(value)) credits.add(value);
      } else {
        lines.add(line);
        if (text.isNotEmpty && !headings.contains(text)) intro = false;
      }
    }
    return PlayerLyrics(lines, credits);
  }
}
