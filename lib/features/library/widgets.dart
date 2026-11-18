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
      icon: Icon(favoriteIcon, color: favoriteColor, size: 19),
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
    return Material(
      color: Colors.transparent,
      child: MotionPress(
        child: InkWell(
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
                    Artwork(
                      state: state,
                      path: song.cover,
                      label: song.title,
                      revision: song.data['revision']?.toString(),
                      size: MediaQuery.sizeOf(context).width < 375 ? 44 : 48,
                    ),
                    const SizedBox(width: 12),
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
                                  fontWeight: FontWeight.w400,
                                  fontSize: 16,
                                  height: 1.31,
                                  color: playing
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              song.artist.isEmpty ? '歌手未知' : song.artist,
                              if (!song.available) '暂不可用',
                              if (song.data['version'] != null &&
                                  song.data['version'] != 'UNKNOWN')
                                song.version,
                            ].join(' · '),
                            maxLines: enlarged ? null : 1,
                            overflow: enlarged ? null : TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 13,
                                  height: 1.31,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (!enlarged) ...[
                      favorite,
                      IconButton(
                        tooltip: '开始练唱 ${song.title}',
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(44),
                          fixedSize: const Size.square(44),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: song.available ? open : null,
                        icon: Icon(
                          Icons.play_arrow_rounded,
                          size: 19,
                          color: playing ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ],
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
      void open() => openSinging(context, state, song);
      return MotionPress(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: const Color(0xFF26262A),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 136,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -.22),
                      child: Artwork(
                        state: state,
                        path: song.cover,
                        revision: song.data['revision']?.toString(),
                        size: 360,
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xD609090B), Color(0x2609090B)],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xA609090B), Colors.transparent],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: song.available ? open : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 72, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (continuing)
                            Text(
                              '继续练唱',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xD6FFFFFF),
                                    fontSize: 12,
                                  ),
                            ),
                          const Spacer(),
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 26,
                                  height: 1.23,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.7,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist.isEmpty ? '歌手未知' : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: const Color(0xC7FFFFFF),
                                  fontSize: 13,
                                  height: 1.38,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 4,
                    child: IconButton(
                      tooltip: '${favorite ? '取消收藏' : '收藏'} ${song.title}',
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.square(44),
                        fixedSize: const Size.square(44),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: state.favoriteSaving
                          ? null
                          : () => uiTask(context, () => state.favorite(song)),
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Glass(
                      state: state,
                      radius: 24,
                      material: GlassMaterialSpec.onColor,
                      tint: const Color(0xFF3D3D40),
                      child: IconButton(
                        tooltip:
                            '${continuing ? '继续练唱' : '开始练唱'} ${song.title}',
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size.square(48),
                          fixedSize: const Size.square(48),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: song.available ? open : null,
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      ),
                    ),
                  ),
                ],
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
                    opacity: .18,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
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
