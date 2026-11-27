import '../../core/models.dart';

/// Display-only separation: the original text track and timestamps stay intact.
class PlayerLyrics {
  const PlayerLyrics(this.lines, this.credits);

  final List<TextLine> lines;
  final List<(String, String)> credits;

  factory PlayerLyrics.fromTracks(Iterable<Json> tracks, Song song) {
    List<TextLine>? untimed;
    for (final track in tracks) {
      final lines = parseText(
        track['format'] as String,
        track['text'] as String,
      );
      if (!lines.any((line) => line.text.trim().isNotEmpty)) continue;
      if (lines.any((line) => line.startMs != null)) {
        return PlayerLyrics.fromLines(lines, song);
      }
      untimed ??= lines;
    }
    return PlayerLyrics.fromLines(untimed ?? [], song);
  }

  static String _normalizeHeading(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\(\)（）\[\]【】·•\-—–_/／:：]+'), '');

  static bool isOpeningHeading(String text, Song song) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final headings = {
      song.title.trim(),
      song.artist.trim(),
      '${song.title} - ${song.artist}'.trim(),
    };
    if (headings.contains(trimmed)) return true;
    final normalizedLine = _normalizeHeading(trimmed);
    final normalizedTitle = _normalizeHeading(song.title);
    if (normalizedTitle.isEmpty ||
        !normalizedLine.startsWith(normalizedTitle)) {
      return false;
    }
    final remainder = normalizedLine.substring(normalizedTitle.length);
    if (remainder.isEmpty ||
        remainder == 'live' ||
        remainder == '现场' ||
        remainder == '伴奏') {
      return true;
    }
    if (trimmed.contains('-') ||
        trimmed.contains('—') ||
        trimmed.contains('–')) {
      return true;
    }
    final rawArtists = song.data['artists'];
    final artists = rawArtists is List
        ? rawArtists.whereType<String>()
        : [song.artist];
    for (final artist in artists) {
      final normalizedArtist = _normalizeHeading(artist);
      if (normalizedArtist.isNotEmpty &&
          normalizedLine.contains(normalizedArtist)) {
        return true;
      }
    }
    return false;
  }

  factory PlayerLyrics.fromLines(List<TextLine> source, Song song) {
    final lines = <TextLine>[];
    final credits = <(String, String)>[];
    final credit = RegExp(
      r'^(作词|作曲|编曲|制作人|制作|出品人|出品|演唱|原唱|和声|合声|混音|缩混|母带|录音|监制|统筹|OP|SP|词|曲)\s*[:：]\s*(\S.*)$',
      caseSensitive: false,
    );
    var intro = true;
    for (final line in source) {
      final text = line.text.trim();
      final match = intro ? credit.firstMatch(text) : null;
      if (match != null) {
        final rawLabel = match[1]!.trim();
        final label = switch (rawLabel.toUpperCase()) {
          '词' => '作词',
          '曲' => '作曲',
          'OP' => 'OP',
          'SP' => 'SP',
          _ => rawLabel,
        };
        final value = (label, match[2]!.trim());
        if (!credits.contains(value)) credits.add(value);
      } else {
        lines.add(line);
        if (text.isNotEmpty && !isOpeningHeading(text, song)) intro = false;
      }
    }
    return PlayerLyrics(lines, credits);
  }
}
