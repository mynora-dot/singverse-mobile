import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_updates.dart';
import 'artwork_cache.dart';
import 'local_store.dart';
import 'login_store.dart';
import 'models.dart';

enum UiMode { standard, senior }

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({
    required this.api,
    required this.store,
    required this.preferences,
    LoginStore? loginStore,
    bool listenPlayer = true,
  }) : loginStore = loginStore ?? NativeLoginStore() {
    WidgetsBinding.instance.addObserver(this);
    themeMode = ThemeMode.values[preferences.getInt('theme')?.clamp(0, 2) ?? 0];
    uiMode = preferences.getString('uiMode') == 'senior'
        ? UiMode.senior
        : UiMode.standard;
    final savedLiquidGlass = preferences.getBool('liquidGlass');
    if (savedLiquidGlass != null) {
      reduceTransparency = !savedLiquidGlass;
      performanceMode = !savedLiquidGlass;
    } else {
      reduceTransparency = preferences.getBool('reduceTransparency') ?? false;
      performanceMode = preferences.getBool('performanceMode') ?? false;
    }
    nativeEnabled = listenPlayer;
    updates = AppUpdates(
      api: api,
      preferences: preferences,
      enabled: listenPlayer,
    );
    if (listenPlayer) {
      _events = const EventChannel('singverse/playback-events')
          .receiveBroadcastStream()
          .listen(
            _onPlayback,
            onError: (Object e) {
              playbackError = e.toString();
              notifyListeners();
            },
          );
    }
  }
  final playback = ChangeNotifier();
  late final Listenable performance = Listenable.merge([this, playback]);
  final NasApi api;
  late final AppUpdates updates;
  final LocalStore store;
  final SharedPreferences preferences;
  final LoginStore loginStore;
  static const _automaticLoginKey = 'login:automatic';
  static const _automaticLoginRecordKey = 'login:automatic-record';
  bool get automaticLogin => preferences.getBool(_automaticLoginKey) == true;
  bool automaticLoginFor(LoginRecord record) =>
      automaticLogin &&
      preferences.getString(_automaticLoginRecordKey) == record.id;

  Future<void> setAutomaticLogin(LoginRecord? record) async {
    // Only the selected record's identity is stored here. Its password stays in
    // the existing Android Keystore vault.
    if (record == null) {
      await preferences.setBool(_automaticLoginKey, false);
      await preferences.remove(_automaticLoginRecordKey);
    } else {
      await preferences.setString(_automaticLoginRecordKey, record.id);
      await preferences.setBool(_automaticLoginKey, true);
    }
    notifyListeners();
  }

  static const player = MethodChannel('singverse/player');
  StreamSubscription<dynamic>? _events;
  String origin = '', instanceId = '', accountName = '';
  String serverName = '';
  bool initialized = false,
      authenticated = false,
      mfaRequired = false,
      busy = false;
  String? error;
  String? retryAfter;
  ThemeMode themeMode = ThemeMode.system;
  UiMode uiMode = UiMode.standard;
  bool get senior => uiMode == UiMode.senior;
  bool reduceTransparency = false;
  bool performanceMode = false;
  bool get liquidGlass => !reduceTransparency && !performanceMode;
  bool nativeEnabled = true;
  Json singing = {};
  List<Json> works = [];
  bool worksLoading = false;
  String? worksError;
  List<Json> get visibleWorks => works
      .where(
        (w) =>
            instanceId.isEmpty ||
            w['instanceId'] == null ||
            w['instanceId'] == instanceId,
      )
      .toList();
  String workId = '';
  int stageRequests = 0;
  int countdown = 0, pitch = 0, rangeA = 0, rangeB = 0;
  double speed = 1, volume = 1;
  String channelMode = 'STEREO', outputRoute = '系统默认', audioRole = '';
  double videoAspect = 16 / 9;
  bool backingMapped = false, originalMapped = false;
  static const karaoke = MethodChannel('singverse/karaoke');
  String get singingPhase => singing['phase'] as String? ?? 'IDLE';
  bool get recording => singingPhase == 'RECORDING';
  bool get taking => recording || countdown > 0 || singingPhase == 'FINALIZING';
  String get takeId => singing['takeId'] as String? ?? '';
  String get pendingReviewId =>
      countdown == 0 &&
          takeId.isNotEmpty &&
          ['FINALIZING', 'PREVIEW', 'FAILED'].contains(singingPhase) &&
          singing['songId'] == current?.id &&
          singing['instanceId'] == playbackInstanceId
      ? takeId
      : '';
  String _workStatus = '';
  int _worksGeneration = 0;
  int _personalGeneration = 0;
  int _playGeneration = 0;
  void cancelPendingPlay() => _playGeneration++;
  Future<dynamic> sing(String method, [Json args = const {}]) async {
    final result = await karaoke.invokeMethod<dynamic>(method, args);
    return result is String &&
            (result.startsWith('{') || result.startsWith('['))
        ? jsonDecode(result)
        : result;
  }

  Future<void> refreshWorks() async {
    if (!nativeEnabled || _disposed) return;
    final ticket = ++_worksGeneration;
    worksLoading = true;
    worksError = null;
    // WorksPage also requests its initial data from initState.
    await Future<void>.value();
    if (_disposed || ticket != _worksGeneration) return;
    notifyListeners();
    try {
      final result = (await sing('works') as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (!_disposed && ticket == _worksGeneration) works = result;
    } catch (e) {
      if (!_disposed && ticket == _worksGeneration) {
        worksError = e is PlatformException
            ? e.message ?? '无法读取本机录音，请重试。'
            : e.toString();
      }
    } finally {
      if (!_disposed && ticket == _worksGeneration) {
        worksLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> endTake() async {
    await sing('end', {'id': takeId});
  }

  bool defaultPassword = false;
  List<Song> favorites = [], history = [];
  Song? current;
  String playbackState = 'IDLE', playbackError = '', mode = '';
  int positionMs = 0, durationMs = 0;
  bool isPlaying = false, loop = false;
  List<Json> tracks = [];
  String playbackInstanceId = '';
  String? _playbackKey;
  int _lastSaved = -1;
  String _lastPlayingKey = '';
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      await _restoreConnection(startup: true);
    } catch (e) {
      error = e is FormatException ? e.message : e.toString();
      if (e is ApiFailure) retryAfter = e.retryAfter;
    }
    initialized = true;
    notifyListeners();
    if (nativeEnabled) unawaited(refreshWorks());
  }

  Future<void> _restoreConnection({bool startup = false}) async {
    if (startup) origin = await api.restore();
    LoginRecord? automatic;
    if (automaticLogin) {
      final id = preferences.getString(_automaticLoginRecordKey);
      automatic = (await loginStore.load())
          .where((record) => record.id == id && record.hasPassword)
          .firstOrNull;
      if (automatic == null) {
        await setAutomaticLogin(null);
      } else if (startup) {
        origin = automatic.origin;
      } else if (automatic.origin != origin) {
        // Resuming must not undo a manual NAS switch.
        return;
      }
    }
    if (!startup && automatic == null) return;
    if (origin.isNotEmpty) {
      instanceId = preferences.getString('server-instance:$origin') ?? '';
      await refreshPersonal();
      final info = await api.inspect(origin) as Json;
      _checkServer(info);
      if (automatic != null && automatic.instanceId != info['instanceId']) {
        await setAutomaticLogin(null);
        throw const FormatException('此地址的曲库身份已变化，请重新登录');
      }
      serverName = info['name'] is String ? info['name'] as String : '';
      if (instanceId != info['instanceId']) _invalidateArtwork();
      instanceId = info['instanceId'] as String;
      await preferences.setString('server-instance:$origin', instanceId);
      await refreshPersonal();
      if (automatic != null) await api.configure(origin);
      updates.connect(origin);
      // Preserve existing session restoration until the user has made an
      // explicit choice with the new control. Turning it off requires a
      // manual login on the next launch, even if a cookie is still valid.
      if (preferences.getBool(_automaticLoginKey) != false) {
        try {
          await readSession();
        } on ApiFailure catch (e) {
          if (e.status != 401) rethrow;
        }
        if (automatic != null &&
            automaticLoginFor(automatic) &&
            (!authenticated || accountName != automatic.username)) {
          _loseSession();
          accountName = '';
          await api.forget();
          final secret = await loginStore.password(automatic);
          if (secret == null || secret.isEmpty) {
            await setAutomaticLogin(null);
            throw const FormatException('已保存的密码不可用，请重新登录');
          }
          if (!automaticLoginFor(automatic)) return;
          try {
            await _authenticate(secret, username: automatic.username);
          } on ApiFailure catch (e) {
            if (e.status == 401 || e.status == 403) {
              await setAutomaticLogin(null);
            }
            rethrow;
          }
          if (mfaRequired) error = '自动登录需要验证身份，请输入动态码或恢复码';
        }
      }
    }
  }

  void _checkServer(Json info) {
    if (info['service'] != 'singverse' ||
        info['apiVersion'] != 1 ||
        info['instanceId'] is! String) {
      throw const FormatException('此地址不是兼容的 SingVerse NAS 服务');
    }
  }

  Future<void> connect(String address) async {
    await _run(() async {
      final next = normalizeOrigin(address);
      final info = await api.inspect(next) as Json;
      _checkServer(info);
      if (origin != next) await command('stop');
      _loseSession();
      notifyListeners();
      updates.disconnect();
      await api.configure(next);
      origin = next;
      instanceId = info['instanceId'] as String;
      serverName = info['name'] is String ? info['name'] as String : '';
      await preferences.setString('server-instance:$origin', instanceId);
      mfaRequired = false;
      await refreshPersonal();
      updates.connect(origin);
      try {
        await readSession();
      } on ApiFailure catch (e) {
        if (e.status != 401) rethrow;
      }
    });
  }

  Future<void> login(String password, {String username = 'admin'}) =>
      _run(() => _authenticate(password, username: username));

  Future<void> _authenticate(
    String password, {
    required String username,
  }) async {
    _invalidateArtwork();
    final result = await api.request(
      '/api/v1/auth/login',
      method: 'POST',
      body: {'username': username.trim(), 'password': password},
    ) as Json;
    mfaRequired = result['state'] == 'mfaRequired';
    authenticated = result['state'] == 'authenticated';
    if (authenticated) {
      await readSession();
      await refreshPersonal();
    }
  }

  Future<void> resetPassword({
    required String username,
    required String resetToken,
    required String newPassword,
  }) => _run(() async {
    _invalidateArtwork();
    await api.request(
      '/api/v1/auth/password/reset',
      method: 'POST',
      body: {
        'username': username.trim(),
        'resetToken': resetToken.trim(),
        'newPassword': newPassword,
      },
    );
    _loseSession();
    mfaRequired = false;
    accountName = '';
    await setAutomaticLogin(null);
  });
  Future<void> verify(String code) => _run(() async {
    _invalidateArtwork();
    await api.request(
      '/api/v1/auth/mfa/verify',
      method: 'POST',
      body: {'code': code},
    );
    mfaRequired = false;
    authenticated = true;
    await readSession();
    await refreshPersonal();
  });
  Future<void> readSession() async {
    final identity = artworkIdentity;
    try {
      final session = await api.request('/api/v1/auth/session') as Json;
      if (_disposed || identity != artworkIdentity) {
        throw ApiFailure(409, 'NAS 连接已切换');
      }
      authenticated = true;
      defaultPassword = session['defaultPassword'] == true;
      accountName = session['username'] as String? ?? '';
      final scope = accountName.isEmpty || instanceId.isEmpty
          ? null
          : (origin: origin, instance: instanceId, account: accountName);
      if (scope != _artworkScope) {
        _invalidateArtwork();
        _artworkScope = scope;
      }
      updates.connect(origin, connection: false);
      await refreshFavorites();
    } on ApiFailure {
      if (!_disposed && identity == artworkIdentity) _loseSession();
      rethrow;
    }
  }

  final _artworkCache = ArtworkCache();
  ({String origin, String instance, String account})? _artworkScope;
  int _artworkGeneration = 0;
  String get artworkIdentity => jsonEncode([
    origin,
    instanceId,
    authenticated,
    _artworkScope?.account,
    _artworkGeneration,
  ]);

  void _invalidateArtwork() {
    _artworkGeneration++;
    _artworkScope = null;
    _artworkCache.clear();
  }

  void _loseSession() {
    authenticated = false;
    _invalidateArtwork();
    _clearFavorites();
  }

  static final _songCoverPath = RegExp(
    r'^/api/v1/metadata/songs/[^/?#]+/cover$',
  );

  Future<Uint8List> artwork(
    String path, {
    String? revision,
    bool thumbnail = false,
  }) async {
    final identity = artworkIdentity;
    final transport = api;
    final scope = _artworkScope;
    final resource =
        transport is NativeNasApi && thumbnail && _songCoverPath.hasMatch(path)
        ? '$path?variant=thumbnail'
        : path;
    final key = jsonEncode([identity, resource, revision]);
    try {
      final bytes = transport is NativeNasApi
          ? await _artworkCache.loadPayload(
              key,
              () => transport.artwork(
                resource,
                origin: origin,
                instanceId: instanceId,
                account:
                    authenticated &&
                        scope?.origin == origin &&
                        scope?.instance == instanceId
                    ? scope?.account
                    : null,
                revision: revision,
              ),
            )
          : await _artworkCache.load(key, () => transport.bytes(resource));
      if (_disposed || identity != artworkIdentity) {
        throw ApiFailure(409, 'NAS 连接已切换');
      }
      return bytes;
    } on ApiFailure catch (e) {
      if (e.status == 401 && authenticated && identity == artworkIdentity) {
        _loseSession();
        error = '登录已失效，请重新登录';
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    _invalidateArtwork();
    await setAutomaticLogin(null);
    await command('stop');
    try {
      if (authenticated) {
        await api.request('/api/v1/auth/logout', method: 'POST');
      }
    } finally {
      updates.disconnect();
      await api.forget();
      _loseSession();
      accountName = '';
      mfaRequired = false;
      error = null;
      notifyListeners();
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (busy) return;
    busy = true;
    error = null;
    retryAfter = null;
    notifyListeners();
    try {
      await task();
    } catch (e) {
      error = e is FormatException ? e.message : e.toString();
      if (e is ApiFailure) retryAfter = e.retryAfter;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<dynamic> get(String path) async {
    final identity = artworkIdentity;
    try {
      return await api.request(path);
    } on ApiFailure catch (e) {
      if (e.status == 401 && identity == artworkIdentity) {
        _loseSession();
        error = '登录已失效，请重新登录';
        notifyListeners();
      }
      if (e.status == 404 && path.startsWith('/api/v1/mobile/library/songs?')) {
        throw ApiFailure(404, 'NAS 版本尚未支持手机曲库，请更新 NAS 服务');
      }
      rethrow;
    }
  }

  Future<void> refreshPersonal({bool includeFavorites = true}) async {
    final expectedInstance = instanceId;
    final ticket = ++_personalGeneration;
    if (expectedInstance.isEmpty || _disposed) return;
    final nextHistory = await store.history(expectedInstance);
    if (_disposed ||
        ticket != _personalGeneration ||
        instanceId != expectedInstance) {
      return;
    }
    history = nextHistory;
    notifyListeners();
    if (includeFavorites) await refreshFavorites();
  }

  String _favoritesIdentity = '';
  int _favoritesGeneration = 0, _favoriteWriteGeneration = 0;
  Set<String> _favoriteIds = {};
  bool favoritesLoading = false, favoriteSaving = false, favoritesReady = false;
  String? favoritesError;
  Timer? _favoritesTimer;
  bool _favoritesForeground = true;
  String get _favoriteConnection => '$origin|$instanceId';
  bool isFavorite(Song song) =>
      _favoritesIdentity == _favoriteConnection &&
      _favoriteIds.contains(song.id);

  void _clearFavorites() {
    _favoritesGeneration++;
    _favoriteWriteGeneration++;
    _favoritesTimer?.cancel();
    _favoritesIdentity = _favoriteConnection;
    favorites = [];
    _favoriteIds = {};
    favoritesReady = false;
    favoritesLoading = false;
    favoriteSaving = false;
    favoritesError = null;
  }

  void _scheduleFavorites() {
    _favoritesTimer?.cancel();
    if (!nativeEnabled ||
        !_favoritesForeground ||
        !authenticated ||
        _disposed) {
      return;
    }
    _favoritesTimer = Timer(
      const Duration(seconds: 30),
      () => unawaited(refreshFavorites()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _favoritesForeground = state == AppLifecycleState.resumed;
    if (_favoritesForeground) {
      unawaited(_refreshForegroundConnection());
    } else {
      _favoritesTimer?.cancel();
    }
  }

  Future<void> _refreshForegroundConnection() async {
    if (authenticated) await refreshFavorites();
    if (_disposed ||
        !_favoritesForeground ||
        !initialized ||
        authenticated ||
        !automaticLogin ||
        busy ||
        mfaRequired ||
        taking ||
        singingPhase == 'RENDERING') {
      return;
    }
    // A warm return does not run initialize(). If the session expired while
    // backgrounded, reuse the same identity-checked login as a cold start.
    // _run serializes restoration with manual login and connection changes.
    await _run(() => _restoreConnection());
  }

  Future<void> refreshFavorites() async {
    if (_disposed) return;
    final identity = _favoriteConnection;
    if (_favoritesIdentity != identity) _clearFavorites();
    if (!authenticated || instanceId.isEmpty || origin.isEmpty) {
      _clearFavorites();
      notifyListeners();
      return;
    }
    if (favoriteSaving) return;
    final ticket = ++_favoritesGeneration;
    bool currentRequest() =>
        !_disposed &&
        authenticated &&
        ticket == _favoritesGeneration &&
        identity == _favoriteConnection;
    favoritesLoading = true;
    notifyListeners();
    try {
      // Publish only a complete, single-revision snapshot. A concurrent write
      // between pages causes a bounded retry instead of a truncated collection.
      for (var attempt = 0; attempt < 2; attempt++) {
        final rows = <Song>[];
        int? revision;
        var changed = false;
        for (var page = 0; ; page++) {
          final result = await api.request(
            '/api/v1/favorites?page=$page&size=100',
          ) as Json;
          if (!currentRequest()) return;
          if (result['revision'] is! int ||
              result['totalElements'] is! int ||
              result['items'] is! List) {
            throw const FormatException('NAS 收藏响应无效，请更新 NAS 服务');
          }
          revision ??= result['revision'] as int;
          if (revision != result['revision']) {
            changed = true;
            break;
          }
          final next = (result['items'] as List)
              .map((value) => Song(Map<String, dynamic>.from(value as Map)))
              .toList();
          rows.addAll(next);
          if (rows.length >= (result['totalElements'] as int)) break;
          if (next.isEmpty) throw const FormatException('收藏列表读取不完整，请重试');
        }
        if (changed) continue;
        favorites = rows;
        _favoriteIds = rows.map((song) => song.id).toSet();
        favoritesReady = true;
        favoritesError = null;
        return;
      }
      throw const FormatException('收藏正在其他终端更新，请重新读取');
    } catch (e) {
      if (currentRequest()) {
        favoritesError = e is FormatException ? e.message : e.toString();
        if (e is ApiFailure && e.status == 401) {
          _loseSession();
          favoritesError = '登录已失效，请重新登录';
        }
      }
    } finally {
      if (!_disposed &&
          identity == _favoriteConnection &&
          ticket == _favoritesGeneration) {
        favoritesLoading = false;
        notifyListeners();
        _scheduleFavorites();
      } else if (!_disposed && identity == _favoriteConnection) {
        notifyListeners();
      }
    }
  }

  Future<void> favorite(Song song) async {
    if (favoriteSaving) return;
    if (_favoritesIdentity != _favoriteConnection) _clearFavorites();
    final initialConnection = _favoriteConnection;
    final initialGeneration = _favoriteWriteGeneration;
    // Preserve the action shown on the button even if preload discovers an
    // identical change already completed by another client.
    final selected = !isFavorite(song);
    if (!favoritesReady || _favoritesIdentity != _favoriteConnection) {
      await refreshFavorites();
    }
    if (_disposed ||
        initialConnection != _favoriteConnection ||
        initialGeneration != _favoriteWriteGeneration) {
      return;
    }
    if (!authenticated || !favoritesReady) {
      throw ApiFailure(0, favoritesError ?? '请先连接 NAS 并读取收藏');
    }
    final identity = _favoriteConnection;
    final ticket = ++_favoriteWriteGeneration;
    _favoritesGeneration++;
    favoritesLoading = false;
    favoriteSaving = true;
    notifyListeners();
    try {
      final result = await api.request(
        '/api/v1/favorites',
        method: 'PUT',
        body: {
          'songIds': [song.id],
          'selected': selected,
        },
      ) as Json;
      if (_disposed ||
          identity != _favoriteConnection ||
          ticket != _favoriteWriteGeneration) {
        return;
      }
      _favoriteIds = (result['songIds'] as List).cast<String>().toSet();
      favorites = favorites
          .where((row) => _favoriteIds.contains(row.id))
          .toList();
      favoriteSaving = false;
      await refreshFavorites();
    } on ApiFailure catch (e) {
      if (!_disposed &&
          identity == _favoriteConnection &&
          ticket == _favoriteWriteGeneration) {
        if (e.status == 401) {
          _loseSession();
          notifyListeners();
        }
        rethrow;
      }
    } finally {
      if (!_disposed &&
          identity == _favoriteConnection &&
          ticket == _favoriteWriteGeneration) {
        favoriteSaving = false;
        notifyListeners();
        _scheduleFavorites();
      }
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    await preferences.setInt('theme', mode.index);
    notifyListeners();
  }

  Future<void> setUiMode(UiMode mode) async {
    uiMode = mode;
    await preferences.setString('uiMode', mode.name);
    notifyListeners();
  }

  Future<void> setLiquidGlass(bool enabled) async {
    reduceTransparency = !enabled;
    performanceMode = !enabled;
    notifyListeners();
    await preferences.setBool('liquidGlass', enabled);
    await preferences.setBool('reduceTransparency', !enabled);
    await preferences.setBool('performanceMode', !enabled);
  }

  Future<void> setTransparency(bool reduced) async {
    reduceTransparency = reduced;
    await preferences.remove('liquidGlass');
    await preferences.setBool('reduceTransparency', reduced);
    notifyListeners();
  }

  Future<void> setPerformanceMode(bool enabled) async {
    performanceMode = enabled;
    notifyListeners();
    await preferences.remove('liquidGlass');
    await preferences.setBool('performanceMode', enabled);
  }

  Future<void> play(
    Song song, {
    bool force = false,
    int start = 0,
    bool autoplay = true,
    bool reuseAttempt = false,
  }) async {
    final ticket = ++_playGeneration;
    final detail = Song(
      await get('/api/v1/mobile/library/songs/${Uri.encodeComponent(song.id)}')
          as Json,
    );
    if (_disposed || ticket != _playGeneration) return;
    await player.invokeMethod<void>('open', {
      'song': jsonEncode(detail.data),
      'instanceId': instanceId,
      'positionMs': start,
      'force': force,
      'autoplay': autoplay,
      'reuseAttempt': reuseAttempt,
    });
    final snapshot = await player.invokeMapMethod<String, dynamic>('snapshot');
    if (snapshot != null) _onPlayback(snapshot);
  }

  Future<void> command(String action, [Object? value]) async {
    if (action == 'pause' || action == 'stop') cancelPendingPlay();
    await player.invokeMethod<void>('command', {
      'action': action,
      'value': value,
    });
  }

  String get _playbackStructure => [
    current?.data,
    playbackInstanceId,
    playbackState,
    playbackError,
    isPlaying,
    loop,
    mode,
    tracks,
    authenticated,
    workId,
    singingPhase,
    takeId,
    singing['error'],
    singing['input'],
    countdown,
    pitch,
    speed,
    volume,
    channelMode,
    audioRole,
    videoAspect,
    outputRoute,
    rangeA,
    rangeB,
    backingMapped,
    originalMapped,
    stageRequests,
  ].join('\u0000');

  void _onPlayback(dynamic event) {
    if (_disposed) return;
    final value = Map<String, dynamic>.from(event as Map);
    final previousProgress = _playbackProgress;
    if (value['progressOnly'] == true) {
      // A queued tick from an older source/service must not update a new song.
      if (_playbackKey == null || value['playbackKey'] != _playbackKey) return;
      final karaoke = value['karaoke'] as Map? ?? const {};
      if (karaoke['phase'] != singingPhase || karaoke['takeId'] != takeId) {
        return;
      }
      positionMs = (value['positionMs'] as num? ?? positionMs).toInt();
      durationMs = (value['durationMs'] as num? ?? durationMs).toInt();
      for (final key in ['level', 'clipped', 'recordedMs']) {
        if (karaoke.containsKey(key)) singing[key] = karaoke[key];
      }
      // AudioTrack can choose its actual route after the initial player event.
      final output = value['output'] as String? ?? outputRoute;
      final routeChanged = output != outputRoute;
      outputRoute = output;
      _savePlaybackHistory();
      if (routeChanged) {
        notifyListeners();
      } else if (previousProgress != _playbackProgress) {
        playback.notifyListeners();
      }
      return;
    }
    final previous = _playbackStructure;
    _playbackKey = value['playbackKey'] as String?;
    if (value['openSinging'] == true) stageRequests++;
    final raw = jsonDecode(value['song'] as String) as Json;
    current = raw['id'] == null ? null : Song(raw);
    playbackInstanceId = value['instanceId'] as String? ?? '';
    playbackState = value['state'] as String? ?? 'IDLE';
    playbackError = value['message'] as String? ?? '';
    positionMs = (value['positionMs'] as num? ?? 0).toInt();
    durationMs = (value['durationMs'] as num? ?? 0).toInt();
    isPlaying = value['isPlaying'] == true;
    loop = value['loop'] == true;
    mode = value['mode'] as String? ?? '';
    tracks = (value['tracks'] as List? ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();
    if (playbackState == 'AUTH_REQUIRED') {
      _loseSession();
      error = playbackError;
    }
    singing = Map<String, dynamic>.from(value['karaoke'] as Map? ?? {});
    workId = value['workId'] as String? ?? '';
    countdown = (value['countdown'] as num? ?? 0).toInt();
    pitch = (value['pitch'] as num? ?? 0).toInt();
    speed = (value['speed'] as num? ?? 1).toDouble();
    volume = (value['volume'] as num? ?? 1).toDouble();
    channelMode = value['channel'] as String? ?? 'STEREO';
    audioRole = value['audioRole'] as String? ?? '';
    final aspect = (value['videoAspect'] as num? ?? 16 / 9).toDouble();
    videoAspect = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
    outputRoute = value['output'] as String? ?? '系统默认';
    rangeA = (value['rangeA'] as num? ?? 0).toInt();
    rangeB = (value['rangeB'] as num? ?? 0).toInt();
    backingMapped = value['backingMapped'] == true;
    originalMapped = value['originalMapped'] == true;
    final statusKey = '$takeId:$singingPhase';
    if (_workStatus != statusKey) {
      _workStatus = statusKey;
      if (['PREVIEW', 'SAVED', 'FAILED'].contains(singingPhase)) {
        unawaited(refreshWorks());
      }
    }
    _savePlaybackHistory();
    if (previous != _playbackStructure) {
      notifyListeners();
    } else if (previousProgress != _playbackProgress) {
      playback.notifyListeners();
    }
  }

  (int, int, Object?, Object?, Object?) get _playbackProgress => (
    positionMs,
    durationMs,
    singing['level'],
    singing['clipped'],
    singing['recordedMs'],
  );

  void _savePlaybackHistory() {
    final song = current;
    final key = '${playbackInstanceId}_${song?.id}';
    final newPlay = isPlaying && _lastPlayingKey != key;
    if (song != null &&
        workId.isEmpty &&
        playbackInstanceId.isNotEmpty &&
        (newPlay ||
            _lastPlayingKey == key &&
                (positionMs - _lastSaved).abs() >= 5000)) {
      _lastSaved = positionMs;
      if (newPlay) _lastPlayingKey = key;
      unawaited(
        store
            .played(playbackInstanceId, song, positionMs, newPlay: newPlay)
            .then((_) async {
              if (_disposed || playbackInstanceId != instanceId) return;
              if (newPlay) {
                await refreshPersonal(includeFavorites: false);
              } else {
                history = history
                    .map(
                      (item) => item.id == song.id
                          ? Song({...item.data, 'positionMs': positionMs})
                          : item,
                    )
                    .toList();
              }
            })
            .catchError((Object e) {
              if (!_disposed) {
                playbackError = '本机历史保存失败';
                notifyListeners();
              }
            }),
      );
    }
    if (current == null) _lastPlayingKey = '';
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _favoritesTimer?.cancel();
    updates.dispose();
    _invalidateArtwork();
    unawaited(_events?.cancel());
    playback.dispose();
    super.dispose();
  }
}

class SongQuery extends ChangeNotifier {
  SongQuery(this.state, {this.artistId, List<String> tags = const []})
    : tagIds = [...tags];
  final AppState state;
  final String? artistId;
  String query = '';
  List<String> tagIds;
  List<Song> items = [];
  int total = 0, _page = 0, _generation = 0;
  bool loading = false, disposed = false;
  String? error;
  bool _failedMore = false;
  String? _loadedCriteria;
  bool get hasMore => items.length < total;
  Future<void> retry() => load(more: _failedMore);
  Future<void> load({bool more = false}) async {
    if (disposed || more && (loading || !hasMore)) return;
    final criteria = jsonEncode([query, tagIds, artistId]);
    if (more && criteria != _loadedCriteria) return load();
    final ticket = ++_generation;
    final page = more ? _page + 1 : 0;
    loading = true;
    error = null;
    _failedMore = false;
    if (!more) {
      items = [];
      total = 0;
    }
    notifyListeners();
    try {
      final params = <String, dynamic>{
        'q': query,
        'page': '$page',
        'size': '20',
        if (tagIds.isNotEmpty) 'tagIds': tagIds,
        if (artistId != null) 'artistId': artistId,
      };
      final result = await state.get(
        '/api/v1/mobile/library/songs?${Uri(queryParameters: params).query}',
      ) as Json;
      if (disposed || ticket != _generation) return;
      final rows = (result['items'] as List).map((x) => Song(x as Json));
      items = more ? [...items, ...rows] : rows.toList();
      total = result['totalElements'] as int;
      _page = page;
      _loadedCriteria = criteria;
    } catch (e) {
      if (!disposed && ticket == _generation) {
        error = e is FormatException ? e.message : e.toString();
        _failedMore = more;
      }
    } finally {
      if (!disposed && ticket == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    _generation++;
    super.dispose();
  }
}
