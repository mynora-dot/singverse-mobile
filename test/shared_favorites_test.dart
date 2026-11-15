import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/app/design.dart';
import 'package:singverse_mobile/app/shell.dart';
import 'package:singverse_mobile/core/api.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/legacy_favorites.dart';
import 'widget_test.dart' show FakeApi;

class FavoritesApi extends FakeApi {
  Future<dynamic> Function(String, String, Object?)? handler;
  Completer<void>? configureGate;
  Completer<void>? configureStarted;
  final writes = <Json>[];
  @override
  Future<void> configure(String value) async {
    await super.configure(value);
    configureStarted?.complete();
    await configureGate?.future;
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    if (path.startsWith('/api/v1/favorites')) {
      if (method == 'PUT') writes.add(body as Json);
      if (handler != null) return handler!(path, method, body);
    }
    return super.request(path, method: method, body: body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late FavoritesApi api;
  late LocalStore store;
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FavoritesApi()..loggedIn = true;
    store = await LocalStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    state =
        AppState(
            api: api,
            store: store,
            preferences: await SharedPreferences.getInstance(),
            listenPlayer: false,
          )
          ..origin = 'https://nas-a.test'
          ..instanceId = 'nas-a'
          ..authenticated = true;
  });
  tearDown(() async {
    state.dispose();
    await store.close();
  });

  test(
    'server is the only favorite source and local history is preserved',
    () async {
      final legacy = Song({'id': 'old', 'title': '旧本地收藏'});
      await store.favorite('nas-a', legacy, true);
      await store.played('nas-a', legacy, 12000, newPlay: true);
      api.favoriteRows['server'] = {'id': 'server', 'title': 'NAS 收藏'};
      await state.refreshPersonal();
      expect(state.favorites.map((song) => song.id), ['server']);
      expect(state.history.single.id, 'old');
      expect(state.history.single.data['positionMs'], 12000);
      expect((await store.favorites('nas-a')).single.id, 'old');
      api.offline = true;
      await state.refreshFavorites();
      expect(state.favorites.single.id, 'server');
      expect(state.favoritesError, contains('NAS 不可达'));
    },
  );

  test(
    'all server pages are loaded without the old 200-song TV or local limit',
    () async {
      for (var i = 0; i < 251; i++) {
        api.favoriteRows['$i'] = {'id': '$i', 'title': '歌曲 $i'};
      }
      await state.refreshFavorites();
      expect(state.favorites.length, 251);
      expect(state.isFavorite(Song({'id': '250'})), isTrue);
      expect(
        api.requests
            .where((path) => path.startsWith('/api/v1/favorites'))
            .length,
        3,
      );
    },
  );

  test(
    'a failed write does not change the authoritative state or playback',
    () async {
      final song = Song({'id': 'one', 'title': '歌曲'});
      api.favoriteRows[song.id] = song.data;
      await state.refreshFavorites();
      state.current = song;
      state.positionMs = 42000;
      api.handler = (_, method, _) async {
        if (method == 'PUT') throw ApiFailure(503, '保存失败');
        return {
          'items': [song.data],
          'totalElements': 1,
          'revision': 1,
        };
      };
      await expectLater(state.favorite(song), throwsA(isA<ApiFailure>()));
      expect(state.isFavorite(song), isTrue);
      expect(state.favoriteSaving, isFalse);
      expect(state.current, same(song));
      expect(state.positionMs, 42000);
      expect(api.writes.single, {
        'songIds': ['one'],
        'selected': false,
      });
      expect(await store.favorites('nas-a'), isEmpty);
    },
  );

  test('late reads and preloaded writes cannot cross a NAS switch', () async {
    final gate = Completer<dynamic>();
    var nas = 'A';
    api.handler = (_, _, _) {
      if (nas == 'A') return gate.future;
      return Future.value({
        'items': [
          {'id': 'same', 'title': 'NAS B'},
        ],
        'totalElements': 1,
        'revision': 2,
      });
    };
    final late = state.favorite(Song({'id': 'A-song', 'title': 'NAS A'}));
    nas = 'B';
    state.origin = 'https://nas-b.test';
    state.instanceId = 'nas-b';
    await state.refreshFavorites();
    expect(state.favorites.single.title, 'NAS B');
    gate.complete({
      'items': [
        {'id': 'same', 'title': 'NAS A'},
      ],
      'totalElements': 1,
      'revision': 1,
    });
    await late;
    expect(state.favorites.single.title, 'NAS B');
    expect(api.writes, isEmpty);
  });

