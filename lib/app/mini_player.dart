import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../features/library/widgets.dart';
import '../features/player/player_page.dart';
import '../features/singing/works_page.dart';
import 'design.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    required this.state,
    this.navigator,
    this.inset = true,
    this.compact = false,
  });
  final AppState state;
  final NavigatorState? navigator;
  final bool inset;
  final bool compact;
  static double heightOf(
    BuildContext context,
    AppState state, {
    bool compact = false,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final title =
        scaler.scale(
          state.senior
              ? 18
              : compact
              ? 12
              : 13,
        ) *
        1.45;
    final subtitle = compact ? 0.0 : scaler.scale(state.senior ? 14 : 12) * 1.5;
    return math.max(state.senior ? 72 : 56, title + subtitle + 12);
  }

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double drag = 0;
  bool dragging = false;

  void open() => (widget.navigator ?? Navigator.of(context)).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(
        name:
            widget.state.workId.isNotEmpty ||
                widget.state.pendingReviewId.isNotEmpty
            ? 'review'
            : 'player',
      ),
      builder: (_) => performancePage(widget.state),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      if (state.current == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final playbackLabel = switch (state.playbackState) {
        'PREPARING' => '正在准备',
        'BUFFERING' => '正在缓冲',
        'ERROR' => '播放失败',
        'AUTH_REQUIRED' => '登录失效',
        'ENDED' => '播放结束',
        _ => state.isPlaying ? '播放中' : '已暂停',
      };
      final showState = [
        'PREPARING',
        'BUFFERING',
        'ERROR',
        'AUTH_REQUIRED',
      ].contains(state.playbackState);
      final actionLabel = showState
          ? '查看播放状态'
          : state.isPlaying
          ? '暂停播放'
          : '继续播放';
      void playbackAction() => showState
          ? open()
          : uiTask(
              context,
              () => state.command(state.isPlaying ? 'pause' : 'play'),
            );
      final duration =
          dragging || AppMotionScope.levelOf(context) != AppMotionLevel.full
          ? Duration.zero
          : AppMotion.release;
      return Padding(
        padding: widget.inset
            ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
            : EdgeInsets.zero,
        child: GestureDetector(
          excludeFromSemantics: true,
          onVerticalDragStart: (_) => setState(() {
            dragging = true;
            drag = 0;
          }),
          onVerticalDragUpdate: (details) =>
              setState(() => drag = (drag + details.delta.dy).clamp(-120, 12)),
          onVerticalDragCancel: () => setState(() {
            dragging = false;
            drag = 0;
          }),
          onVerticalDragEnd: (details) {
            final expand =
                drag < -56 ||
                (drag < -20 && (details.primaryVelocity ?? 0) < -650);
            setState(() {
              dragging = false;
              drag = 0;
            });
            if (expand) open();
          },
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.softSpring,
            transform: Matrix4.translationValues(0, drag, 0),
            child: Glass(
              state: state,
              radius: 24,
              variant: GlassVariant.regular,
              material: GlassMaterialSpec.player,
              backdropContext: GlassBackdropContext.content,
              child: InkWell(
                key: const Key('mini-player'),
                onTap: open,
                child: SizedBox(
                  height: MiniPlayer.heightOf(
                    context,
                    state,
                    compact: widget.compact,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final artwork =
                          !widget.compact || constraints.maxWidth >= 190;
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                if (artwork) ...[
                                  Artwork(
                                    state: state,
                                    path: state.current!.cover,
                                    label: state.current!.title,
                                    size: state.senior ? 48 : 40,
                                  ),
                                  SizedBox(width: widget.compact ? 6 : 10),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        state.current!.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontSize: state.senior
                                                  ? 18
                                                  : widget.compact
                                                  ? 12
                                                  : 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (!widget.compact)
                                        ListenableBuilder(
                                          listenable: state.playback,
                                          builder: (context, _) => Text(
                                            state.recording
                                                ? '正在录音 · ${durationLabel((state.singing['recordedMs'] as num? ?? 0).toInt())}'
                                                : state.countdown > 0
                                                ? '录音倒数 ${state.countdown}'
                                                : state.singingPhase ==
                                                      'FINALIZING'
                                                ? '正在保留录音'
                                                : state
                                                      .pendingReviewId
                                                      .isNotEmpty
                                                ? '录音已保留 · 点击回听'
                                                : state.workId.isNotEmpty
                                                ? '返回作品回听'
                                                : '${state.current!.artist} · $playbackLabel',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontSize: state.senior
                                                      ? 14
                                                      : 12,
                                                  color: state.taking
                                                      ? scheme.error
                                                      : scheme.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (state.recording)
                                  TextButton(
                                    onPressed: () => uiTask(context, () async {
                                      final id = state.takeId;
                                      await state.endTake();
                                      if (!context.mounted) return;
                                      await (widget.navigator ??
                                              Navigator.of(context))
                                          .push(
                                            MaterialPageRoute<void>(
                                              settings: const RouteSettings(
                                                name: 'review',
                                              ),
                                              builder: (_) => ReviewPage(
                                                state: state,
                                                id: id,
                                              ),
                                            ),
                                          );
                                    }),
                                    child: const Text('结束'),
                                  )
                                else if (state.taking)
                                  TextButton(
                                    onPressed: open,
                                    child: const Text('查看'),
                                  )
                                else if (state.senior)
                                  TextButton(
                                    onPressed: playbackAction,
                                    child: Text(
                                      showState
                                          ? '查看'
                                          : state.isPlaying
                                          ? '暂停'
                                          : '继续',
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: actionLabel,
                                    onPressed: playbackAction,
                                    iconSize: 24,
                                    color: scheme.onSurface,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 44,
                                      height: 44,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      state.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!widget.compact)
                            Positioned(
                              left: 56,
                              right: 10,
                              bottom: 0,
                              child: ExcludeSemantics(
                                child: ListenableBuilder(
                                  listenable: state.playback,
                                  builder: (context, _) =>
                                      LinearProgressIndicator(
                                        minHeight: 2,
                                        value: state.durationMs > 0
                                            ? (state.positionMs /
                                                      state.durationMs)
                                                  .clamp(0, 1)
                                            : 0,
                                        color: state.recording
                                            ? scheme.error
                                            : scheme.primary,
                                        backgroundColor: scheme.onSurface
                                            .withValues(alpha: .06),
                                      ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
