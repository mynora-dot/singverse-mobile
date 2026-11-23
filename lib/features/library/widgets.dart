import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../singing/actions.dart';

class Artwork extends StatefulWidget {
  const Artwork({
    super.key,
    required this.state,
    this.path,
    this.size = 56,
    this.round = false,
    this.revision,
    this.label = '',
  });
  final AppState state;
  final String? path, revision;
  final String label;
  final double size;
  final bool round;
  @override
  State<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<Artwork> {
  Future<Uint8List>? _image;
  String identity = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(Artwork old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.revision != widget.revision ||
        identity !=
            '${widget.state.origin}:${widget.state.instanceId}:${widget.state.authenticated}') {
      _load();
    }
  }

  void _load() {
    identity =
        '${widget.state.origin}:${widget.state.instanceId}:${widget.state.authenticated}';
    _image = widget.path?.trim().isNotEmpty == true
        ? widget.state.artwork(widget.path!, revision: widget.revision)
        : null;
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(
      widget.round ? widget.size : AppRadii.artwork,
    ),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<Uint8List>(
        key: ValueKey('$identity:${widget.path}:${widget.revision}'),
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => _placeholder(context),
            );
          }
          return _placeholder(context);
        },
      ),
    ),
  );

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ColoredBox(
        color: scheme.secondaryContainer,
        child: Center(
          child: Icon(
            widget.round
                ? Icons.person_outline_rounded
                : Icons.music_note_rounded,
            color: scheme.onSurfaceVariant.withValues(alpha: .55),
            size: widget.size * .42,
          ),
        ),
      ),
    );
  }
}

