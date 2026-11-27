import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../library/connection.dart';
import '../player/player_page.dart';

Future<bool> microphonePermission(BuildContext context, AppState state) async {
  final result = await state.sing('permission');
  if (result == 'granted') return true;
  if (!context.mounted) return false;
  await showAppDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('需要麦克风才能录音'),
      content: Text(
        result == 'settings' ? '请在系统设置中允许麦克风。不开启也能继续练唱。' : '没有获得麦克风权限，仍可继续练唱。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('继续练唱'),
        ),
        if (result == 'settings')
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              state.sing('settings');
            },
            child: const Text('打开设置'),
          ),
      ],
    ),
  );
  return false;
}

Future<bool> keepCurrentRecording(BuildContext context, AppState state) async {
  if (state.taking) {
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('先结束当前录音？'),
        content: const Text('已录下的声音会保留在“作品 · 草稿”，之后可以回听和保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束并保留草稿'),
          ),
        ],
      ),
    );
    if (yes != true) return false;
    if (state.countdown > 0) await state.command('cancelCountdown');
    if (state.recording) await state.endTake();
  }
  for (
    var i = 0;
    i < 80 && (state.taking || state.singingPhase == 'RENDERING');
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (state.taking || state.singingPhase == 'RENDERING') {
    throw const FormatException('录音仍在处理中，请稍后重试。');
  }
  return context.mounted;
}

Future<void> openSinging(BuildContext context, AppState state, Song song) =>
    uiTask(context, () async {
      final same =
          state.current?.id == song.id &&
          state.workId.isEmpty &&
          state.playbackInstanceId == state.instanceId &&
          !['ERROR', 'AUTH_REQUIRED', 'IDLE'].contains(state.playbackState);
      if (!same && !await keepCurrentRecording(context, state)) return;
      if (!context.mounted) return;
      if (!same && !state.authenticated) {
        await openConnection(context, state);
        if (!state.authenticated || !context.mounted) return;
      }
      if (same && !state.taking && !state.isPlaying) {
        if (state.playbackState == 'ENDED') await state.command('seek', 0);
        await state.command('play');
      }
      if (!context.mounted) return;
      await Navigator.push(
        context,
        playerStageRoute<void>(
          settings: const RouteSettings(name: 'player'),
          builder: (_) => PlayerPage(state: state, song: same ? null : song),
        ),
      );
    });

class _SoundValue extends StatelessWidget {
  const _SoundValue({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        value,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Equal-width actions at normal text sizes, with room to read at large sizes.
class _SoundActions extends StatelessWidget {
  const _SoundActions({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(14) > 21) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class _CenteredTrackShape extends RoundedRectSliderTrackShape {
  const _CenteredTrackShape({
    required this.originFraction,
    required this.activeColor,
  });

  final double originFraction;
  final Color activeColor;

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
    double additionalActiveTrackHeight = 0,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(trackRect.height / 2);
    final inactiveColor = Color.lerp(
      sliderTheme.disabledInactiveTrackColor ??
          Colors.white.withValues(alpha: .08),
      sliderTheme.inactiveTrackColor ?? Colors.white.withValues(alpha: .14),
      enableAnimation.value,
    )!;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = inactiveColor,
    );

    final fraction = textDirection == TextDirection.rtl
        ? 1 - originFraction
        : originFraction;
    final originX = trackRect.left + trackRect.width * fraction.clamp(0.0, 1.0);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(originX, trackRect.center.dy),
          width: 1.5,
          height: 10,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white.withValues(alpha: .28),
    );

    if ((thumbCenter.dx - originX).abs() > 1.5) {
      final activeLeft = math.min(originX, thumbCenter.dx);
      final activeRight = math.max(originX, thumbCenter.dx);
      final activeRect = Rect.fromLTRB(
        activeLeft,
        trackRect.top,
        activeRight,
        trackRect.bottom,
      );
      final fillColor = Color.lerp(
        sliderTheme.disabledActiveTrackColor ??
            activeColor.withValues(alpha: .35),
        activeColor,
        enableAnimation.value,
      )!;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()..color = fillColor,
      );
    }
  }
}

Future<void> singingSettings(BuildContext context, AppState state) =>
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SingingSettingsSheet(state: state),
    );

