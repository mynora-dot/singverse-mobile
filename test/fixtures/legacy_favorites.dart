import 'dart:convert';

import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/core/models.dart';

// Old local favorites survive upgrades but are never read or written by the
// application. Fixtures still need them to verify isolation from NAS favorites.
extension LegacyFavoritesFixture on LocalStore {
  Future<List<Song>> favorites(String server) async =>
      (await db.query(
            'personal_song',
            where: 'instance_id = ? AND favorite = 1',
            whereArgs: [server],
            orderBy: 'song_id',
          ))
          .map((row) => Song(jsonDecode(row['snapshot']! as String) as Json))
          .toList();

  Future<void> favorite(String server, Song song, bool selected) async {
    await db.rawInsert(
      'INSERT OR IGNORE INTO personal_song(instance_id,song_id,snapshot) VALUES(?,?,?)',
      [server, song.id, jsonEncode(song.data)],
    );
    await db.update(
      'personal_song',
      {'snapshot': jsonEncode(song.data), 'favorite': selected ? 1 : 0},
      where: 'instance_id = ? AND song_id = ?',
      whereArgs: [server, song.id],
    );
  }
}
