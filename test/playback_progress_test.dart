import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singverse_mobile/app/mini_player.dart';
import 'package:singverse_mobile/core/app_state.dart';
import 'package:singverse_mobile/core/local_store.dart';
import 'package:singverse_mobile/core/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show FakeApi;

class _HistoryStore extends LocalStore {
  _HistoryStore(super.db);
  final saves = <(String, int, bool)>[];

  @override
  Future<void> played(
    String server,
    Song song,
    int position, {
    bool newPlay = false,
  }) async {
    saves.add((song.id, position, newPlay));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const events = MethodChannel('singverse/playback-events');
  const updates = MethodChannel('singverse/update-events');
  const codec = StandardMethodCodec();
  sqfliteFfiInit();
  late _HistoryStore store;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final opened = await LocalStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    store = _HistoryStore(opened.db);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(updates, (_) async => null);
    state = AppState(
      api: FakeApi(),
      store: store,
      preferences: await SharedPreferences.getInstance(),
    );
    // Wait for EventChannel's initial listen handshake.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    state.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(updates, null);
    await store.close();
  });

  Future<void> emit(Map<String, Object?> event) async {
    binding.channelBuffers.push(
      events.name,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Map<String, Object?> snapshot({
    String key = 'service-a:1',
    String id = 'song',
    bool playing = false,
    String phase = 'IDLE',
    String take = '',
  }) => {
    'playbackKey': key,
    'song': jsonEncode({'id': id, 'title': '测试歌曲'}),
    'state': playing ? 'PLAYING' : 'PAUSED',
    'instanceId': 'nas-a',
    'isPlaying': playing,
    'positionMs': 100,
    'durationMs': 10000,
    'tracks': [
      {'id': '0:0', 'type': 'audio', 'selected': true},
    ],
    'karaoke': {
      'phase': phase,
      'takeId': take,
      'songId': id,
      'instanceId': 'nas-a',
      'level': 0.0,
      'clipped': false,
      'recordedMs': 0,
    },
  };

  Map<String, Object?> progress({
    String key = 'service-a:1',
    int position = 200,
    String phase = 'IDLE',
    String take = '',
    double level = 0.0,
    bool clipped = false,
  }) => {
    'progressOnly': true,
    'playbackKey': key,
    'positionMs': position,
    'durationMs': 10000,
    'karaoke': {
      'phase': phase,
      'takeId': take,
      'level': level,
      'clipped': clipped,
      'recordedMs': position,
    },
  };

  test(
    'ticks reuse song and tracks and only notify progress listeners',
    () async {
      await emit(snapshot());
      final song = state.current;
      final tracks = state.tracks;
      var globals = 0, ticks = 0;
      state.addListener(() => globals++);
      state.playback.addListener(() => ticks++);
      for (var i = 1; i <= 100; i++) {
        await emit(progress(position: 100 + i * 100));
      }
      expect(identical(song, state.current), isTrue);
      expect(identical(tracks, state.tracks), isTrue);
      expect(state.positionMs, 10100);
      expect(globals, 0);
      expect(ticks, 100);
      await emit(progress(position: 10100));
      expect(ticks, 100);
    },
  );

  test('ticks before a snapshot or from an old playback are ignored', () async {
    await emit(progress());
    expect(state.current, isNull);
    expect(state.positionMs, 0);
    await emit(snapshot(key: 'service-a:2', id: 'new'));
    await emit(progress(key: 'service-a:1', position: 9000));
    expect(state.current!.id, 'new');
    expect(state.positionMs, 100);
    await emit(progress(key: 'service-b:2', position: 8000));
    expect(state.positionMs, 100);
    await emit(progress(key: 'service-a:2', position: 300));
    expect(state.positionMs, 300);
  });

  test(
    'recording meters preserve take metadata and reject another take',
    () async {
      await emit(snapshot(phase: 'RECORDING', take: 'take-1'));
      await emit(
        progress(
          phase: 'RECORDING',
          take: 'take-1',
          position: 900,
          level: .6,
          clipped: true,
        ),
      );
      expect(state.singing['songId'], 'song');
      expect(state.singing['recordedMs'], 900);
      expect(state.singing['level'], .6);
      expect(state.singing['clipped'], isTrue);
      await emit(progress(phase: 'RECORDING', take: 'take-2', position: 4000));
      expect(state.singing['recordedMs'], 900);
      expect(state.takeId, 'take-1');
      await emit(progress(phase: 'IDLE', take: 'take-1', position: 5000));
      expect(state.singingPhase, 'RECORDING');
      expect(state.positionMs, 900);
    },
  );

  test('progress retains the five second local history checkpoint', () async {
    await emit(snapshot(playing: true));
    await emit(progress(position: 1000));
    await emit(progress(position: 5200));
    await emit(progress(position: 5500));
    expect(store.saves, [('song', 100, true), ('song', 5200, false)]);
  });

  test('a late output route refreshes controls only when it changes', () async {
    await emit(snapshot());
    final song = state.current;
    var globals = 0, ticks = 0;
    state.addListener(() => globals++);
    state.playback.addListener(() => ticks++);
    await emit({...progress(), 'output': '蓝牙耳机'});
    expect(state.outputRoute, '蓝牙耳机');
    expect(globals, 1);
    expect(identical(song, state.current), isTrue);
    await emit({...progress(position: 300), 'output': '蓝牙耳机'});
    expect(globals, 1);
    expect(ticks, 1);
    await emit({...progress(key: 'old:1'), 'output': '旧设备'});
    expect(state.outputRoute, '蓝牙耳机');
    expect(globals, 1);
  });

  testWidgets(
    'mini player ticks update progress without rebuilding the title or controls',
    (tester) async {
      await tester.runAsync(() => emit(snapshot(playing: true)));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniPlayer(state: state)),
        ),
      );
      final title = tester.widget<Text>(find.text('测试歌曲'));
      final playButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '暂停播放',
      );
      final button = tester.widget<IconButton>(playButton);
      await tester.runAsync(() => emit(progress(position: 2300)));
      await tester.pump();
      expect(identical(title, tester.widget<Text>(find.text('测试歌曲'))), isTrue);
      expect(identical(button, tester.widget<IconButton>(playButton)), isTrue);
      expect(find.text('播放中 · 0:02'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .23,
      );
      await tester.runAsync(() => emit(snapshot()));
      await tester.pump();
      expect(find.byTooltip('继续播放'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