  test(
    'initial add intent is preserved when preload finds it already selected',
    () async {
      final song = Song({'id': 'existing', 'title': '其他终端已收藏'});
      api.favoriteRows[song.id] = song.data;
      expect(state.favoritesReady, isFalse);
      await state.favorite(song);
      expect(api.writes.single, {
        'songIds': ['existing'],
        'selected': true,
      });
      expect(state.isFavorite(song), isTrue);
    },
  );

  test('favorites cannot write while the transport is changing NAS', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppState.player, (_) async => null);
    addTearDown(
      () => messenger.setMockMethodCallHandler(AppState.player, null),
    );
    final song = Song({'id': 'old', 'title': 'NAS A 收藏'});
    api.favoriteRows[song.id] = song.data;
    await state.refreshFavorites();
    final gate = Completer<void>();
    final started = Completer<void>();
    api.configureGate = gate;
    api.configureStarted = started;
    final switching = state.connect('https://nas-b.test');
    await started.future.timeout(const Duration(seconds: 5));
    try {
      expect(api.origin, 'https://nas-b.test');
      expect(state.authenticated, isFalse);
      expect(state.favorites, isEmpty);
      await state.favorite(song);
      expect(api.writes, isEmpty);
    } finally {
      api.loggedIn = false;
      gate.complete();
      await switching;
    }
    expect(state.favorites, isEmpty);
  });

  test('a revision change between pages retries and publishes only the final collection', () async {
    var calls = 0;
    api.handler = (_, _, _) async {
      calls++;
      return calls == 1
          ? {
              'items': [
                {'id': 'old'},
              ],
              'totalElements': 2,
              'revision': 1,
            }
          : calls == 2
          ? {
              'items': [
                {'id': 'changed'},
              ],
              'totalElements': 2,
              'revision': 2,
            }
          : {
              'items': [
                {'id': 'final'},
              ],
              'totalElements': 1,
              'revision': 2,
            };
    };
    await state.refreshFavorites();
    expect(calls, 3);
    expect(state.favorites.single.id, 'final');
  });

  test('foreground resume reads changes made by another client', () async {
    await state.refreshFavorites();
    api.favoriteRows['external'] = {'id': 'external', 'title': '后台新增'};
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(state.favorites.single.title, '后台新增');
  });

  test('an expired session clears the previous shared collection', () async {
    api.favoriteRows['server'] = {'id': 'server', 'title': 'NAS 收藏'};
    await state.refreshFavorites();
    api.handler = (_, _, _) async => throw ApiFailure(401, '登录失效');
    await state.refreshFavorites();
    expect(state.authenticated, isFalse);
    expect(state.favorites, isEmpty);
    expect(state.favoritesReady, isFalse);
    expect(state.isFavorite(Song({'id': 'server'})), isFalse);
    expect(state.favoritesError, '登录已失效，请重新登录');
  });

  testWidgets('shared favorites show read failure and recover with refresh', (
    tester,
  ) async {
    api.offline = true;
    await state.refreshFavorites();
    await tester.pumpWidget(
      MaterialApp(
        theme: singVerseTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, _) => FrequentPage(state: state),
          ),
        ),
      ),
    );
    expect(find.text('NAS 共享收藏'), findsOneWidget);
    expect(find.textContaining('收藏读取失败'), findsOneWidget);
    expect(find.text('还没有收藏。点歌曲旁的爱心，就能在这里快速找到。'), findsNothing);
    api.offline = false;
    api.favoriteRows['server'] = {
      'id': 'server',
      'title': '服务器歌曲',
      'available': false,
    };
    await tester.tap(find.byTooltip('刷新收藏'));
    await tester.pumpAndSettle();
    expect(find.text('服务器歌曲'), findsOneWidget);
    expect(find.textContaining('收藏读取失败'), findsNothing);
    expect(find.textContaining('暂不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