class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.state,
    required this.song,
    this.onTap,
  });
  final AppState state;
  final Song song;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => buildRow(context),
  );

  Widget buildRow(BuildContext context) {
    void open() {
      if (onTap != null) {
        onTap!();
      } else {
        openSinging(context, state, song);
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final playing =
        state.workId.isEmpty && state.isPlaying && state.current?.id == song.id;
    final favoriteLabel = state.isFavorite(song) ? '已收藏' : '收藏';
    final favoriteTooltip = state.isFavorite(song)
        ? '取消收藏 ${song.title}'
        : '收藏 ${song.title}';
    final favoriteIcon = state.isFavorite(song)
        ? Icons.favorite_rounded
        : Icons.favorite_border_rounded;
    final favoriteColor = state.isFavorite(song)
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final favorite = IconButton(
      tooltip: favoriteTooltip,
      onPressed: state.favoriteSaving
          ? null
          : () => uiTask(context, () => state.favorite(song)),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        fixedSize: const Size.square(44),
        padding: EdgeInsets.zero,
      ),
      icon: AnimatedSwitcher(
        duration: AppMotionScope.durationOf(
          context,
          const Duration(milliseconds: 220),
        ),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: .72, end: 1).animate(
            CurvedAnimation(parent: animation, curve: AppMotion.bouncySpring),
          ),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          favoriteIcon,
          key: ValueKey(state.isFavorite(song)),
          color: favoriteColor,
          size: 19,
        ),
      ),
    );
    if (state.senior) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: .5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(
                    state: state,
                    path: song.cover,
                    label: song.title,
                    revision: song.data['revision']?.toString(),
                    size: 64,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: playing ? scheme.primary : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist.isEmpty ? '歌手未知' : song.artist,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final favoriteButton = OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: favoriteColor,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: scheme.onSurface.withValues(alpha: .10),
                      ),
                    ),
                    onPressed: state.favoriteSaving
                        ? null
                        : () => uiTask(context, () => state.favorite(song)),
                    icon: Icon(favoriteIcon, size: 20),
                    label: Text(favoriteLabel),
                  );
                  final startButton = FilledButton.icon(
                    onPressed: song.available ? open : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(song.available ? '开始练唱' : '暂不可用'),
                  );
                  if (constraints.maxWidth < 320 ||
                      MediaQuery.textScalerOf(context).scale(19) > 24) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        startButton,
                        const SizedBox(height: 8),
                        favoriteButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: favoriteButton),
                      const SizedBox(width: 12),
                      Expanded(child: startButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    final enlarged = MediaQuery.textScalerOf(context).scale(15) > 19;
    final playAction = IconButton(
      tooltip: '开始练唱 ${song.title}',
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        fixedSize: const Size.square(44),
        padding: EdgeInsets.zero,
      ),
      onPressed: song.available ? open : null,
      icon: AnimatedContainer(
        duration: AppMotionScope.durationOf(context, AppMotion.release),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: playing
              ? scheme.primary
              : scheme.primary.withValues(alpha: .10),
          border: Border.all(
            color: playing
                ? scheme.primary
                : scheme.primary.withValues(alpha: .18),
            width: .6,
          ),
        ),
        child: Center(
          child: playing && state.isPlaying
              ? const Icon(Icons.pause_rounded, size: 17, color: Colors.white)
              : AppVectorIcon(
                  AppGlyph.play,
                  size: 13.5,
                  filled: true,
                  color: playing ? Colors.white : scheme.primary,
                ),
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: MotionPress(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: song.available ? open : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: scheme.onSurface.withValues(alpha: .055),
                  width: .5,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        Artwork(
                          state: state,
                          path: song.cover,
                          label: song.title,
                          revision: song.data['revision']?.toString(),
                          size: MediaQuery.sizeOf(context).width < 375
                              ? 46
                              : 50,
                        ),
                        if (playing)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppRadii.artwork,
                              ),
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: .38),
                                child: const Center(
                                  child: AppVectorIcon(
                                    AppGlyph.waveform,
                                    color: Colors.white,
                                    size: 19,
                                    filled: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: enlarged ? null : 1,
                            overflow: enlarged ? null : TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontWeight: playing
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontSize: 16,
                                  height: 1.31,
                                  color: playing
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  [
                                    song.artist.isEmpty ? '歌手未知' : song.artist,
                                    if (!song.available) '暂不可用',
                                  ].join(' · '),
                                  maxLines: enlarged ? null : 1,
                                  overflow: enlarged
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontSize: 13,
                                        height: 1.31,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                              if (!enlarged &&
                                  song.data['version'] != null &&
                                  song.data['version'] != 'UNKNOWN') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.onSurface.withValues(
                                      alpha: .07,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    song.version,
                                    maxLines: 1,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.2,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!enlarged) ...[favorite, playAction],
                  ],
                ),
                if (enlarged) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      Tooltip(
                        message: favoriteTooltip,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: favoriteColor,
                          ),
                          onPressed: state.favoriteSaving
                              ? null
                              : () =>
                                    uiTask(context, () => state.favorite(song)),
                          icon: Icon(favoriteIcon, size: 20),
                          label: Text(favoriteLabel),
                        ),
                      ),
                      Tooltip(
                        message: '开始练唱 ${song.title}',
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          onPressed: song.available ? open : null,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: Text(song.available ? '开始练唱' : '暂不可用'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real catalog item, displayed once in the feed. This is not a recommendation
/// or an additional queue: opening it uses the same practice flow as a song row.
class SongSpotlight extends StatelessWidget {
  const SongSpotlight({super.key, required this.state, required this.song});
  final AppState state;
  final Song song;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final favorite = state.isFavorite(song);
      final continuing = state.current?.id == song.id && state.workId.isEmpty;
      final narrow = MediaQuery.sizeOf(context).width < 360;
      void open() => openSinging(context, state, song);
      return MotionPress(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.featured),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .22),
                blurRadius: 28,
                spreadRadius: -8,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Material(
            color: const Color(0xFF1D1B2A),
            borderRadius: BorderRadius.circular(AppRadii.featured),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 168),
              child: IntrinsicHeight(
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: .42,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: Artwork(
                              state: state,
                              path: song.cover,
                              revision: song.data['revision']?.toString(),
                              size: 320,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xE01A1828),
                              Color(0xC83A1E34),
                              Color(0xB8922C42),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xC00E0E15), Color(0x280E0E15)],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: song.available ? open : null,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Glass(
                                        state: state,
                                        radius: 999,
                                        material: GlassMaterialSpec.onColor,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const AppVectorIcon(
                                                AppGlyph.sparkles,
                                                size: 11,
                                                color: Color(0xFFFFD580),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  continuing
                                                      ? '继续练唱'
                                                      : '家庭精选开唱',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: .94,
                                                            ),
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        song.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontSize: narrow ? 20 : 22,
                                              height: 1.2,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -.5,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        song.artist.isEmpty
                                            ? '歌手未知'
                                            : song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xCCFFFFFF),
                                              fontSize: 13,
                                              height: 1.35,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Flexible(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white
                                              .withValues(alpha: .94),
                                          foregroundColor: AppPalette.ink,
                                          minimumSize: const Size(48, 48),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                          shape: const StadiumBorder(),
                                          textStyle: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        onPressed: song.available ? open : null,
                                        icon: const AppVectorIcon(
                                          AppGlyph.play,
                                          size: 14,
                                          color: AppPalette.ink,
                                        ),
                                        label: Text(
                                          continuing ? '继续练唱' : '开始练唱',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Glass(
                                      state: state,
                                      radius: 24,
                                      material: GlassMaterialSpec.onColor,
                                      tint: favorite
                                          ? Colors.white
                                          : const Color(0xFF3A3A44),
                                      child: IconButton(
                                        tooltip:
                                            '${favorite ? '取消收藏' : '收藏'} ${song.title}',
                                        style: IconButton.styleFrom(
                                          foregroundColor: favorite
                                              ? AppPalette.brand
                                              : Colors.white,
                                          minimumSize: const Size.square(48),
                                          fixedSize: const Size.square(48),
                                          padding: EdgeInsets.zero,
                                        ),
                                        onPressed: state.favoriteSaving
                                            ? null
                                            : () => uiTask(
                                                context,
                                                () => state.favorite(song),
                                              ),
                                        icon: AnimatedSwitcher(
                                          duration: AppMotionScope.durationOf(
                                            context,
                                            const Duration(milliseconds: 220),
                                          ),
                                          transitionBuilder:
                                              (child, animation) =>
                                                  ScaleTransition(
                                                    scale:
                                                        Tween<double>(
                                                          begin: .72,
                                                          end: 1,
                                                        ).animate(
                                                          CurvedAnimation(
                                                            parent: animation,
                                                            curve: AppMotion
                                                                .bouncySpring,
                                                          ),
                                                        ),
                                                    child: child,
                                                  ),
                                          child: Icon(
                                            favorite
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            key: ValueKey(favorite),
                                            size: 19,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!narrow) ...[
                            const SizedBox(width: 14),
                            GestureDetector(
                              onTap: song.available ? open : null,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .32),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .38,
                                      ),
                                      blurRadius: 22,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Artwork(
                                    state: state,
                                    path: song.cover,
                                    revision: song.data['revision']?.toString(),
                                    size: 108,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A single, small decoded cover supplies a static ambient color wash.
/// It filters its own image, never a native video or camera underneath it.
class AmbientArtwork extends StatefulWidget {
  const AmbientArtwork({super.key, required this.state, required this.song});
  final AppState state;
  final Song song;
  @override
  State<AmbientArtwork> createState() => _AmbientArtworkState();
}

class _AmbientArtworkState extends State<AmbientArtwork> {
  Future<Uint8List>? image;
  String identity = '';
  String get nextIdentity =>
      '${widget.state.origin}:${widget.state.instanceId}:${widget.state.authenticated}:${widget.song.cover}:${widget.song.data['revision']}';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(AmbientArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identity != nextIdentity) load();
  }

  void load() {
    identity = nextIdentity;
    final path = widget.song.cover;
    image = path?.isNotEmpty == true
        ? widget.state.artwork(
            path!,
            revision: widget.song.data['revision']?.toString(),
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotionScope.solidOf(context) ||
        widget.state.performanceMode ||
        widget.state.reduceTransparency ||
        widget.state.senior) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: FutureBuilder<Uint8List>(
            key: ValueKey(identity),
            future: image,
            builder: (context, snapshot) => snapshot.hasData
                ? Opacity(
                    opacity: .62,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                      child: Image.memory(
                        snapshot.data!,
                        cacheWidth: 96,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
