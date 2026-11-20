typedef Json = Map<String, dynamic>;

class Song {
  Song(this.data);
  final Json data;
  String get id => data['id'] as String;
  bool get available => data['available'] != false;
  String get title => data['title'] as String? ?? '未命名歌曲';
  String get artist => (data['artists'] as List? ?? []).join(' / ');
  String? get cover => data['coverPath'] as String?;
  String get mediaType => data['mediaType'] as String? ?? 'UNKNOWN';
  String get format => data['format'] as String? ?? '';
  String get source => data['sourceName'] as String? ?? '';
  String get version =>
      const {
        'ORIGINAL': '原唱版本',
        'ACCOMPANIMENT': '伴奏版本',
        'INSTRUMENTAL': '纯音乐',
        'DUET': '合唱版本',
        'KARAOKE': '卡拉 OK',
      }[data['version']] ??
      '版本待确认';
  String get description => [
    artist.isEmpty ? '歌手未知' : artist,
    if (format.isNotEmpty) format,
    version,
  ].join(' · ');
}

class TextLine {
  const TextLine(this.startMs, this.endMs, this.text);
  const TextLine.untimed(this.text) : startMs = null, endMs = null;

  /// Null for plain lyrics that have no media timeline.
  final int? startMs;
  final int? endMs;
  final String text;
}

List<TextLine> parseText(String format, String text) {
  format = format.toLowerCase();
  text = text
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll(RegExp(r'\r\n?'), '\n');
  if (format == 'text') {
    final metadata = RegExp(
      r'^\[(?:ti|ar|al|by|offset|length):.*\]$',
      caseSensitive: false,
    );
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !metadata.hasMatch(line))
        .map(TextLine.untimed)
        .toList();
  }
  final result = <TextLine>[];
  if (format == 'lrc') {
    final stamp = RegExp(r'\[(\d+):(\d{2})(?:[.,](\d{1,3}))?\]');
    final offset =
        int.tryParse(
          RegExp(
                r'\[offset:([+-]?\d+)\]',
                caseSensitive: false,
              ).firstMatch(text)?.group(1) ??
              '',
        ) ??
        0;
    for (final line in text.split('\n')) {
      final matches = stamp.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final words = line.substring(matches.last.end).trim();
      for (final m in matches) {
        result.add(
          TextLine(
            int.parse(m[1]!) * 60000 +
                int.parse(m[2]!) * 1000 +
                int.parse((m[3] ?? '').padRight(3, '0')) -
                offset,
            null,
            words,
          ),
        );
      }
    }
    if (result.isEmpty) return parseText('text', text);
  } else {
    int time(String v) {
      final parts = v.replaceAll(',', '.').split(':');
      double seconds = 0;
      for (final part in parts) {
        seconds = seconds * 60 + double.parse(part);
      }
      return (seconds * 1000).round();
    }

    final expression = RegExp(
      r'((?:\d{2,}:)?\d{2}:\d{2}[.,]\d{3})\s*-->\s*((?:\d{2,}:)?\d{2}:\d{2}[.,]\d{3})[^\n]*\n([\s\S]*?)(?=\n\s*\n|$)',
    );
    for (final match in expression.allMatches(text.replaceAll('\r', ''))) {
      result.add(
        TextLine(
          time(match[1]!),
          time(match[2]!),
          match[3]!.replaceAll(RegExp('<[^>]*>'), '').trim(),
        ),
      );
    }
  }
  result.sort((a, b) => a.startMs!.compareTo(b.startMs!));
  return result;
}

String durationLabel(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