class _SingingSettingsSheet extends StatefulWidget {
  const _SingingSettingsSheet({required this.state});
  final AppState state;

  @override
  State<_SingingSettingsSheet> createState() => _SingingSettingsSheetState();
}

class _SingingSettingsSheetState extends State<_SingingSettingsSheet> {
  bool _showMicTest = false;
  bool _showAudioSubpage = false;
  bool _micStarted = false;
  bool _micBusy = false;
  LocalHistoryEntry? _audioHistoryEntry;

  @override
  void dispose() {
    if (_micStarted && widget.state.singingPhase == 'TESTING') {
      unawaited(widget.state.sing('test', {'start': false}));
    }
    super.dispose();
  }

  void _openAudioSubpage() {
    if (_showAudioSubpage) return;
    final entry = LocalHistoryEntry(
      onRemove: () {
        if (!mounted) return;
        setState(() {
          _showAudioSubpage = false;
          _audioHistoryEntry = null;
        });
      },
    );
    _audioHistoryEntry = entry;
    ModalRoute.of(context)?.addLocalHistoryEntry(entry);
    setState(() => _showAudioSubpage = true);
  }

  Future<void> _toggleMicTest() => uiTask(context, () async {
    if (_micBusy) return;
    setState(() => _micBusy = true);
    try {
      if (widget.state.singingPhase == 'TESTING') {
        await widget.state.sing('test', {'start': false});
        _micStarted = false;
      } else if (await microphonePermission(context, widget.state) && mounted) {
        await widget.state.sing('test', {'start': true});
        _micStarted = true;
      }
    } finally {
      if (mounted) setState(() => _micBusy = false);
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, widget.state.performance]),
    builder: (context, _) {
      final state = widget.state;
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      final cardBg = theme.colorScheme.onSurface.withValues(
        alpha: dark ? .05 : .04,
      );
      final cardBorder = Colors.white.withValues(alpha: dark ? .08 : .60);
      final dividerColor = theme.colorScheme.onSurface.withValues(
        alpha: dark ? .08 : .06,
      );
      final chevronColor = theme.colorScheme.onSurfaceVariant.withValues(
        alpha: .62,
      );
      final modified = state.pitch != 0 || (state.speed - 1.0).abs() > .01;
      final volumeTrackColor = dark
          ? Colors.white.withValues(alpha: .78)
          : theme.colorScheme.primary;
      final baseSliderTheme = theme.sliderTheme.copyWith(
        trackHeight: 4,
        inactiveTrackColor: theme.colorScheme.onSurface.withValues(alpha: .14),
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
      );
      final micEnabled = !_micBusy && !state.taking;
      final micTesting = state.singingPhase == 'TESTING';
      final micError = state.singing['error'] as String? ?? '';

      return AnimatedSwitcher(
        duration: AppMotionScope.durationOf(
          context,
          const Duration(milliseconds: 200),
        ),
        child: _showAudioSubpage
            ? _AudioSettingsBody(
                key: const ValueKey('sheet-audio-subpage'),
                state: state,
                onBack: () {
                  final entry = _audioHistoryEntry;
                  if (entry != null) {
                    Navigator.maybePop(context);
                  } else {
                    setState(() => _showAudioSubpage = false);
                  }
                },
              )
            : SingleChildScrollView(
                key: const ValueKey('sheet-singing-main'),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SheetHeader(
                      '调音',
                      trailing: modified && !state.taking
                          ? TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                minimumSize: const Size(0, 36),
                                textStyle: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () => uiTask(context, () async {
                                if (state.pitch != 0) {
                                  await state.command('pitch', 0);
                                }
                                if ((state.speed - 1.0).abs() > .01) {
                                  await state.command('speed', 1.0);
                                }
                              }),
                              child: const Text('恢复默认'),
                            )
                          : null,
                    ),
                    if (state.taking)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '录音参数已锁定，结束录音后可以调整。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardBorder, width: .7),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SoundValue(
                            label: '音调',
                            value:
                                '${state.pitch > 0 ? '+' : ''}${state.pitch} 半音',
                          ),
                          SliderTheme(
                            data: baseSliderTheme.copyWith(
                              activeTrackColor: state.pitch == 0
                                  ? Colors.white.withValues(alpha: .72)
                                  : AppPalette.brand,
                              trackShape: _CenteredTrackShape(
                                originFraction: .5,
                                activeColor: state.pitch == 0
                                    ? Colors.white.withValues(alpha: .72)
                                    : AppPalette.brand,
                              ),
                            ),
                            child: Semantics(
                              label: '音调',
                              child: Slider(
                                key: const ValueKey('pitch-control'),
                                semanticFormatterCallback: (v) =>
                                    '${v.round()} 半音',
                                value: state.pitch.toDouble().clamp(-6, 6),
                                min: -6,
                                max: 6,
                                divisions: 12,
                                onChanged: state.taking
                                    ? null
                                    : (v) => uiTask(
                                        context,
                                        () => state.command('pitch', v.round()),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _SoundValue(
                            label: '速度',
                            value: '${(state.speed * 100).round()}%',
                          ),
                          SliderTheme(
                            data: baseSliderTheme.copyWith(
                              activeTrackColor: (state.speed - 1.0).abs() <= .01
                                  ? Colors.white.withValues(alpha: .72)
                                  : AppPalette.brand,
                              trackShape: _CenteredTrackShape(
                                originFraction: (1.0 - .6) / (1.2 - .6),
                                activeColor: (state.speed - 1.0).abs() <= .01
                                    ? Colors.white.withValues(alpha: .72)
                                    : AppPalette.brand,
                              ),
                            ),
                            child: Semantics(
                              label: '速度',
                              child: Slider(
                                key: const ValueKey('speed-control'),
                                semanticFormatterCallback: (v) =>
                                    '${(v * 100).round()}%',
                                value: state.speed.clamp(.6, 1.2),
                                min: .6,
                                max: 1.2,
                                divisions: 12,
                                onChanged: state.taking
                                    ? null
                                    : (v) => uiTask(
                                        context,
                                        () => state.command('speed', v),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _SoundValue(
                            label: '播放音量',
                            value: '${(state.volume * 100).round()}%',
                          ),
                          SliderTheme(
                            data: baseSliderTheme.copyWith(
                              activeTrackColor: volumeTrackColor,
                            ),
                            child: Semantics(
                              label: '播放音量',
                              child: Slider(
                                key: const ValueKey('volume-control'),
                                semanticFormatterCallback: (v) =>
                                    '${(v * 100).round()}%',
                                value: state.volume.clamp(0, 1),
                                onChanged: (v) => uiTask(
                                  context,
                                  () => state.command('volume', v),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '这里调整听到的声音。作品的人声和伴奏比例在回听时调整。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardBorder, width: .7),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              leading: const Icon(Icons.mic_rounded),
                              title: const Text('麦克风试音'),
                              subtitle: const Text('检查声音是否能录到，不保存录音'),
                              trailing: AnimatedRotation(
                                turns: _showMicTest ? .25 : 0,
                                duration: AppMotionScope.durationOf(
                                  context,
                                  const Duration(milliseconds: 180),
                                ),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: chevronColor,
                                ),
                              ),
                              onTap: state.taking
                                  ? null
                                  : () => setState(
                                      () => _showMicTest = !_showMicTest,
                                    ),
                            ),
                            AnimatedSize(
                              duration: AppMotionScope.durationOf(
                                context,
                                const Duration(milliseconds: 220),
                              ),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: _showMicTest
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        14,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            '说一句话，看看音量条是否变化。试音不会保存声音，也不提供实时耳返。',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  height: 1.4,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: LinearProgressIndicator(
                                              minHeight: 8,
                                              color: AppPalette.brand,
                                              backgroundColor: theme
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: .12),
                                              value:
                                                  ((state.singing['level']
                                                                      as num? ??
                                                                  0)
                                                              .toDouble() *
                                                          6)
                                                      .clamp(0, 1),
                                            ),
                                          ),
                                          if (micError.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 10,
                                              ),
                                              child: Semantics(
                                                liveRegion: true,
                                                child: Text(
                                                  micError,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 12),
                                          DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              gradient: micEnabled
                                                  ? const LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        Color(0xFFD63058),
                                                        Color(0xFFB01E43),
                                                      ],
                                                    )
                                                  : null,
                                            ),
                                            child: FilledButton(
                                              style: FilledButton.styleFrom(
                                                minimumSize:
                                                    const Size.fromHeight(44),
                                                backgroundColor: micEnabled
                                                    ? Colors.transparent
                                                    : null,
                                                foregroundColor: Colors.white,
                                                shape: const StadiumBorder(),
                                                textStyle: theme
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              onPressed: micEnabled
                                                  ? _toggleMicTest
                                                  : null,
                                              child: Text(
                                                micTesting ? '结束试音' : '开始试音',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            Divider(
                              height: 1,
                              indent: 54,
                              endIndent: 16,
                              color: dividerColor,
                            ),
                            ListTile(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(20),
                                ),
                              ),
                              leading: const Icon(Icons.headphones_rounded),
                              title: const Text('音轨与播放设置'),
                              subtitle: const Text('试听伴奏、声道、字幕和兼容播放'),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: chevronColor,
                              ),
                              onTap: _openAudioSubpage,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

String _friendlyTrackSubtitle(Map<String, dynamic> track) {
  final raw = (track['label'] as String? ?? '').trim();
  final channels = (track['channels'] as num?)?.toInt();
  final channelText = channels == 1
      ? '单声道'
      : channels == 2
      ? '立体声（双声道）'
      : channels != null && channels > 2
      ? '$channels 声道'
      : '';
  // Strip raw technical IDs such as "audio_1 · 2 声道" or "track_0".
  final cleaned = raw
      .replaceAll(
        RegExp(r'^audio[_\-\s]*\d+\s*[·•-]?\s*', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'^track[_\-\s]*\d+\s*[·•-]?\s*', caseSensitive: false),
        '',
      )
      .trim();
  if (cleaned.isNotEmpty && !RegExp(r'^\d+\s*声道$').hasMatch(cleaned)) {
    return cleaned;
  }
  if (channelText.isNotEmpty) return channelText;
  return cleaned.isNotEmpty ? cleaned : '默认音轨';
}

Future<void> audioSettings(BuildContext context, AppState state) =>
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AudioSettingsBody(state: state),
    );

class _AudioSettingsBody extends StatelessWidget {
  const _AudioSettingsBody({super.key, required this.state, this.onBack});

  final AppState state;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.performance,
    builder: (context, _) {
      final theme = Theme.of(context);
      final dark = theme.brightness == Brightness.dark;
      final cardBg = theme.colorScheme.onSurface.withValues(
        alpha: dark ? .05 : .04,
      );
      final cardBorder = Colors.white.withValues(alpha: dark ? .08 : .60);
      final audio = state.tracks.where((t) => t['type'] == 'audio').toList();
      final selected = audio.where((t) => t['selected'] == true).firstOrNull;
      final stereo = selected?['channels'] == 2;
      final roleLabel = state.audioRole == 'backing'
          ? '当前伴奏'
          : state.audioRole == 'original'
          ? '当前原唱'
          : '待标记';
      Future<void> mark(String role) => uiTask(context, () async {
        final local =
            audio.length == 1 && ['LEFT', 'RIGHT'].contains(state.channelMode);
        final yes = await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(role == 'backing' ? '标记为伴奏？' : '标记为原唱？'),
            content: Text(
              local
                  ? '声道标记只保存在此手机，对当前素材版本生效。'
                  : '这会更新 NAS 曲库的音轨标记，其他设备也会使用此标记。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认标记'),
              ),
            ],
          ),
        );
        if (yes == true) await state.command('role', role);
      });
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onBack != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回调音',
                      onPressed: onBack,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 21),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('音轨与播放设置', style: theme.textTheme.titleLarge),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: '完成',
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.onSurface.withValues(
                                  alpha: dark ? .18 : .09,
                                ),
                                theme.colorScheme.onSurface.withValues(
                                  alpha: dark ? .08 : .04,
                                ),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: dark ? .20 : .65,
                              ),
                              width: .7,
                            ),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .88,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const SheetHeader('音轨与播放设置'),
            Text(
              state.taking ? '录音中不能切换音轨或声道。' : '先试听，再选择原唱或伴奏。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (audio.isEmpty) const Notice('歌曲准备好后，会在这里显示音轨。'),
            if (audio.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder, width: .7),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < audio.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 52,
                            endIndent: 16,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: dark ? .08 : .06,
                            ),
                          ),
                        ListTile(
                          key: ValueKey('audio-track-${audio[i]['id']}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: i == 0
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                              bottom: i == audio.length - 1
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                            ),
                          ),
                          selected: audio[i]['selected'] == true,
                          selectedTileColor: theme.colorScheme.onSurface
                              .withValues(alpha: dark ? .07 : .05),
                          selectedColor: theme.colorScheme.onSurface,
                          leading: Icon(
                            audio[i]['selected'] == true
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 20,
                            color: audio[i]['selected'] == true
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            '音轨 ${i + 1}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            _friendlyTrackSubtitle(audio[i]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: audio[i]['selected'] == true
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: state.audioRole == 'backing'
                                        ? AppPalette.brand.withValues(
                                            alpha: dark ? .18 : .10,
                                          )
                                        : theme.colorScheme.onSurface
                                              .withValues(
                                                alpha: dark ? .09 : .06,
                                              ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: state.audioRole == 'backing'
                                          ? AppPalette.brand.withValues(
                                              alpha: .42,
                                            )
                                          : Colors.white.withValues(
                                              alpha: dark ? .14 : .45,
                                            ),
                                      width: .7,
                                    ),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: state.audioRole == 'backing'
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: state.taking
                              ? null
                              : () => uiTask(
                                  context,
                                  () => state.command('track', audio[i]['id']),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (audio.isNotEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.onSurface.withValues(
                    alpha: dark ? .08 : .06,
                  ),
                  foregroundColor: theme.colorScheme.onSurface,
                  minimumSize: const Size.fromHeight(44),
                  shape: const StadiumBorder(),
                  side: BorderSide(color: cardBorder, width: .7),
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: state.taking
                    ? null
                    : () => uiTask(
                        context,
                        () => state.command(state.isPlaying ? 'pause' : 'play'),
                      ),
                icon: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 20,
                ),
                label: Text(state.isPlaying ? '暂停试听' : '播放当前音轨'),
              ),
            ],
            if (stereo) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '声道',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppSegments<String>(
                values: const [
                  ('STEREO', '立体声'),
                  ('LEFT', '左声道'),
                  ('RIGHT', '右声道'),
                ],
                selected: state.channelMode,
                senior: state.senior,
                enabled: !state.taking,
                liquid:
                    !state.senior &&
                    !state.reduceTransparency &&
                    !state.performanceMode,
                selectedColor: theme.colorScheme.onSurface,
                trackColor: dark ? Colors.white.withValues(alpha: .06) : null,
                keyFor: (value) => ValueKey('audio-channel-$value'),
                onChanged: (value) =>
                    uiTask(context, () => state.command('channel', value)),
              ),
            ],
            if (audio.length > 1 || stereo) ...[
              const SizedBox(height: 14),
              _SoundActions(
                children: [
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: state.audioRole == 'backing'
                          ? AppPalette.brand.withValues(alpha: dark ? .16 : .10)
                          : cardBg,
                      foregroundColor: state.audioRole == 'backing'
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      minimumSize: const Size.fromHeight(44),
                      shape: const StadiumBorder(),
                      side: BorderSide(
                        color: state.audioRole == 'backing'
                            ? AppPalette.brand.withValues(alpha: .42)
                            : cardBorder,
                        width: .7,
                      ),
                    ),
                    onPressed: state.taking ? null : () => mark('backing'),
                    child: const Text('设为伴奏'),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: state.audioRole == 'original'
                          ? theme.colorScheme.onSurface.withValues(
                              alpha: dark ? .12 : .08,
                            )
                          : cardBg,
                      foregroundColor: theme.colorScheme.onSurface,
                      minimumSize: const Size.fromHeight(44),
                      shape: const StadiumBorder(),
                      side: BorderSide(
                        color: state.audioRole == 'original'
                            ? Colors.white.withValues(alpha: dark ? .26 : .45)
                            : cardBorder,
                        width: .7,
                      ),
                    ),
                    onPressed: state.taking ? null : () => mark('original'),
                    child: const Text('设为原唱'),
                  ),
                ],
              ),
            ],
            if (state.tracks.any((t) => t['type'] == 'text')) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '视频字幕',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder, width: .7),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final track in state.tracks.where(
                        (t) => t['type'] == 'text',
                      ))
                        ListTile(
                          title: Text(track['label'] as String? ?? '字幕'),
                          trailing: track['selected'] == true
                              ? Icon(
                                  Icons.check_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => uiTask(
                            context,
                            () => state.command('track', track['id']),
                          ),
                        ),
                      TextButton(
                        onPressed: () => uiTask(
                          context,
                          () => state.command('subtitles', false),
                        ),
                        child: const Text('关闭视频字幕'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (state.playbackError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Notice(state.playbackError),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder, width: .7),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '声音输出：${state.outputRoute}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurface,
                      side: BorderSide(color: cardBorder, width: .8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 34),
                      shape: const StadiumBorder(),
                      textStyle: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: state.taking || state.current == null
                        ? null
                        : () => uiTask(context, () async {
                            final song = state.current!;
                            await state.play(
                              song,
                              force: true,
                              start: state.positionMs,
                              autoplay: state.isPlaying,
                            );
                          }),
                    child: const Text('兼容播放'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<bool> confirmRecording(BuildContext context, AppState state) async {
  if (state.audioRole != 'backing' &&
      ![
        'ACCOMPANIMENT',
        'INSTRUMENTAL',
      ].contains(state.current?.data['version'])) {
    if (!context.mounted) return false;
    final choice = await showAppDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('录音前听一下伴奏'),
        content: Text(
          state.audioRole == 'original'
              ? '当前播放的是原唱，录下的作品也会包含原唱。可以先切换到伴奏，或继续跟原唱录音。'
              : '当前音轨的用途尚未确认。如果含有原唱，录下的作品也会包含原唱。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'select'),
            child: Text(state.backingMapped ? '切换到伴奏' : '试听并选择伴奏'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'record'),
            child: const Text('使用当前声音录音'),
          ),
        ],
      ),
    );
    if (!context.mounted) return false;
    if (choice == 'select') {
      if (state.backingMapped) {
        await state.command('useRole', 'backing');
      } else {
        await audioSettings(context, state);
      }
      return false;
    }
    if (choice != 'record') return false;
  }
  if (!context.mounted || !await microphonePermission(context, state)) {
    return false;
  }
  await state.sing('notifications');
  if (state.mode == 'HLS') {
    final songId = state.current?.id;
    final instanceId = state.playbackInstanceId;
    // HLS opened at a later position may no longer contain the recording start.
    // The existing seek command renegotiates from zero and preserves settings.
    await state.command('seek', 0);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (context.mounted) {
      final snapshot = await AppState.player.invokeMapMethod<String, dynamic>(
        'snapshot',
      );
      if (!context.mounted) return false;
      if (snapshot == null) {
        throw const FormatException('无法确认歌曲是否准备完成，请重试。');
      }
      final song = jsonDecode(snapshot['song'] as String) as Json;
      if (song['id'] != songId ||
          snapshot['instanceId'] != instanceId ||
          (snapshot['workId'] as String? ?? '').isNotEmpty ||
          state.taking) {
        return false;
      }
      final status = snapshot['state'];
      if (status == 'ERROR' || status == 'AUTH_REQUIRED') {
        throw FormatException(
          (snapshot['message'] as String?)?.isNotEmpty == true
              ? snapshot['message'] as String
              : '歌曲准备失败，请重试。',
        );
      }
      if (status == 'PLAYING' || status == 'PAUSED') return true;
      if (DateTime.now().isAfter(deadline)) {
        throw const FormatException('歌曲仍在准备中，请稍后再开始录音。');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }
  return context.mounted;
}
