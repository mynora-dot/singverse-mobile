import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../library/connection.dart';
import '../library/library_pages.dart';
import '../library/widgets.dart';
import '../singing/actions.dart';
import '../singing/works_page.dart';
import 'player_lyrics.dart';

Widget performancePage(AppState state) => state.recording || state.countdown > 0
    ? PlayerPage(state: state)
    : state.workId.isNotEmpty
    ? ReviewPage(state: state, id: state.workId)
    : state.pendingReviewId.isNotEmpty
    ? ReviewPage(state: state, id: state.pendingReviewId)
    : PlayerPage(state: state);

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.state, this.song});
  final AppState state;
  final Song? song;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const stageColor = AppPalette.stage;
  List<TextLine> lines = [];
  List<(String, String)> lyricCredits = [];
  String? lyricsSong, lyricError, openError, recordingError;
  bool lyricsLoading = true,
      opening = false,
      actionBusy = false,
      allowPop = false;
  int lyricsGeneration = 0;
  String recordedTake = '', reviewed = '';
  double? drag;
  bool forcedLandscape = false;
  Timer? controlsTimer;
  bool controlsVisible = true, pointerHeld = false, keyboardNavigation = false;
  bool landscape = false, accessibleControls = false, wasPlaying = false;
  bool wasClipped = false;
  int openPanels = 0;
  final dockKey = GlobalKey();
  double dockHeight = 154, lastSubtitleInset = -1;
  bool measurePending = false;
  double stageDrag = 0;
  bool stageDragging = false;

  void measureChrome(double canvasHeight) {
    if (measurePending) return;
    measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      measurePending = false;
      if (!mounted) return;
      final measured = dockKey.currentContext?.size?.height ?? dockHeight;
      if (landscape && (measured - dockHeight).abs() > 1) {
        setState(() => dockHeight = measured);
      }
      final inset = landscape && controlsVisible
          ? ((measured + 12) / canvasHeight).clamp(.08, .65)
          : .08;
      if ((lastSubtitleInset - inset).abs() > .005) {
        lastSubtitleInset = inset;
        if (widget.state.nativeEnabled) {
          unawaited(widget.state.command('subtitleInset', inset));
        }
      }
    });
  }

  void updateLayout(bool wide) {
    if (landscape == wide) return;
    landscape = wide;
    controlsVisible = true;
    keyboardNavigation = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          wide ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
      armControls();
    });
  }

  bool get keepControls =>
      !widget.state.isPlaying ||
      widget.state.countdown > 0 ||
      opening ||
      actionBusy ||
      drag != null ||
      pointerHeld ||
      keyboardNavigation ||
      accessibleControls ||
      openPanels > 0 ||
      widget.state.playbackError.isNotEmpty ||
      recordingError != null;

  void armControls() {
    controlsTimer?.cancel();
    if (!mounted || !landscape || !controlsVisible || keepControls) return;
    controlsTimer = Timer(
      Duration(milliseconds: widget.state.senior ? 6000 : 3500),
      () {
        if (!mounted ||
            keepControls ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        setState(() => controlsVisible = false);
      },
    );
  }

  void revealControls() {
    if (!mounted) return;
    setState(() => controlsVisible = true);
    armControls();
  }

  void toggleControls() {
    if (keepControls) {
      revealControls();
      return;
    }
    setState(() => controlsVisible = !controlsVisible);
    armControls();
  }

  Future<void> panel(Future<void> Function() action) async {
    openPanels++;
    revealControls();
    try {
      await action();
    } finally {
      openPanels--;
      armControls();
    }
  }

  ThemeData? cachedTheme;
  (Brightness, bool, bool, AppMotionLevel)? cachedThemeKey;
  ThemeData get _theme {
    final size = MediaQuery.sizeOf(context);
    final brightness = size.width > size.height
        ? Brightness.dark
        : Theme.of(context).brightness;
    final key = (
      brightness,
      widget.state.senior,
      size.width < 375,
      widget.state.performanceMode
          ? AppMotionLevel.none
          : AppMotionScope.levelOf(context),
    );
    if (cachedThemeKey == key && cachedTheme != null) return cachedTheme!;
    cachedThemeKey = key;
    final theme = singVerseTheme(
      brightness,
      senior: widget.state.senior,
      compact: MediaQuery.sizeOf(context).width < 375,
      motion: widget.state.performanceMode
          ? AppMotionLevel.none
          : AppMotionScope.levelOf(context),
    );
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF121214) : const Color(0xFFF5F5F7);
    final foreground = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
    final muted = dark ? const Color(0xFFA1A1A6) : const Color(0xFF6E6E73);
    return cachedTheme = theme.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: theme.colorScheme.copyWith(
        primary: foreground,
        onPrimary: background,
        surface: dark ? const Color(0xFF242426) : Colors.white,
        onSurface: foreground,
        onSurfaceVariant: muted,
        secondaryContainer: dark
            ? const Color(0xFF252527)
            : const Color(0xFFEBEBED),
        onSecondaryContainer: foreground,
        outlineVariant: dark
            ? const Color(0xFF39393C)
            : const Color(0xFFDADADD),
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      sliderTheme: theme.sliderTheme.copyWith(
        activeTrackColor: foreground,
        thumbColor: foreground,
        inactiveTrackColor: foreground.withValues(alpha: .16),
      ),
    );
  }

  Color get pageColor => _theme.scaffoldBackgroundColor;

  Color get recordingColor => _theme.colorScheme.error;

  bool get largeControls =>
      widget.state.senior || MediaQuery.textScalerOf(context).scale(16) > 22;

  @override
  void initState() {
    super.initState();
    reviewed = widget.state.takeId;
    if (widget.state.recording) recordedTake = widget.state.takeId;
    wasClipped = widget.state.singing['clipped'] == true;
    widget.state.performance.addListener(watch);
    if (widget.song != null) {
      opening = true;
      unawaited(prepare());
    } else {
      unawaited(loadLyrics(widget.state.current));
    }
  }

  @override
  void dispose() {
    lyricsGeneration++;
    controlsTimer?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    if (widget.state.nativeEnabled) {
      unawaited(widget.state.command('subtitleInset', .08));
    }
    widget.state.performance.removeListener(watch);
    if (forcedLandscape) {
      unawaited(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
      );
    }
    super.dispose();
  }

  Future<void> prepare({bool compatible = false, bool retry = false}) async {
    final song = widget.song ?? widget.state.current;
    if (song == null) return;
    if (mounted) {
      setState(() {
        opening = true;
        openError = null;
      });
    }
    try {
      await widget.state.play(
        song,
        force: compatible,
        reuseAttempt: retry,
        start: (song.data['positionMs'] as num? ?? 0).toInt(),
      );
      if (mounted) await loadLyrics(widget.state.current ?? song);
    } catch (e) {
      if (mounted) setState(() => openError = e.toString());
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> loadLyrics(Song? song) async {
    if (song == null || widget.state.workId.isNotEmpty) {
      if (mounted) setState(() => lyricsLoading = false);
      return;
    }
    final generation = ++lyricsGeneration;
    lyricsSong = song.id;
    if (mounted) {
      setState(() {
        lyricsLoading = true;
        lyricError = null;
        lines = [];
        lyricCredits = [];
      });
    }
    try {
      final data = await widget.state.get(
        '/api/v1/mobile/library/songs/${Uri.encodeComponent(song.id)}/text-tracks',
      ) as Json;
      if (mounted && generation == lyricsGeneration) {
        final display = PlayerLyrics.fromTracks(
          (data['items'] as List).cast<Json>(),
          song,
        );
        setState(() {
          lines = display.lines;
          lyricCredits = display.credits;
        });
      }
    } catch (_) {
      if (mounted && generation == lyricsGeneration) {
        setState(() => lyricError = '歌词暂不可读');
      }
    } finally {
      if (mounted && generation == lyricsGeneration) {
        setState(() => lyricsLoading = false);
      }
    }
  }

  void watch() {
    final state = widget.state;
    final clipped = state.singing['clipped'] == true;
    if (clipped != wasClipped) {
      setState(() => wasClipped = clipped);
    }
    if (wasPlaying != state.isPlaying) {
      wasPlaying = state.isPlaying;
      controlsVisible = true;
      armControls();
    } else if (keepControls) {
      controlsVisible = true;
      controlsTimer?.cancel();
    } else if (controlsVisible && !(controlsTimer?.isActive ?? false)) {
      armControls();
    }
    if (!opening && state.current?.id != lyricsSong && state.workId.isEmpty) {
      unawaited(loadLyrics(state.current));
    }
    if (state.recording) recordedTake = state.takeId;
    if (state.countdown == 0 &&
        recordedTake.isNotEmpty &&
        state.takeId == recordedTake &&
        reviewed != state.takeId &&
        ['FINALIZING', 'PREVIEW', 'FAILED'].contains(state.singingPhase)) {
      final id = state.takeId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            state.takeId == id &&
            reviewed != id &&
            ModalRoute.of(context)?.isCurrent == true) {
          reviewed = id;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'review'),
              builder: (_) => ReviewPage(state: state, id: id),
            ),
          );
        }
      });
    }
  }

  Future<void> close() async {
    if (widget.state.countdown > 0) {
      await widget.state.command('cancelCountdown');
    }
    if (!mounted) return;
    if (widget.state.recording) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('仍在录音，可通过底部播放器或通知返回。')));
    }
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> record() => uiTask(context, () async {
    if (actionBusy) return;
    setState(() {
      actionBusy = true;
      recordingError = null;
    });
    controlsTimer?.cancel();
    final state = widget.state;
    try {
      if (state.countdown > 0) {
        await state.command('cancelCountdown');
        return;
      }
      if (state.recording) {
        await state.endTake();
        return;
      }
      if (await confirmRecording(context, state)) {
        reviewed = state.takeId;
        await state.command('record', true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => recordingError = e is FormatException
              ? e.message
              : e is PlatformException
              ? e.message ?? '录音准备失败，请重试。'
              : e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() => actionBusy = false);
        armControls();
      }
    }
  });
  Future<void> orientation() async {
    forcedLandscape = true;
    await SystemChrome.setPreferredOrientations(
      MediaQuery.orientationOf(context) == Orientation.landscape
          ? [DeviceOrientation.portraitUp]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  Future<void> range() async {
    final state = widget.state;
    if (state.durationMs <= 0 || state.taking) return;
    final duration = state.durationMs.toDouble();
    final timedLines = lines.where((line) => line.startMs != null).toList();
    // Native playback keeps the committed loop while this sheet owns a draft.
    var values = RangeValues(
      state.rangeA.toDouble().clamp(0, duration),
      state.rangeB > state.rangeA
          ? state.rangeB.toDouble().clamp(0, duration)
          : duration,
    );
    int? startLine;
    var selectingEnd = false;
    var committing = false;
    await panel(
      () => showAppSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            Future<void> commit({bool wholeSong = false}) =>
                uiTask(context, () async {
                  if (committing) return;
                  final selection = values;
                  update(() => committing = true);
                  try {
                    await state.command('range', {
                      'a': wholeSong ? 0 : selection.start.round(),
                      'b': wholeSong ? 0 : selection.end.round(),
                    });
                    if (!wholeSong) {
                      await state.command('seek', selection.start.round());
                    }
                    if (context.mounted) Navigator.pop(context);
                  } finally {
                    if (context.mounted) update(() => committing = false);
                  }
                });

            Widget endpoint(String label, bool start) => Semantics(
              label: '选段$label',
              child: Slider(
                key: ValueKey(
                  start ? 'player-range-start' : 'player-range-end',
                ),
                value: start ? values.start : values.end,
                max: duration,
                label: durationLabel(
                  (start ? values.start : values.end).round(),
                ),
                semanticFormatterCallback: (value) =>
                    '$label ${durationLabel(value.round())}',
                onChanged: committing
                    ? null
                    : (value) => update(() {
                        values = start
                            ? RangeValues(
                                value.clamp(0, values.end),
                                values.end,
                              )
                            : RangeValues(
                                values.start,
                                value.clamp(values.start, duration),
                              );
                      }),
              ),
            );

            return SizedBox(
              height: (MediaQuery.sizeOf(context).height * .82).clamp(
                320.0,
                720.0,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SheetHeader('选段练唱', done: '取消'),
                    Expanded(
                      child: ListView(
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            '起点 ${durationLabel(values.start.round())} — 终点 ${durationLabel(values.end.round())}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 12),
                          endpoint('起点', true),
                          endpoint('终点', false),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: committing
                                    ? null
                                    : () => update(
                                        () => values = RangeValues(
                                          state.positionMs.toDouble().clamp(
                                            0,
                                            values.end,
                                          ),
                                          values.end,
                                        ),
                                      ),
                                child: const Text('当前位置设为起点'),
                              ),
                              TextButton(
                                onPressed: committing
                                    ? null
                                    : () => update(
                                        () => values = RangeValues(
                                          values.start,
                                          state.positionMs.toDouble().clamp(
                                            values.start,
                                            duration,
                                          ),
                                        ),
                                      ),
                                child: const Text('当前位置设为终点'),
                              ),
                            ],
                          ),
                          if (timedLines.isNotEmpty) ...[
                            const Divider(height: 32),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                selectingEnd ? '再点一句作为结束句' : '按歌词选段：先点起句，再点结束句',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                            for (var i = 0; i < timedLines.length; i++)
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                selected:
                                    timedLines[i].startMs! >= values.start &&
                                    timedLines[i].startMs! < values.end,
                                leading: Text(
                                  durationLabel(timedLines[i].startMs!),
                                ),
                                title: Text(timedLines[i].text),
                                onTap: committing
                                    ? null
                                    : () => update(() {
                                        final end =
                                            (timedLines[i].endMs ??
                                                    (i + 1 < timedLines.length
                                                        ? timedLines[i + 1]
                                                              .startMs!
                                                        : state.durationMs))
                                                .toDouble();
                                        if (!selectingEnd ||
                                            startLine == null ||
                                            i < startLine!) {
                                          startLine = i;
                                          selectingEnd = true;
                                          final start = timedLines[i].startMs!
                                              .toDouble()
                                              .clamp(0, duration)
                                              .toDouble();
                                          values = RangeValues(
                                            start,
                                            end.clamp(start, duration),
                                          );
                                        } else {
                                          values = RangeValues(
                                            values.start,
                                            end.clamp(values.start, duration),
                                          );
                                          selectingEnd = false;
                                        }
                                      }),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('player-range-apply'),
                      onPressed: committing || values.end <= values.start
                          ? null
                          : commit,
                      child: Text(committing ? '正在应用…' : '循环练唱这一段'),
                    ),
                    TextButton(
                      key: const ValueKey('player-range-clear'),
                      onPressed: committing
                          ? null
                          : () => commit(wholeSong: true),
                      child: const Text('恢复整首练唱'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> more() => panel(
    () => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ListenableBuilder(
        listenable: widget.state.performance,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader('更多功能', done: '关闭'),
              ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: const Text('选段练唱'),
                onTap: widget.state.taking
                    ? null
                    : () {
                        Navigator.pop(context);
                        range();
                      },
              ),
              SwitchListTile(
                value: widget.state.loop,
                title: const Text('单曲循环'),
                onChanged: widget.state.taking
                    ? null
                    : (v) => uiTask(
                        context,
                        () => widget.state.command('loop', v),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.headphones_rounded),
                title: const Text('音轨与播放设置'),
                onTap: () => panel(() => audioSettings(context, widget.state)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget header(Song song, {bool compact = false, bool dense = false}) {
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '收起演唱',
            onPressed: close,
            color: _theme.colorScheme.onSurfaceVariant,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: compact || dense ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!compact && !dense)
                  Text(
                    song.artist.isEmpty ? '手机练唱' : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _theme.textTheme.bodySmall?.copyWith(
                      color: _theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: state.isFavorite(song) ? '取消收藏' : '收藏歌曲',
            onPressed: () => uiTask(context, () => state.favorite(song)),
            icon: Icon(
              state.isFavorite(song)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 22,
              color: state.isFavorite(song)
                  ? _theme.colorScheme.primary
                  : _theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (compact)
            IconButton(
              tooltip: '退出横屏',
              onPressed: orientation,
              icon: const Icon(Icons.fullscreen_exit_rounded),
            ),
          IconButton(
            tooltip: '歌曲信息',
            onPressed: () => panel(
              () => showSong(context, state, song, credits: lyricCredits),
            ),
            color: _theme.colorScheme.onSurfaceVariant,
            icon: const Icon(Icons.info_outline_rounded, size: 22),
          ),
        ],
      ),
    );
  }

  Widget video() => Stack(
    key: const ValueKey('player-video'),
    fit: StackFit.expand,
    children: [
      ColoredBox(
        color: Colors.black,
        child: widget.state.nativeEnabled
            ? const AndroidView(viewType: 'singverse/video')
            : const Center(
                child: Icon(
                  Icons.music_video_rounded,
                  size: 64,
                  color: Colors.white54,
                ),
              ),
      ),
      if (playbackFailure != null || preparingPlayback)
        ColoredBox(
          key: const ValueKey('player-video-feedback'),
          color: stageColor.withValues(alpha: .94),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: playbackFeedback(onVideo: true),
            ),
          ),
        ),
    ],
  );

  Widget lyrics({bool currentOnly = false, bool stage = false}) =>
      ListenableBuilder(
        listenable: widget.state.playback,
        builder: (context, _) => LyricsView(
          currentOnly: currentOnly,
          stage: stage,
          onBackgroundTap: currentOnly ? toggleControls : null,
          lines: lines,
          positionMs: widget.state.positionMs,
          senior: widget.state.senior,
          enabled: !widget.state.taking,
          rangeA: widget.state.rangeA,
          rangeB: widget.state.rangeB,
          onSeek: (ms) =>
              uiTask(context, () => widget.state.command('seek', ms)),
        ),
      );

  Widget media(Song song, {required bool landscape}) {
    final state = widget.state;
    if (song.mediaType == 'VIDEO') {
      Widget frame(Widget child) => Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            bottom: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: landscape ? '退出横屏' : '全屏视频',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xB314161B),
                foregroundColor: Colors.white,
              ),
              onPressed: orientation,
              icon: Icon(
                landscape
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
              ),
            ),
          ),
        ],
      );
      if (lines.isEmpty) {
        return Align(
          alignment: Alignment.topCenter,
          child: AspectRatio(
            aspectRatio: state.videoAspect,
            child: frame(video()),
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, size) {
          final readingHeight =
              MediaQuery.textScalerOf(context)
                      .scale(_lyricFontSize(context, state.senior)) *
                  2.8 +
              48;
          final pictureHeight = largeControls
              ? math.max(48.0, size.maxHeight - readingHeight)
              : size.maxHeight * .48;
          return Column(
            children: [
              SizedBox(
                width: size.maxWidth,
                height: (size.maxWidth / state.videoAspect).clamp(
                  0.0,
                  math.max(0.0, math.min(pictureHeight, size.maxHeight - 8)),
                ),
                child: frame(video()),
              ),
              Expanded(child: lyrics()),
            ],
          );
        },
      );
    }
    if (lines.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, size) => Column(
          children: [
            if ((song.cover?.isNotEmpty ?? false) && size.maxHeight >= 340) ...[
              const SizedBox(height: 16),
              Artwork(
                state: state,
                path: song.cover,
                label: song.title,
                size: 64,
              ),
              const SizedBox(height: 8),
            ],
            Expanded(child: lyrics()),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, size) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: size.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Artwork(
                    state: state,
                    path: song.cover,
                    label: song.title,
                    size: (size.maxHeight - 112).clamp(
                      80.0,
                      (size.maxWidth - 48).clamp(80.0, 176.0),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    lyricsLoading ? '正在读取歌词…' : lyricError ?? '暂无独立歌词',
                    textAlign: TextAlign.center,
                    style: _theme.textTheme.bodyMedium?.copyWith(
                      color: _theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (lyricError != null)
                    TextButton(
                      onPressed: () => loadLyrics(song),
                      child: const Text('重试歌词'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get ready =>
      !opening &&
      openError == null &&
      ['PLAYING', 'PAUSED', 'ENDED'].contains(widget.state.playbackState) &&
      widget.state.tracks.any((t) => t['type'] == 'audio');

  bool get preparingPlayback =>
      opening ||
      ['PREPARING', 'BUFFERING'].contains(widget.state.playbackState);

  String? get playbackFailure =>
      openError ??
      (['ERROR', 'AUTH_REQUIRED'].contains(widget.state.playbackState)
          ? widget.state.playbackError.isNotEmpty
                ? widget.state.playbackError
                : '歌曲暂时无法播放'
          : null);

  Widget recordingStatus() => ListenableBuilder(
    listenable: widget.state.playback,
    builder: (context, _) => recordingStatusContent(),
  );

  Widget recordingStatusContent() {
    final state = widget.state;
    return Text(
      key: const ValueKey('player-status'),
      state.recording
          ? '正在录音 · ${durationLabel((state.singing['recordedMs'] as num? ?? 0).toInt())}'
          : state.countdown > 0
          ? '准备录音 · ${state.countdown}'
          : state.singingPhase == 'FINALIZING'
          ? '正在保留录音…'
          : state.rangeB > state.rangeA
          ? '选段 ${durationLabel(state.rangeA)} — ${durationLabel(state.rangeB)}'
          : '练唱 · 未录音',
      style: _theme.textTheme.bodySmall?.copyWith(
        color: state.taking
            ? recordingColor
            : state.rangeB > state.rangeA
            ? _theme.colorScheme.primary
            : _theme.colorScheme.onSurfaceVariant,
        fontWeight: state.taking ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  Widget progress({bool stacked = false}) => ListenableBuilder(
    listenable: widget.state.playback,
    builder: (context, _) => progressContent(stacked: stacked),
  );

  Widget progressContent({required bool stacked}) {
    final state = widget.state;
    final scheme = _theme.colorScheme;
    final timeStyle = _theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: state.senior ? 14 : 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final slider = SliderTheme(
      data: _theme.sliderTheme.copyWith(
        trackHeight: 3,
        thumbShape: _PracticeThumb(
          animate: AppMotionScope.levelOf(context) == AppMotionLevel.full,
        ),
        overlayShape: AppMotionScope.levelOf(context) == AppMotionLevel.full
            ? const RoundSliderOverlayShape(overlayRadius: 14)
            : SliderComponentShape.noOverlay,
        overlayColor: scheme.primary.withValues(alpha: .10),
        trackShape: _PracticeTrack(
          start: state.rangeA,
          end: state.rangeB,
          duration: state.durationMs,
        ),
      ),
      child: SizedBox(
        height: state.senior
            ? 56
            : stacked
            ? 44
            : 48,
        child: Semantics(
          container: true,
          child: Slider(
            key: const ValueKey('player-progress'),
            padding: stacked ? EdgeInsets.zero : null,
            semanticFormatterCallback: (v) => state.rangeB > state.rangeA
                ? '${durationLabel(v.round())}，选段 ${durationLabel(state.rangeA)} 至 ${durationLabel(state.rangeB)}'
                : durationLabel(v.round()),
            value: (drag ?? state.positionMs.toDouble()).clamp(
              0,
              state.durationMs > 0 ? state.durationMs.toDouble() : 1,
            ),
            max: state.durationMs > 0 ? state.durationMs.toDouble() : 1,
            onChangeStart: ready && !state.taking
                ? (v) {
                    controlsTimer?.cancel();
                    setState(() => drag = v);
                  }
                : null,
            onChanged: ready && !state.taking
                ? (v) => setState(() => drag = v)
                : null,
            onChangeEnd: ready && !state.taking
                ? (v) {
                    setState(() => drag = null);
                    uiTask(context, () => state.command('seek', v.round()));
                    armControls();
                  }
                : null,
          ),
        ),
      ),
    );
    final elapsed = Text(
      durationLabel((drag ?? state.positionMs).round()),
      style: timeStyle,
    );
    final duration = Text(durationLabel(state.durationMs), style: timeStyle);
    return stacked
        ? SizedBox(
            height: state.senior ? 72 : 52,
            child: Stack(
              children: [
                slider,
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Row(children: [elapsed, const Spacer(), duration]),
                ),
              ],
            ),
          )
        : Row(
            children: [
              elapsed,
              Expanded(child: slider),
              duration,
            ],
          );
  }

  double roleWidth({bool compact = false}) {
    final font = widget.state.senior
        ? 19.0
        : compact
        ? 13.0
        : 14.0;
    return 2 * (MediaQuery.textScalerOf(context).scale(font) * 2 + 24) + 8;
  }

  String? get audioRoleHint {
    final state = widget.state;
    if (!ready) return null;
    if (!state.originalMapped && !state.backingMapped) {
      return '此歌曲暂无可切换音轨';
    }
    if (state.taking) return '录音期间保持当前音轨';
    if (!state.backingMapped) return '伴奏暂不可用';
    if (!state.originalMapped) return '原唱暂不可用';
    if (!['original', 'backing'].contains(state.audioRole)) {
      return '当前音轨未标记为原唱或伴奏';
    }
    return null;
  }

  Widget roleHint() => Text(
    audioRoleHint!,
    key: const ValueKey('player-role-hint'),
    style: _theme.textTheme.bodySmall?.copyWith(
      color: _theme.colorScheme.onSurfaceVariant,
    ),
  );

  Widget roles({bool compact = false, bool stage = false}) {
    final state = widget.state;
    final choices = AppSegments<String>(
      values: const [('original', '原唱'), ('backing', '伴奏')],
      selected:
          (state.audioRole == 'original' && state.originalMapped ||
              state.audioRole == 'backing' && state.backingMapped)
          ? state.audioRole
          : '',
      senior: state.senior,
      accent: false,
      enabled: ready && !state.taking,
      disabled: {
        if (!state.originalMapped) 'original',
        if (!state.backingMapped) 'backing',
      },
      keyFor: (role) => ValueKey('player-role-$role'),
      glass:
          stage &&
          !state.senior &&
          !state.reduceTransparency &&
          !state.performanceMode,
      material: stage ? GlassMaterialSpec.standard : null,
      textStyle: _theme.textTheme.labelLarge?.copyWith(
        fontSize: state.senior
            ? 19
            : compact
            ? 13
            : 15,
      ),
      labelBuilder: (role, label) => Tooltip(
        message:
            (role == 'original' ? state.originalMapped : state.backingMapped)
            ? label
            : '$label暂不可用',
        child: stage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    role == 'original'
                        ? Icons.mic_none_rounded
                        : Icons.music_note_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(label, maxLines: 1, softWrap: false),
                ],
              )
            : Text(label, maxLines: 1, softWrap: false),
      ),
      onChanged: (role) =>
          uiTask(context, () => state.command('useRole', role)),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '播放音轨',
      child: choices,
    );
  }

  Widget playButton({
    bool text = false,
    bool compact = false,
    bool stage = false,
  }) {
    final state = widget.state;
    final label = preparingPlayback
        ? '正在准备歌曲'
        : state.isPlaying
        ? '暂停音乐'
        : '继续播放';
    return FilledButton.tonal(
      key: const ValueKey('player-play'),
      style: FilledButton.styleFrom(
        minimumSize: Size(
          stage
              ? 68
              : state.senior
              ? 56
              : text || compact
              ? 48
              : 56,
          stage
              ? 68
              : state.senior
              ? 56
              : text || compact
              ? 48
              : 56,
        ),
        padding: text
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
            : EdgeInsets.zero,
        textStyle: _theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        backgroundColor: stage
            ? _theme.colorScheme.onSurface
            : _theme.colorScheme.secondaryContainer,
        foregroundColor: stage ? pageColor : _theme.colorScheme.onSurface,
        disabledBackgroundColor: _theme.colorScheme.onSurface.withValues(
          alpha: .12,
        ),
        disabledForegroundColor: _theme.colorScheme.onSurface.withValues(
          alpha: .38,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(text ? 12 : 32),
        ),
      ),
      onPressed: ready && !state.taking
          ? () => uiTask(
              context,
              () => state.command(state.isPlaying ? 'pause' : 'play'),
            )
          : null,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: AppMotionScope.durationOf(
                context,
                const Duration(milliseconds: 140),
              ),
              child: Icon(
                preparingPlayback
                    ? Icons.hourglass_empty_rounded
                    : state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey((preparingPlayback, state.isPlaying)),
                size: stage ? 32 : 28,
              ),
            ),
            if (text) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  preparingPlayback
                      ? '加载中'
                      : state.isPlaying
                      ? '暂停'
                      : '继续',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget recordButton({bool compact = false, Key? key}) {
    final state = widget.state;
    final enabled =
        !actionBusy && (ready || state.recording || state.countdown > 0);
    return FilledButton.icon(
      key: key ?? const ValueKey('player-record'),
      style: FilledButton.styleFrom(
        minimumSize: Size(
          48,
          state.senior
              ? 56
              : compact
              ? 48
              : 54,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 20,
          vertical: 12,
        ),
        textStyle: _theme.textTheme.labelLarge?.copyWith(
          fontSize: state.senior
              ? 19
              : compact
              ? 13
              : 16,
          fontWeight: FontWeight.w500,
        ),
        backgroundColor: recordingControl,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _theme.colorScheme.onSurface.withValues(
          alpha: .05,
        ),
        disabledForegroundColor: _theme.colorScheme.onSurface.withValues(
          alpha: .38,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      onPressed: enabled ? record : null,
      icon: Icon(
        state.recording
            ? Icons.stop_rounded
            : state.countdown > 0
            ? Icons.close_rounded
            : Icons.mic_none_rounded,
        size: 18,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              state.recording
                  ? '结束录音'
                  : state.countdown > 0
                  ? '取消倒数'
                  : '开始录音',
            ),
          ),
          if (state.recording && !compact) ...[
            const SizedBox(width: 12),
            ListenableBuilder(
              listenable: state.playback,
              builder: (context, _) => Text(
                durationLabel(
                  (state.singing['recordedMs'] as num? ?? 0).toInt(),
                ),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> restart() => uiTask(context, () async {
    final state = widget.state;
    await state.command(
      'restart',
      state.rangeB > state.rangeA ? state.rangeA : 0,
    );
    await state.command('play');
  });

  Widget tools({
    bool compact = false,
    bool includeRestart = true,
    bool stage = false,
  }) {
    final state = widget.state;
    return LayoutBuilder(
      builder: (context, size) {
        final items = <(IconData, String, VoidCallback?)>[
          (
            Icons.tune_rounded,
            '调音',
            !state.taking
                ? () => panel(() => singingSettings(context, state))
                : null,
          ),
          if (includeRestart)
            (
              Icons.replay_rounded,
              '重唱',
              ready && !state.taking ? restart : null,
            ),
          (Icons.linear_scale_rounded, '选段', !state.taking ? range : null),
          (Icons.more_horiz_rounded, '更多', !state.taking ? more : null),
        ];
        final columns =
            size.maxWidth < 320 &&
                MediaQuery.textScalerOf(context).scale(16) > 22
            ? 2
            : items.length;
        return Wrap(
          children: [
            for (final tool in items)
              SizedBox(
                width: size.maxWidth / columns,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: stage
                        ? _theme.colorScheme.onSurface
                        : _theme.colorScheme.onSurfaceVariant,
                    minimumSize: Size(
                      48,
                      stage
                          ? 60
                          : state.senior
                          ? 56
                          : 48,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: _theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: state.senior
                          ? 17
                          : compact
                          ? 12
                          : stage
                          ? 14
                          : 13,
                    ),
                  ),
                  onPressed: tool.$3,
                  child: compact
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(tool.$1, size: 18),
                            const SizedBox(width: 8),
                            Flexible(child: Text(tool.$2)),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(tool.$1, size: stage ? 22 : 20),
                            SizedBox(height: stage ? 6 : 4),
                            Text(tool.$2),
                          ],
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget controls({bool compact = false}) {
    final state = widget.state;
    final large = MediaQuery.textScalerOf(context).scale(16) > 22;
    final primaryFirst = compact && (large || state.senior);
    if (!compact) {
      return DecoratedBox(
        key: const ValueKey('player-primary-controls'),
        decoration: BoxDecoration(
          color: pageColor,
          border: Border(
            top: BorderSide(
              color: _theme.colorScheme.onSurface.withValues(alpha: .08),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              progress(),
              const SizedBox(height: 8),
              LayoutBuilder(
                key: const ValueKey('player-action-group'),
                builder: (context, size) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final playFont = _theme.textTheme.labelLarge!.fontSize!;
                  final playWidth =
                      scaler.scale(playFont) * (preparingPlayback ? 3 : 2) + 52;
                  final recordWidth =
                      scaler.scale(state.senior ? 19 : 14) * 4 + 72;
                  if (playWidth + recordWidth + 12 > size.maxWidth) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        playButton(text: true),
                        const SizedBox(height: 8),
                        recordButton(),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: playWidth, child: playButton(text: true)),
                      const SizedBox(width: 12),
                      Expanded(child: recordButton()),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!primaryFirst) ...[progress(), const SizedBox(height: 8)],
          LayoutBuilder(
            builder: (context, size) {
              final choiceWidth = roleWidth(compact: true)
                  .clamp(0.0, size.maxWidth);
              final primary = Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  playButton(compact: true),
                  SizedBox(width: choiceWidth, child: roles(compact: true)),
                  if (!state.recording) recordButton(compact: true),
                ],
              );
              if (!state.senior && !large && size.maxWidth >= 680) {
                return Row(
                  children: [
                    primary,
                    const Spacer(),
                    SizedBox(width: 284, child: tools(compact: true)),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primary,
                  if (primaryFirst) progress(),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: size.maxWidth.clamp(
                        0.0,
                        state.senior ? 500.0 : 380.0,
                      ),
                      child: tools(compact: true),
                    ),
                  ),
                ],
              );
            },
          ),
          if (audioRoleHint != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: roleHint()),
          ],
          if (state.singing['clipped'] == true) const Text('声音偏大，请稍微远离麦克风'),
        ],
      ),
    );
  }

  Widget practiceTools() {
    final scheme = _theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.state.taking) ...[
            recordingStatus(),
            const SizedBox(height: 8),
          ],
          LayoutBuilder(
            builder: (context, size) {
              final label = Text(
                '播放音轨',
                style: _theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              );
              final labelWidth =
                  MediaQuery.textScalerOf(context)
                      .scale(_theme.textTheme.bodySmall!.fontSize!) *
                  4;
              if (labelWidth + 12 + roleWidth() > size.maxWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [label, const SizedBox(height: 8), roles()],
                );
              }
              return Row(
                children: [
                  label,
                  const Spacer(),
                  SizedBox(width: roleWidth(), child: roles()),
                ],
              );
            },
          ),
          if (audioRoleHint != null) ...[const SizedBox(height: 8), roleHint()],
          const SizedBox(height: 8),
          tools(compact: !largeControls),
          if (widget.state.singing['clipped'] == true)
            Text('声音偏大，请稍微远离麦克风', style: _theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget stageIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) => Glass(
    state: widget.state,
    radius: 24,
    material: GlassMaterialSpec.standard,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: color ?? _theme.colorScheme.onSurface,
      icon: AnimatedSwitcher(
        duration: AppMotionScope.durationOf(
          context,
          const Duration(milliseconds: 140),
        ),
        child: Icon(icon, key: ValueKey(icon), size: 21),
      ),
    ),
  );

  Widget stageHeader(Song song) => SizedBox(
    height: widget.state.senior ? 64 : 56,
    child: Row(
      children: [
        const SizedBox(width: 20),
        stageIcon(
          tooltip: '收起演唱',
          onPressed: close,
          icon: Icons.keyboard_arrow_down_rounded,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => setState(() => stageDragging = true),
            onVerticalDragUpdate: (details) => setState(
              () => stageDrag = (stageDrag + details.delta.dy).clamp(
                0,
                MediaQuery.sizeOf(context).height * .65,
              ),
            ),
            onVerticalDragCancel: () => setState(() {
              stageDragging = false;
              stageDrag = 0;
            }),
            onVerticalDragEnd: (details) {
              final dismiss =
                  stageDrag >= 80 ||
                  (stageDrag > 28 && details.velocity.pixelsPerSecond.dy > 600);
              setState(() {
                stageDragging = false;
                if (!dismiss) stageDrag = 0;
              });
              if (dismiss) close();
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '正在练唱',
                  textAlign: TextAlign.center,
                  style: _theme.textTheme.bodyMedium?.copyWith(
                    color: _theme.colorScheme.onSurface,
                    fontSize: widget.state.senior ? 17 : 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                Text(
                  widget.state.serverName.isEmpty
                      ? '家庭曲库'
                      : widget.state.serverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _theme.textTheme.bodySmall?.copyWith(
                    color: _theme.colorScheme.onSurfaceVariant,
                    fontSize: widget.state.senior ? 14 : 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        stageIcon(
          tooltip: '歌曲信息',
          onPressed: () => panel(
            () => showSong(context, widget.state, song, credits: lyricCredits),
          ),
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(width: 20),
      ],
    ),
  );

  Widget stageSong(Song song, {bool centered = false}) {
    final title = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          song.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: _theme.textTheme.headlineSmall?.copyWith(
            fontSize: centered
                ? 26
                : MediaQuery.sizeOf(context).width < 375
                ? 22
                : 26,
            fontWeight: FontWeight.w600,
            height: 1.18,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          song.artist.isEmpty ? '歌手未知' : song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: _theme.textTheme.bodyMedium?.copyWith(
            color: _theme.colorScheme.onSurfaceVariant,
            fontSize: widget.state.senior ? 17 : 15,
            height: 1.3,
          ),
        ),
      ],
    );
    final favorite = IconButton(
      tooltip: widget.state.isFavorite(song) ? '取消收藏' : '收藏歌曲',
      onPressed: () => uiTask(context, () => widget.state.favorite(song)),
      icon: Icon(
        widget.state.isFavorite(song)
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
      ),
      color: widget.state.isFavorite(song)
          ? _theme.colorScheme.primary
          : _theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: centered
          ? Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: title,
                ),
                Align(alignment: Alignment.centerRight, child: favorite),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                favorite,
              ],
            ),
    );
  }

  Widget stageVideo() => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadii.artwork),
    child: Stack(
      fit: StackFit.expand,
      children: [
        video(),
        Positioned(
          right: 10,
          bottom: 8,
          child: Glass(
            state: widget.state,
            radius: 24,
            material: GlassMaterialSpec.mediaOverlay,
            tint: const Color(0xFF2C2C2E),
            child: IconButton(
              tooltip: '全屏视频',
              onPressed: orientation,
              color: AppPalette.stageText,
              icon: const Icon(Icons.fullscreen_rounded, size: 22),
            ),
          ),
        ),
      ],
    ),
  );

  double stageSongHeight(Song song, double width, {bool centered = false}) {
    double measure(String text, TextStyle? style, int maxLines) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: math.max(1, width - (centered ? 136 : 100)));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final title = measure(
      song.title,
      _theme.textTheme.headlineSmall?.copyWith(
        fontSize: centered
            ? 26
            : MediaQuery.sizeOf(context).width < 375
            ? 22
            : 26,
        fontWeight: FontWeight.w600,
        height: 1.18,
        letterSpacing: -.4,
      ),
      2,
    );
    final artist = measure(
      song.artist.isEmpty ? '歌手未知' : song.artist,
      _theme.textTheme.bodyMedium?.copyWith(
        fontSize: widget.state.senior ? 17 : 15,
        height: 1.3,
      ),
      1,
    );
    return 20 + math.max(48, title + 4 + artist);
  }

  Widget stageMedia(Song song) => LayoutBuilder(
    builder: (context, size) {
      final videoSong = song.mediaType == 'VIDEO';
      final titleHeight = stageSongHeight(
        song,
        size.maxWidth,
        centered: !videoSong,
      );
      final contentWidth = math.max(1.0, size.maxWidth - 40);
      final hasFeedback =
          recordingError != null ||
          widget.state.playbackError.isNotEmpty ||
          (!videoSong && (playbackFailure != null || preparingPlayback));
      final readingHeight =
          lines.isNotEmpty || hasFeedback || lyricsLoading || lyricError != null
          ? 64.0
          : videoSong
          ? 0.0
          : 32.0;
      final available = math.max(
        96.0,
        size.maxHeight - titleHeight - readingHeight,
      );
      final mediaHeight = videoSong
          ? math.min(contentWidth / widget.state.videoAspect, available)
          : math.min(208.0, available);
      final artwork = videoSong
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(height: mediaHeight, child: stageVideo()),
            )
          : Center(
              child: Artwork(
                state: widget.state,
                path: song.cover,
                label: song.title,
                size: mediaHeight,
              ),
            );
      final heading = stageSong(song, centered: !videoSong);
      final reading = hasFeedback
          ? SingleChildScrollView(child: status(song))
          : lines.isNotEmpty
          ? lyrics(stage: true)
          : videoSong && !lyricsLoading && lyricError == null
          ? const SizedBox.shrink()
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lyricsLoading
                          ? '正在读取歌词…'
                          : lyricError ?? (videoSong ? '' : '暂无独立歌词'),
                      textAlign: TextAlign.center,
                      style: _theme.textTheme.bodySmall?.copyWith(
                        color: _theme.colorScheme.onSurfaceVariant,
                        fontSize: widget.state.senior ? 14 : 12,
                      ),
                    ),
                    if (lyricError != null)
                      TextButton(
                        onPressed: () => loadLyrics(song),
                        child: const Text('重试歌词'),
                      ),
                  ],
                ),
              ),
            );
      if (mediaHeight + titleHeight + readingHeight > size.maxHeight) {
        return SingleChildScrollView(
          child: Column(
            children: [
              artwork,
              heading,
              SizedBox(height: math.max(96, readingHeight), child: reading),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          artwork,
          heading,
          Expanded(child: reading),
        ],
      );
    },
  );

  Widget stageStatus() => ListenableBuilder(
    listenable: widget.state.playback,
    builder: (context, _) => stageStatusContent(),
  );

  Widget stageStatusContent() {
    final state = widget.state;
    final recording = state.recording;
    final practice = preparingPlayback
        ? '正在准备'
        : state.isPlaying
        ? '练唱中'
        : state.playbackState == 'ENDED'
        ? '播放结束'
        : '已暂停';
    final capture = recording
        ? '正在录音 · ${durationLabel((state.singing['recordedMs'] as num? ?? 0).toInt())}'
        : state.countdown > 0
        ? '准备录音 · ${state.countdown}'
        : state.singingPhase == 'FINALIZING'
        ? '正在保留录音…'
        : state.rangeB > state.rangeA
        ? '选段 ${durationLabel(state.rangeA)} — ${durationLabel(state.rangeB)}'
        : '尚未录音';
    return Semantics(
      key: const ValueKey('player-status'),
      liveRegion: state.taking,
      child: Row(
        children: [
          const Icon(Icons.circle, size: 5, color: recordingControl),
          const SizedBox(width: 7),
          Text(
            practice,
            style: _theme.textTheme.bodySmall?.copyWith(
              color: _theme.colorScheme.onSurfaceVariant,
              fontSize: state.senior ? 14 : 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: AppMotionScope.durationOf(
                context,
                const Duration(milliseconds: 160),
              ),
              style: _theme.textTheme.bodySmall!.copyWith(
                fontSize: state.senior ? 14 : 12,
                color: state.taking
                    ? recordingColor
                    : _theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: Text(capture, textAlign: TextAlign.end),
            ),
          ),
        ],
      ),
    );
  }

  Widget seekButton(int seconds) => IconButton(
    key: ValueKey('player-seek-$seconds'),
    tooltip: seconds < 0 ? '后退15秒' : '前进15秒',
    onPressed: ready && !widget.state.taking
        ? () => uiTask(
            context,
            () => widget.state.command(
              'seek',
              (widget.state.positionMs + seconds * 1000).clamp(
                0,
                widget.state.durationMs,
              ),
            ),
          )
        : null,
    icon: SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            seconds < 0
                ? Icons.rotate_left_rounded
                : Icons.rotate_right_rounded,
            size: 32,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '15',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  Widget stageControls() {
    final state = widget.state;
    return Padding(
      key: const ValueKey('player-primary-controls'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        key: const ValueKey('player-action-group'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          progress(stacked: true),
          const SizedBox(height: 2),
          stageStatus(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              seekButton(-15),
              const SizedBox(width: 36),
              playButton(stage: true),
              const SizedBox(width: 36),
              seekButton(15),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '演唱模式',
            style: _theme.textTheme.bodySmall?.copyWith(
              color: _theme.colorScheme.onSurfaceVariant,
              fontSize: state.senior ? 14 : 12,
            ),
          ),
          const SizedBox(height: 6),
          roles(stage: true),
          if (audioRoleHint != null) ...[const SizedBox(height: 8), roleHint()],
          const SizedBox(height: 12),
          Glass(
            state: state,
            radius: AppRadii.control,
            material: GlassMaterialSpec.standard,
            enabled: !state.taking,
            child: tools(stage: true),
          ),
          if (state.singing['clipped'] == true)
            Text('声音偏大，请稍微远离麦克风', style: _theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          recordButton(),
        ],
      ),
    );
  }

  Widget portrait(Song song, BoxConstraints size) {
    if (largeControls || size.maxHeight < 620) {
      return accessiblePortrait(song, size);
    }
    return AnimatedContainer(
      duration: stageDragging
          ? Duration.zero
          : AppMotionScope.durationOf(context, AppMotion.release),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, stageDrag, 0),
      child: Stack(
        children: [
          Column(
            children: [
              stageHeader(song),
              Expanded(
                child: SizedBox(
                  key: const ValueKey('player-content'),
                  width: size.maxWidth,
                  child: stageMedia(song),
                ),
              ),
              stageControls(),
            ],
          ),
          if (widget.state.countdown > 0) Positioned.fill(child: countdown()),
        ],
      ),
    );
  }

  Widget accessiblePortrait(Song song, BoxConstraints size) => Stack(
    children: [
      Positioned.fill(
        child: Column(
          children: [
            header(song, dense: size.maxHeight < 680),
            if (widget.state.taking)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: recordingStatus(),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, available) {
                  // Only the content scrolls. Playback and the explicit microphone
                  // action stay in the safe area, including at large text sizes.
                  final videoOnly = song.mediaType == 'VIDEO' && lines.isEmpty;
                  final mediaHeight = videoOnly
                      ? available.maxWidth / widget.state.videoAspect
                      : math.max(
                          math.min(
                            available.maxHeight,
                            largeControls ? 280.0 : 240.0,
                          ),
                          available.maxHeight - (largeControls ? 208.0 : 160.0),
                        );
                  return SingleChildScrollView(
                    key: const ValueKey('player-content'),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: available.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: mediaHeight,
                            child: media(song, landscape: false),
                          ),
                          status(song),
                          practiceTools(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            controls(),
          ],
        ),
      ),
      if (widget.state.countdown > 0) Positioned.fill(child: countdown()),
    ],
  );

  Future<void> retryPlayback({bool compatible = false}) async {
    if (!widget.state.authenticated) {
      await openConnection(context, widget.state);
      if (!mounted || !widget.state.authenticated) return;
    }
    await prepare(compatible: compatible, retry: true);
  }

  Widget playbackFeedback({bool onVideo = false}) {
    final failure = playbackFailure;
    final foreground = onVideo ? Colors.white : _theme.colorScheme.onSurface;
    if (failure != null) {
      return Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failure,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: retryPlayback,
                  style: TextButton.styleFrom(
                    foregroundColor: onVideo ? Colors.white : null,
                  ),
                  child: Text(widget.state.authenticated ? '重试播放' : '登录后重试'),
                ),
                if (widget.state.authenticated)
                  TextButton(
                    onPressed: () => retryPlayback(compatible: true),
                    style: TextButton.styleFrom(
                      foregroundColor: onVideo ? Colors.white70 : null,
                    ),
                    child: const Text('兼容播放'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (preparingPlayback) {
      return Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onVideo)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              widget.state.playbackState == 'BUFFERING' ? '正在缓冲…' : '正在准备歌曲…',
              style: _theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget status(Song song) {
    final state = widget.state;
    if (playbackFailure != null || preparingPlayback) {
      // Video owns its feedback so a black frame always explains its state.
      if (song.mediaType == 'VIDEO') return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: playbackFeedback(),
      );
    }
    final message = state.playbackError.isNotEmpty
        ? state.playbackError
        : recordingError;
    if (message != null && message.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(message, textAlign: TextAlign.center),
      );
    }
    return const SizedBox.shrink();
  }

  Widget countdown() => ColoredBox(
    color: const Color(0xDB0C1017),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('准备好，跟着音乐唱'),
              Text(
                '${widget.state.countdown}',
                style: const TextStyle(
                  fontSize: 76,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Text('倒数结束后开始录音'),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white12,
                ),
                onPressed: record,
                child: const Text('取消录音'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget immersiveMedia(Song song) {
    final state = widget.state;
    final top = controlsVisible
        ? (state.recording ? 122.0 : 70.0)
        : state.recording
        ? 70.0
        : 12.0;
    final bottom = controlsVisible ? dockHeight + 8 : 12.0;
    if (song.mediaType == 'VIDEO') {
      return Stack(
        children: [
          Positioned.fill(child: video()),
          // Own the hit surface above AndroidView. A detector around a platform
          // view can lose taps to its native gesture recognizer on real devices.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: playbackFailure != null || preparingPlayback,
              child: GestureDetector(
                key: const ValueKey('player-video-tap-layer'),
                behavior: HitTestBehavior.opaque,
                onTap: toggleControls,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
          if (lines.isNotEmpty && playbackFailure == null && !preparingPlayback)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(48, top, 48, bottom),
                child: lyrics(currentOnly: true),
              ),
            ),
        ],
      );
    }
    return ColoredBox(
      color: stageColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(40, top, 40, bottom),
        child: lines.isNotEmpty
            ? lyrics()
            : LayoutBuilder(
                builder: (context, size) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: size.maxHeight),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Artwork(
                            state: state,
                            path: song.cover,
                            label: song.title,
                            size: size.maxHeight.clamp(64.0, 200.0),
                          ),
                          const SizedBox(width: 24),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  style: _theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  lyricsLoading
                                      ? '正在读取歌词…'
                                      : lyricError ?? '没有独立歌词，听着旋律轻松跟唱',
                                  style: _theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white60,
                                  ),
                                ),
                                if (lyricError != null)
                                  TextButton(
                                    onPressed: () => loadLyrics(song),
                                    child: const Text('重试歌词'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget chrome(Widget child) => IgnorePointer(
    ignoring: !controlsVisible,
    child: ExcludeSemantics(
      excluding: !controlsVisible,
      child: AnimatedOpacity(
        opacity: controlsVisible ? 1 : 0,
        duration: AppMotionScope.durationOf(
          context,
          const Duration(milliseconds: 180),
        ),
        child: child,
      ),
    ),
  );

  Widget immersive(Song song, BoxConstraints size) {
    measureChrome(size.maxHeight);
    // Keep a real lyric reading area even on a short screen with large type.
    // Extra controls scroll inside their floating surface rather than shrinking lyrics to zero.
    final textScale = MediaQuery.textScalerOf(context).scale(28);
    final readingHeight = (textScale * 2.7).clamp(80.0, size.maxHeight * .45);
    final topClearance = widget.state.recording ? 122.0 : 70.0;
    final maxDockHeight = (size.maxHeight - topClearance - readingHeight - 8)
        .clamp(72.0, size.maxHeight * .65);
    return Listener(
      onPointerDown: (_) {
        pointerHeld = true;
        keyboardNavigation = false;
        controlsTimer?.cancel();
      },
      onPointerUp: (_) {
        pointerHeld = false;
        armControls();
      },
      onPointerCancel: (_) {
        pointerHeld = false;
        armControls();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            keyboardNavigation = true;
            revealControls();
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: SizedBox.expand(
                key: const ValueKey('player-landscape-surface'),
                child: song.mediaType == 'VIDEO'
                    ? immersiveMedia(song)
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: toggleControls,
                        child: immersiveMedia(song),
                      ),
              ),
            ),
            // Accessible users can always summon controls without finding a gesture.
            Positioned.fill(
              child: Semantics(
                container: true,
                label: controlsVisible ? '隐藏播放控制' : '显示播放控制',
                button: true,
                onTap: revealControls,
                child: const IgnorePointer(child: SizedBox.expand()),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: chrome(
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xD9090C11), Color(0x00090C11)],
                    ),
                  ),
                  child: header(song, compact: true),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: chrome(
                ConstrainedBox(
                  key: dockKey,
                  constraints: BoxConstraints(maxHeight: maxDockHeight),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: stageColor.withValues(
                        alpha: widget.state.reduceTransparency ? 1 : .96,
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: .08),
                        ),
                      ),
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('landscape-controls'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [status(song), controls(compact: true)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.state.recording)
              Positioned(
                top: controlsVisible ? 70 : 10,
                right: 16,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: size.maxWidth - 32),
                  child: DecoratedBox(
                    key: const ValueKey('landscape-recording'),
                    decoration: BoxDecoration(
                      color: const Color(0xF219141D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: coral.withValues(alpha: .3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      child: Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          recordingStatus(),
                          recordButton(
                            key: const ValueKey('player-record'),
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.state.countdown > 0) Positioned.fill(child: countdown()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      return Theme(
        data: _theme,
        child: Builder(
          builder: (context) => ListenableBuilder(
            listenable: widget.state,
            builder: (context, _) {
              final state = widget.state;
              final song = opening || openError != null
                  ? widget.song ?? state.current
                  : state.current ?? widget.song;
              return PopScope(
                canPop: allowPop,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) close();
                },
                child: Scaffold(
                  backgroundColor: pageColor,
                  appBar: AppBar(
                    toolbarHeight: 0,
                    backgroundColor: pageColor,
                    systemOverlayStyle: _theme.brightness == Brightness.dark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark,
                  ),
                  body: AppEnvironment(
                    solid:
                        state.senior ||
                        state.reduceTransparency ||
                        state.performanceMode ||
                        MediaQuery.highContrastOf(context),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (song != null && song.mediaType != 'VIDEO')
                          Positioned.fill(
                            child: AmbientArtwork(state: state, song: song),
                          ),
                        SafeArea(
                          child: song == null
                              ? Notice(
                                  '还没有正在演唱的歌曲。',
                                  action: close,
                                  label: '返回曲库',
                                )
                              : LayoutBuilder(
                                  builder: (context, size) {
                                    final wide = size.maxWidth > size.maxHeight;
                                    accessibleControls =
                                        MediaQuery.accessibleNavigationOf(
                                          context,
                                        ) ||
                                        MediaQuery.viewInsetsOf(context)
                                                .bottom >
                                            0;
                                    if (accessibleControls) {
                                      controlsVisible = true;
                                      controlsTimer?.cancel();
                                    }
                                    updateLayout(wide);
                                    if (wide) return immersive(song, size);
                                    measureChrome(size.maxHeight);
                                    return portrait(song, size);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

void _paintPracticeBracket(
  Canvas canvas,
  Offset center, {
  required bool start,
  required Color color,
  required double height,
}) {
  final cap = start ? 4.0 : -4.0;
  canvas.drawPath(
    Path()
      ..moveTo(center.dx + cap, center.dy - height / 2)
      ..lineTo(center.dx, center.dy - height / 2)
      ..lineTo(center.dx, center.dy + height / 2)
      ..lineTo(center.dx + cap, center.dy + height / 2),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round,
  );
}

class _PracticeThumb extends SliderComponentShape {
  const _PracticeThumb({required this.animate});
  final bool animate;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = Color.lerp(
      sliderTheme.disabledThumbColor,
      sliderTheme.thumbColor,
      enableAnimation.value,
    )!;
    final radius = 5.0 + (animate ? activationAnimation.value * 2 : 0.0);
    context.canvas.drawCircle(center, radius, Paint()..color = color);
  }
}

class _PracticeTrack extends RoundedRectSliderTrackShape {
  const _PracticeTrack({
    required this.start,
    required this.end,
    required this.duration,
  });
  final int start, end, duration;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (duration <= 0 || end <= start) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final color = sliderTheme.activeTrackColor ?? berry;
    for (final boundary in [(start, true), (end, false)]) {
      final fraction = (boundary.$1 / duration).clamp(0.0, 1.0);
      final rtl = textDirection == TextDirection.rtl;
      _paintPracticeBracket(
        context.canvas,
        Offset(
          rect.left + rect.width * (rtl ? 1 - fraction : fraction),
          rect.center.dy,
        ),
        start: rtl ? !boundary.$2 : boundary.$2,
        color: color,
        height: 12,
      );
    }
  }
}

class _LyricRangePainter extends CustomPainter {
  const _LyricRangePainter({
    required this.start,
    required this.end,
    required this.color,
  });
  final bool start, end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (start) {
      _paintPracticeBracket(
        canvas,
        Offset(-12, size.height / 2),
        start: true,
        color: color,
        height: 32,
      );
    }
    if (end) {
      _paintPracticeBracket(
        canvas,
        Offset(size.width + 12, size.height / 2),
        start: false,
        color: color,
        height: 32,
      );
    }
  }

  @override
  bool shouldRepaint(_LyricRangePainter oldDelegate) =>
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      color != oldDelegate.color;
}

double _lyricFontSize(BuildContext context, bool senior, {bool active = true}) {
  if (senior) return active ? 32 : 23;
  final narrow = MediaQuery.sizeOf(context).width < 375;
  return active ? (narrow ? 18 : 20) : (narrow ? 15 : 16);
}

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lines,
    required this.positionMs,
    required this.senior,
    required this.enabled,
    required this.onSeek,
    this.currentOnly = false,
    this.stage = false,
    this.onBackgroundTap,
    this.rangeA = 0,
    this.rangeB = 0,
  });
  final bool currentOnly;
  final bool stage;
  final VoidCallback? onBackgroundTap;
  final List<TextLine> lines;
  final int positionMs;
  final int rangeA, rangeB;
  final bool senior, enabled;
  final ValueChanged<int> onSeek;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final controller = ScrollController();
  int lastActive = -2;
  double lastHeight = 0;
  List<TextLine>? measuredLines;
  double measuredWidth = 0;
  TextStyle? measuredStyle;
  TextScaler? measuredScaler;
  TextDirection? measuredDirection;
  bool? measuredSenior;
  final heights = <double>[];
  final textHeights = <double>[];
  final offsets = <double>[];
  DateTime manualUntil = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines) &&
        !widget.lines.any((line) => line.startMs != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final scaler = MediaQuery.textScalerOf(context);
      final scheme = Theme.of(context).colorScheme;
      final timed = widget.lines.any((line) => line.startMs != null);
      final hasRange = timed && widget.rangeB > widget.rangeA;
      final rangeStart = hasRange
          ? widget.lines.lastIndexWhere(
              (line) => line.startMs! <= widget.rangeA,
            )
          : -1;
      final rangeEnd = hasRange
          ? widget.lines.lastIndexWhere((line) => line.startMs! < widget.rangeB)
          : -1;
      final active = timed
          ? widget.lines.lastIndexWhere(
              (line) => line.startMs! <= widget.positionMs,
            )
          : -1;
      if (widget.currentOnly && timed) {
        if (widget.lines.isEmpty) return const SizedBox.shrink();
        final index = active < 0 ? 0 : active;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onBackgroundTap,
          child: SingleChildScrollView(
            key: const ValueKey('lyrics-viewport'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.maxHeight),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Semantics(
                  button: widget.enabled,
                  selected: true,
                  child: InkWell(
                    onTap: widget.enabled
                        ? () => widget.onSeek(
                            widget.lines[index].startMs!.clamp(0, 1 << 53),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        key: ValueKey('lyrics-line-$index'),
                        widget.lines[index].text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.senior ? 26 : 20,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                            Shadow(color: Colors.black87, blurRadius: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      TextStyle styleFor(int index) => TextStyle(
        fontSize: widget.currentOnly
            ? (widget.senior ? 26 : 20)
            : widget.stage && !widget.senior
            ? (index == active ? 26 : 18)
            : _lyricFontSize(context, widget.senior, active: index == active),
        height: 1.4,
        fontWeight: index == active
            ? (widget.senior || widget.stage
                  ? FontWeight.w600
                  : FontWeight.w500)
            : FontWeight.w400,
      );
      final measurementStyle = styleFor(timed ? active : -2);
      final direction = Directionality.of(context);
      final measurementsChanged =
          !identical(measuredLines, widget.lines) ||
          measuredWidth != size.maxWidth ||
          measuredStyle != measurementStyle ||
          measuredScaler != scaler ||
          measuredDirection != direction ||
          measuredSenior != widget.senior;
      // Parsed timelines are replaced when a track changes. Position updates
      // reuse their geometry instead of laying out the entire song each tick.
      if (measurementsChanged) {
        measuredLines = widget.lines;
        measuredWidth = size.maxWidth;
        measuredStyle = measurementStyle;
        measuredScaler = scaler;
        measuredDirection = direction;
        measuredSenior = widget.senior;
        heights.clear();
        textHeights.clear();
        offsets.clear();
        var offset = 0.0;
        for (final line in widget.lines) {
          final painter = TextPainter(
            text: TextSpan(
              text: line.text.isEmpty ? ' ' : line.text,
              // Reserve the active size so highlighting keeps stable geometry.
              style: measurementStyle,
            ),
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: (size.maxWidth - 48).clamp(1, double.infinity));
          final height = math.max(
            widget.senior ? 56.0 : 48.0,
            painter.height + (widget.senior ? 28 : 20),
          );
          offsets.add(offset);
          heights.add(height);
          textHeights.add(painter.height);
          offset += height;
          painter.dispose();
        }
      }
      final topPadding = timed ? size.maxHeight * .16 : 16.0;
      if (timed &&
          (active != lastActive ||
              measurementsChanged ||
              size.maxHeight != lastHeight)) {
        lastActive = active;
        lastHeight = size.maxHeight;
        final offset = active < 0 ? 0.0 : offsets[active];
        final activeHeight = active < 0 ? 0.0 : heights[active];
        final textHeight = active < 0 ? 0.0 : textHeights[active];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !controller.hasClients ||
              DateTime.now().isBefore(manualUntil)) {
            return;
          }
          final target =
              (active < 0
                      ? 0.0
                      : topPadding +
                            offset +
                            (textHeight > size.maxHeight
                                ? (activeHeight - textHeight) / 2
                                : activeHeight / 2 - size.maxHeight / 2))
                  .clamp(0.0, controller.position.maxScrollExtent);
          if (widget.senior ||
              scaler.scale(16) > 23 ||
              AppMotionScope.levelOf(context) != AppMotionLevel.full) {
            controller.jumpTo(target);
          } else {
            controller.animateTo(
              target,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
      final viewport = NotificationListener<ScrollStartNotification>(
        onNotification: (notice) {
          if (notice.dragDetails != null) {
            manualUntil = DateTime.now().add(const Duration(seconds: 4));
          }
          return false;
        },
        child: ListView.builder(
          key: const ValueKey('lyrics-viewport'),
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            24,
            topPadding,
            24,
            timed ? size.maxHeight * .58 : 16,
          ),
          itemCount: widget.lines.length,
          itemExtentBuilder: (index, dimensions) => heights[index],
          itemBuilder: (context, index) => Semantics(
            button: widget.enabled && timed,
            selected: timed ? index == active : null,
            label: index == rangeStart && index == rangeEnd
                ? '选段起止句'
                : index == rangeStart
                ? '选段起句'
                : index == rangeEnd
                ? '选段结束句'
                : null,
            child: InkWell(
              onTap: widget.enabled && timed
                  ? () {
                      manualUntil = DateTime.fromMillisecondsSinceEpoch(0);
                      widget.onSeek(
                        widget.lines[index].startMs!.clamp(0, 1 << 53),
                      );
                    }
                  : null,
              child: CustomPaint(
                painter: _LyricRangePainter(
                  start: index == rangeStart,
                  end: index == rangeEnd,
                  color: scheme.primary,
                ),
                child: Align(
                  alignment: widget.stage || widget.currentOnly
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Text(
                    key: ValueKey('lyrics-line-$index'),
                    widget.lines[index].text,
                    textAlign: widget.stage || widget.currentOnly
                        ? TextAlign.center
                        : TextAlign.start,
                    style: styleFor(index).copyWith(
                      color: widget.currentOnly
                          ? Colors.white
                          : index == active
                          ? (widget.stage ? scheme.onSurface : scheme.primary)
                          : scheme.onSurfaceVariant,
                      shadows: widget.currentOnly
                          ? const [Shadow(color: Colors.black, blurRadius: 6)]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return widget.stage
          ? ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, .07, .88, 1],
              ).createShader(bounds),
              child: viewport,
            )
          : widget.currentOnly
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: widget.onBackgroundTap,
              child: viewport,
            )
          : viewport;
    },
  );
}
