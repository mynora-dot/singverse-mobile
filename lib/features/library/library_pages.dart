import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../singing/actions.dart';
import 'widgets.dart';

const tagDimensions = {
  'LANGUAGE': '语种',
  'DECADE': '年代',
  'GENRE': '风格',
  'MOOD': '情绪',
  'SCENE': '场景',
  'CUSTOM': '其他分类',
};

Future<void> showSong(
  BuildContext context,
  AppState state,
  Song song, {
  List<(String, String)> credits = const [],
}) => showAppSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) =>
      SongDetail(state: state, song: song, credits: credits),
);

class SongsPage extends StatefulWidget {
  const SongsPage({
    super.key,
    required this.state,
    this.title = '歌曲',
    this.artistId,
    this.tags = const [],
    this.embedded = false,
    this.showBrowse = false,
    this.browseItem,
    this.headerActions,
  });
  final AppState state;
  final String title;
  final String? artistId;
  final List<String> tags;
  final bool embedded, showBrowse;
  final Json? browseItem;
  final Widget? headerActions;
  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  late final query = SongQuery(
    widget.state,
    artistId: widget.artistId,
    tags: widget.tags,
  );
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final filtersFocus = FocusNode(debugLabel: '筛选歌曲');
  final scroll = ScrollController();
  final tagNames = <String, String>{};
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    searchFocus.addListener(searchChanged);
    unawaited(query.load());
  }

  void searchChanged() => setState(() {});

  @override
  void dispose() {
    debounce?.cancel();
    searchFocus.removeListener(searchChanged);
    searchFocus.dispose();
    filtersFocus.dispose();
    scroll.dispose();
    search.dispose();
    query.dispose();
    super.dispose();
  }

  Future<void> filters() => uiTask(context, () async {
    final tags = (await widget.state.get('/api/v1/classification/tags') as List)
        .cast<Json>()
        .where(
          (t) =>
              t['active'] == true &&
              ((t['count'] as num? ?? 0) > 0 || query.tagIds.contains(t['id'])),
        )
        .toList();
    for (final tag in tags) {
      tagNames[tag['id'] as String] = tag['name'] as String;
    }
    if (!mounted) return;
    searchFocus.unfocus();
    final result = await showAppSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SongFilters(
        tags: tags,
        selected: query.tagIds,
        senior: widget.state.senior,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      query.tagIds = result;
      if (scroll.hasClients) scroll.jumpTo(0);
      await query.load();
    }
    if (mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        filtersFocus.context != null) {
      filtersFocus.requestFocus();
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: query,
    builder: (context, _) {
      final state = widget.state;
      final pageInset = MediaQuery.sizeOf(context).width < 375 ? 16.0 : 20.0;
      final searching =
          searchFocus.hasFocus ||
          search.text.isNotEmpty ||
          query.tagIds.isNotEmpty;
      final orderedItems = searching
          ? query.items
          : _interleaveSongsByTitle(query.items);
      final spotlight =
          widget.showBrowse &&
          !searching &&
          !state.senior &&
          MediaQuery.textScalerOf(context).scale(16) <= 21 &&
          orderedItems.isNotEmpty;
      final rows = spotlight ? orderedItems.skip(1).toList() : orderedItems;
      final pinnedSearch = widget.embedded && widget.headerActions != null;
      final searchHeader = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _SongSearchField(
              state: state,
              fieldKey: const ValueKey('song-search'),
              controller: search,
              focusNode: searchFocus,
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (search.text.isNotEmpty)
                    IconButton(
                      tooltip: '清除搜索',
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(44),
                        fixedSize: const Size.square(44),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () {
                        debounce?.cancel();
                        search.clear();
                        query.query = '';
                        query.load();
                        setState(() {});
                      },
                      icon: const Icon(Icons.cancel_rounded),
                    ),
                  IconButton(
                    tooltip: '筛选歌曲',
                    focusNode: filtersFocus,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(44),
                      fixedSize: const Size.square(44),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: filters,
                    icon: Badge(
                      isLabelVisible: query.tagIds.isNotEmpty,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: AppVectorIcon(
                        AppGlyph.sliders,
                        size: 18,
                        color: query.tagIds.isNotEmpty
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              onChanged: (text) {
                query.query = text;
                setState(() {});
                debounce?.cancel();
                debounce = Timer(const Duration(milliseconds: 350), () {
                  if (scroll.hasClients) scroll.jumpTo(0);
                  query.load();
                });
              },
              onSubmitted: (_) {
                debounce?.cancel();
                query.load();
                searchFocus.unfocus();
              },
            ),
          ),
          if (!pinnedSearch && widget.headerActions != null) ...[
            const SizedBox(width: 8),
            widget.headerActions!,
          ],
        ],
      );
      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.browseItem != null)
            _BrowseIntroduction(state: state, item: widget.browseItem!),
          if (!pinnedSearch) searchHeader,
          if (widget.showBrowse && !searching) ...[
            const SizedBox(height: 4),
            _BrowseLinks(state: state),
          ],
          if (query.tagIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final id in query.tagIds)
                    InputChip(
                      shape: const StadiumBorder(),
                      backgroundColor: AppPalette.brand.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? .18
                            : .10,
                      ),
                      side: BorderSide(
                        color: AppPalette.brand.withValues(alpha: .36),
                        width: .8,
                      ),
                      labelStyle: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                      deleteIconColor: Theme.of(context).colorScheme.primary,
                      label: Text(
                        tagNames[id] ??
                            (widget.tags.contains(id) ? widget.title : '已选分类'),
                      ),
                      onDeleted: () {
                        query.tagIds.remove(id);
                        query.load();
                      },
                    ),
                  TextButton(
                    onPressed: () {
                      query.tagIds.clear();
                      query.load();
                    },
                    child: const Text('清除筛选'),
                  ),
                ],
              ),
            ),
          if (spotlight) ...[
            const SizedBox(height: 8),
            MotionEntrance(
              key: ValueKey(
                'spotlight:${state.instanceId}:${orderedItems.first.id}',
              ),
              index: 0,
              child: SongSpotlight(state: state, song: orderedItems.first),
            ),
          ],
          const SizedBox(height: 16),
          SectionTitle(
            search.text.trim().isNotEmpty
                ? '搜索结果'
                : widget.embedded && query.tagIds.isNotEmpty
                ? '筛选结果'
                : '全部曲目',
            trailing: Text(
              '${query.total} 首',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
      final topFloatHeight = pinnedSearch
          ? math.max(
              114.0,
              MediaQuery.textScalerOf(context).scale(30) * 1.25 +
                  (state.senior ? 64.0 : 56.0) +
                  24,
            )
          : 0.0;
      final body = RefreshIndicator(
        edgeOffset: topFloatHeight,
        onRefresh: () => query.load(),
        child: CustomScrollView(
          controller: scroll,
          key: PageStorageKey(
            'songs:${state.instanceId}:${widget.artistId}:${widget.tags.join(',')}',
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pageInset,
                pinnedSearch ? topFloatHeight + 6 : 4,
                pageInset,
                0,
              ),
              sliver: SliverToBoxAdapter(child: header),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pageInset),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => MotionEntrance(
                  key: ValueKey(
                    'songs:${state.instanceId}:${widget.artistId}:${rows[index].id}',
                  ),
                  index: index,
                  child: SongRow(state: state, song: rows[index]),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pageInset),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (query.loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (query.error != null)
                      Notice(query.error!, action: query.retry),
                    if (!query.loading &&
                        query.error == null &&
                        query.items.isEmpty)
                      Notice(
                        search.text.isEmpty && query.tagIds.isEmpty
                            ? '曲库还没有歌曲，请在 NAS 管理端添加自备歌曲。'
                            : '没有找到歌曲，试试其他关键词或清除筛选。',
                      ),
                    if (query.hasMore && !query.loading && query.error == null)
                      TextButton(
                        onPressed: () => query.load(more: true),
                        child: const Text('加载更多歌曲'),
                      ),
                  ],
                ),
              ),
            ),
            SliverBottomSpace(embedded: widget.embedded),
          ],
        ),
      );
      final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
      final content = pinnedSearch
          ? AppBackdropCapture(
              builder: (context, layerBackdrop) => Stack(
                children: [
                  Positioned.fill(
                    child: AppBackdropSource(
                      backdrop: layerBackdrop,
                      child: AppEnvironment(
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) {
                            final h = bounds.height <= 0 ? 1.0 : bounds.height;
                            final fadeStart = (10 / h).clamp(0.0, 0.12);
                            final fadeEnd = (52 / h).clamp(
                              fadeStart + 0.01,
                              0.20,
                            );
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0, fadeStart, fadeEnd, 1],
                              colors: const [
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black,
                                Colors.black,
                              ],
                            ).createShader(bounds);
                          },
                          child: body,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AppBackdropScope(
                      backdrop: layerBackdrop,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              pageInset,
                              6,
                              pageInset,
                              10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '点歌',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -.8,
                                        ),
                                  ),
                                ),
                                widget.headerActions!,
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              pageInset,
                              0,
                              pageInset,
                              8,
                            ),
                            child: searchHeader,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : body;
      return widget.embedded
          ? content
          : AppBackdropCapture(
              builder: (context, layerBackdrop) => Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppToolbar(
                  leading: Navigator.canPop(context)
                      ? AppBackdropScope(
                          backdrop: layerBackdrop,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 12,
                              top: 2,
                              bottom: 2,
                            ),
                            child: Glass(
                              state: state,
                              radius: 24,
                              variant: GlassVariant.liquid,
                              child: const BackButton(),
                            ),
                          ),
                        )
                      : null,
                  title: Text(widget.title),
                ),
                body: AppBackdropSource(
                  backdrop: layerBackdrop,
                  child: AppEnvironment(
                    child: Stack(
                      children: [
                        ContentWidth(child: content),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 36,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    scaffoldBg.withValues(alpha: 0),
                                    scaffoldBg.withValues(alpha: .30),
                                  ],
                                ),
                              ),
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

/// Interleaves songs that share the exact same normalized title into secondary
/// passes so different cover versions of the same song do not cluster back-to-back
/// on the default home screen feed while keeping the relative order of distinct songs.
List<Song> _interleaveSongsByTitle(List<Song> source) {
  if (source.length <= 2) return source;
  final buckets = <String, List<Song>>{};
  for (final song in source) {
    final key = song.title.trim().toLowerCase();
    (buckets[key] ??= <Song>[]).add(song);
  }
  if (buckets.length == source.length) return source;
  final result = <Song>[];
  var round = 0;
  var added = true;
  while (added) {
    added = false;
    for (final group in buckets.values) {
      if (round < group.length) {
        result.add(group[round]);
        added = true;
      }
    }
    round++;
  }
  return result;
}

class _SongSearchField extends StatelessWidget {
  const _SongSearchField({
    required this.state,
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.suffix,
    required this.onChanged,
    required this.onSubmitted,
    this.hint = '搜索歌名或歌手',
  });
  final AppState state;
  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget suffix;
  final ValueChanged<String> onChanged, onSubmitted;
  final String hint;

  @override
  Widget build(BuildContext context) => GlassField(
    state: state,
    radius: 999,
    material: GlassMaterialSpec.search,
    child: TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontSize: state.senior ? 18 : 16, height: 1.25),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: state.senior ? 18 : 16,
          height: 1.25,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        prefixIcon: Center(
          widthFactor: 1,
          child: AppVectorIcon(
            AppGlyph.search,
            size: 17.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: state.senior ? 44 : 40,
          minHeight: state.senior ? 56 : 44,
        ),
        suffixIcon: suffix,
        suffixIconConstraints: BoxConstraints(
          minHeight: state.senior ? 56 : 44,
        ),
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  );
}

class _SongFilters extends StatefulWidget {
  const _SongFilters({
    required this.tags,
    required this.selected,
    required this.senior,
  });
  final List<Json> tags;
  final List<String> selected;
  final bool senior;

  @override
  State<_SongFilters> createState() => _SongFiltersState();
}

class _SongFiltersState extends State<_SongFilters> {
  late final selected = {...widget.selected};
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final inset = MediaQuery.sizeOf(context).width < 375 ? 16.0 : 20.0;
    final dimensions = {
      ...tagDimensions.keys,
      ...widget.tags.map((tag) => tag['dimension'] as String? ?? 'CUSTOM'),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset - 4, 4),
            child: const SheetHeader('筛选歌曲', done: '取消'),
          ),
          Flexible(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .88, 1],
                colors: [Colors.black, Colors.black, Colors.transparent],
              ).createShader(bounds),
              child: ListView(
                key: const PageStorageKey('song-filter-options'),
                controller: scroll,
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(inset, 0, inset, 22),
                children: [
                  if (widget.tags.isEmpty) const Notice('曲库还没有可用分类。'),
                  for (final dimension in dimensions)
                    if (widget.tags.any(
                      (tag) => (tag['dimension'] ?? 'CUSTOM') == dimension,
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 8),
                        child: Text(
                          tagDimensions[dimension] ?? dimension,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: widget.senior ? 17 : 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final tag in widget.tags.where(
                            (tag) =>
                                (tag['dimension'] ?? 'CUSTOM') == dimension,
                          ))
                            () {
                              final isSelected = selected.contains(tag['id']);
                              return FilterChip(
                                key: ValueKey('song-filter:${tag['id']}'),
                                showCheckmark: false,
                                shape: const StadiumBorder(),
                                backgroundColor: scheme.onSurface.withValues(
                                  alpha: dark ? .07 : .05,
                                ),
                                selectedColor: AppPalette.brand.withValues(
                                  alpha: dark ? .24 : .14,
                                ),
                                side: BorderSide(
                                  color: isSelected
                                      ? AppPalette.brand.withValues(alpha: .72)
                                      : scheme.onSurface.withValues(
                                          alpha: dark ? .10 : .08,
                                        ),
                                  width: .9,
                                ),
                                labelStyle: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: widget.senior ? 17 : 14,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? (dark
                                                ? Colors.white
                                                : AppPalette.brandDeep)
                                          : scheme.onSurface.withValues(
                                              alpha: .86,
                                            ),
                                    ),
                                label: Text('${tag['name']} · ${tag['count']}'),
                                selected: isSelected,
                                onSelected: (yes) => setState(() {
                                  yes
                                      ? selected.add(tag['id'] as String)
                                      : selected.remove(tag['id']);
                                }),
                              );
                            }(),
                        ],
                      ),
                    ],
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: scheme.onSurface.withValues(alpha: dark ? .08 : .06),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, 10, inset, 12),
              child: Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    onPressed: selected.isEmpty
                        ? null
                        : () => setState(selected.clear),
                    child: const Text('清除全部'),
                  ),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppPalette.brand, AppPalette.brandDeep],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppPalette.brand.withValues(alpha: .32),
                          blurRadius: 16,
                          spreadRadius: -4,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(140, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () =>
                          Navigator.pop(context, selected.toList()),
                      child: Text('应用筛选 (${selected.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseIntroduction extends StatelessWidget {
  const _BrowseIntroduction({required this.state, required this.item});
  final AppState state;
  final Json item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Artwork(
              state: state,
              path: item['portraitPath'] as String?,
              revision: item['portraitVersion']?.toString(),
              round: true,
              size: 80,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] as String,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item['count'] ?? 0} 首歌曲',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if ((item['biography'] as String? ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            item['biography'] as String,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class _BrowseLinks extends StatelessWidget {
  const _BrowseLinks({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          state.senior ||
          constraints.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(13) > 18;
      final scheme = Theme.of(context).colorScheme;
      final links = [
        for (final item in const [
          (AppGlyph.artist, '歌手', '歌手'),
          (AppGlyph.grid, '分类', '分类'),
          (AppGlyph.playlist, '家庭歌单', '共享歌单'),
        ])
          MotionPress(
            child: Glass(
              state: state,
              radius: 999,
              material: GlassMaterialSpec.shortcut,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                  padding: EdgeInsets.symmetric(
                    horizontal: stacked ? 14 : 6,
                    vertical: 11,
                  ),
                  minimumSize: Size(44, state.senior ? 56 : 44),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => BrowsePage(state: state, kind: item.$3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: stacked
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    AppVectorIcon(
                      item.$1,
                      size: state.senior ? 22 : 16.5,
                      color: scheme.primary,
                    ),
                    SizedBox(width: stacked ? 12 : 6),
                    Flexible(
                      fit: stacked ? FlexFit.tight : FlexFit.loose,
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: state.senior ? 18 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (stacked)
                      const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
      ];
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < links.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  links[i],
                ],
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < links.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: links[i]),
                ],
              ],
            );
    },
  );
}

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.state, required this.kind});
  final AppState state;
  final String kind;
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  List<Json> items = [];
  int page = 0, total = 0, generation = 0;
  bool loading = false;
  bool failedMore = false;
  String loadedSearch = '';
  String? error;
  bool get artist => widget.kind == '歌手';
  bool get tags => widget.kind == '分类';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    generation++;
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && loading) return;
    if (more && loadedSearch != search.text) return load();
    final requestedSearch = search.text;
    final ticket = ++generation, next = more ? page + 1 : 0;
    setState(() {
      loading = true;
      error = null;
      failedMore = false;
      if (!more) items = [];
    });
    try {
      final path = tags
          ? '/api/v1/classification/tags'
          : '/api/v1/${artist ? 'artists' : 'playlists'}?${Uri(queryParameters: {'q': requestedSearch, 'page': '$next', 'size': '20'}).query}';
      final result = await widget.state.get(path);
      if (!mounted || ticket != generation) return;
      final rows = tags
          ? (result as List)
                .cast<Json>()
                .where(
                  (t) => t['active'] == true && (t['count'] as num? ?? 0) > 0,
                )
                .toList()
          : (result['items'] as List).cast<Json>();
      setState(() {
        items = more ? [...items, ...rows] : rows;
        page = next;
        total = tags ? rows.length : result['totalElements'] as int;
        loadedSearch = requestedSearch;
      });
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          error = e.toString();
          failedMore = more;
        });
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  void open(Json item) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => tags || artist
          ? SongsPage(
              state: widget.state,
              title: item['name'] as String,
              artistId: artist ? item['id'] as String : null,
              tags: tags ? [item['id'] as String] : [],
              browseItem: artist ? item : null,
            )
          : PlaylistPage(state: widget.state, id: item['id'] as String),
    ),
  );
  Widget tile(Json item) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).dividerColor, width: .5),
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: ListTile(
        minTileHeight: widget.state.senior ? 88 : 68,
        contentPadding: EdgeInsets.symmetric(
          vertical: widget.state.senior ? 12 : 4,
        ),
        leading: tags
            ? null
            : Artwork(
                state: widget.state,
                path: item[artist ? 'portraitPath' : 'coverPath'] as String?,
                label: item['name'] as String,
                round: artist,
                size: widget.state.senior ? 64 : 48,
                revision: artist
                    ? item['portraitVersion']?.toString()
                    : artworkVersion(item),
              ),
        title: Text(
          item['name'] as String,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w400),
        ),
        subtitle: Text('${item['count'] ?? 0} 首歌曲'),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => open(item),
      ),
    ),
  );
  Widget gridTile(Json item) {
    if (tags) {
      final dimension = item['dimension'] as String? ?? 'CUSTOM';
      final accent = switch (dimension) {
        'LANGUAGE' => const Color(0xFF38BDF8),
        'GENRE' => AppPalette.brand,
        'MOOD' => const Color(0xFFA855F7),
        'SCENE' => AppPalette.coral,
        _ => const Color(0xFF10B981),
      };
      final dark = Theme.of(context).brightness == Brightness.dark;
      return MotionPress(
        child: Glass(
          state: widget.state,
          radius: 18,
          material: GlassMaterialSpec.standard,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: dark ? .14 : .08),
                  Colors.transparent,
                ],
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => open(item),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 76),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    item['name'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Padding(
                              padding: const EdgeInsets.only(left: 14),
                              child: Text(
                                '${item['count'] ?? 0} 首歌曲',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: .65),
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
    return LayoutBuilder(
      builder: (context, size) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => open(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: artist
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      artist ? 999 : AppRadii.artwork,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? .12
                            : .55,
                      ),
                      width: .6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? .34
                              : .10,
                        ),
                        blurRadius: 18,
                        spreadRadius: -4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Artwork(
                    state: widget.state,
                    path:
                        item[artist ? 'portraitPath' : 'coverPath'] as String?,
                    round: artist,
                    size: artist ? math.min(124, size.maxWidth) : size.maxWidth,
                    revision: artist
                        ? item['portraitVersion']?.toString()
                        : artworkVersion(item),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  item['name'] as String,
                  textAlign: artist ? TextAlign.center : TextAlign.start,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['count'] ?? 0} 首${artist ? '歌曲' : ' · 家庭共享'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageInset = MediaQuery.sizeOf(context).width < 375 ? 16.0 : 20.0;
    final rows = <({String? heading, Json? item})>[];
    if (tags) {
      for (final dimension in {
        ...tagDimensions.keys,
        ...items.map((t) => t['dimension'] as String? ?? 'CUSTOM'),
      }) {
        final group = items.where(
          (t) => (t['dimension'] ?? 'CUSTOM') == dimension,
        );
        if (group.isEmpty) continue;
        rows.add((heading: tagDimensions[dimension] ?? dimension, item: null));
        rows.addAll(group.map((item) => (heading: null, item: item)));
      }
    } else {
      rows.addAll(items.map((item) => (heading: null, item: item)));
    }
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return AppEnvironment(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppToolbar(
          leading: Navigator.canPop(context)
              ? Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
                  child: Glass(
                    state: widget.state,
                    radius: 24,
                    variant: GlassVariant.liquid,
                    child: const BackButton(),
                  ),
                )
              : null,
          title: Text(widget.kind == '共享歌单' ? '家庭歌单' : widget.kind),
        ),
        body: Stack(
          children: [
            ContentWidth(
              child: RefreshIndicator(
                edgeOffset: topInset,
                onRefresh: load,
                child: CustomScrollView(
                  key: PageStorageKey(
                    'browse:${widget.state.instanceId}:${widget.kind}',
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: topInset + 6)),
                    if (!tags)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          pageInset,
                          4,
                          pageInset,
                          20,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _SongSearchField(
                            state: widget.state,
                            fieldKey: const ValueKey('browse-search'),
                            controller: search,
                            focusNode: searchFocus,
                            hint:
                                '搜索${widget.kind == '共享歌单' ? '家庭歌单' : widget.kind}',
                            suffix: search.text.isEmpty
                                ? const SizedBox.shrink()
                                : IconButton(
                                    tooltip: '搜索',
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size.square(44),
                                      fixedSize: const Size.square(44),
                                      padding: EdgeInsets.zero,
                                    ),
                                    onPressed: load,
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 19,
                                    ),
                                  ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              load();
                              searchFocus.unfocus();
                            },
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: pageInset),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              widget.state.senior ||
                                  constraints.crossAxisExtent < 300 ||
                                  MediaQuery.textScalerOf(context).scale(15) >
                                      21
                              ? 1
                              : 2;
                          final display =
                              <({String? heading, List<Json> items})>[];
                          for (var index = 0; index < rows.length;) {
                            final row = rows[index++];
                            if (row.heading != null) {
                              display.add((heading: row.heading, items: []));
                            } else {
                              final group = [row.item!];
                              if (columns == 2 &&
                                  index < rows.length &&
                                  rows[index].heading == null) {
                                group.add(rows[index++].item!);
                              }
                              display.add((heading: null, items: group));
                            }
                          }
                          return SliverList.builder(
                            itemCount: display.length,
                            itemBuilder: (context, index) {
                              final row = display[index];
                              if (row.heading != null) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 20,
                                    bottom: 12,
                                  ),
                                  child: SectionTitle(row.heading!),
                                );
                              }
                              if (columns == 1) return tile(row.items.single);
                              return Padding(
                                padding: EdgeInsets.only(bottom: tags ? 8 : 20),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: gridTile(row.items.first)),
                                    SizedBox(width: tags ? 8 : 20),
                                    Expanded(
                                      child: row.items.length == 2
                                          ? gridTile(row.items.last)
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pageInset, 0, pageInset, 32),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (error != null)
                              Notice(
                                error!,
                                action: () => load(more: failedMore),
                              ),
                            if (loading)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            if (!loading && error == null && items.isEmpty)
                              Notice(
                                search.text.isNotEmpty
                                    ? '没有找到匹配内容，试试其他关键词。'
                                    : tags
                                    ? '还没有歌曲分类，请在 NAS 管理端整理曲库。'
                                    : artist
                                    ? '曲库还没有歌手。'
                                    : '还没有家庭歌单，请在 NAS 管理端创建。',
                              ),
                            if (items.length < total &&
                                !loading &&
                                error == null)
                              TextButton(
                                onPressed: () => load(more: true),
                                child: const Text('加载更多'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset + 16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .60, 1],
                      colors: [
                        scaffoldBg.withValues(alpha: .86),
                        scaffoldBg.withValues(alpha: .42),
                        scaffoldBg.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 36,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scaffoldBg.withValues(alpha: 0),
                        scaffoldBg.withValues(alpha: .86),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.state, required this.id});
  final AppState state;
  final String id;
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  late Future<dynamic> data = widget.state.get(
    '/api/v1/playlists/${widget.id}',
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return AppEnvironment(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppToolbar(
          leading: Navigator.canPop(context)
              ? Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
                  child: Glass(
                    state: widget.state,
                    radius: 24,
                    variant: GlassVariant.liquid,
                    child: const BackButton(),
                  ),
                )
              : null,
          title: const Text('家庭歌单'),
        ),
        body: FutureBuilder<dynamic>(
          future: data,
          builder: (context, result) {
            if (result.hasError) {
              return Padding(
                padding: EdgeInsets.fromLTRB(20, topInset + 20, 20, 20),
                child: Notice(
                  result.error.toString(),
                  action: () => setState(
                    () => data = widget.state.get(
                      '/api/v1/playlists/${widget.id}',
                    ),
                  ),
                ),
              );
            }
            if (!result.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final item = result.data as Json;
            final songs = (item['songs'] as List).cast<Json>();
            final coverPath = item['coverPath'] as String?;
            final coverSize = widget.state.senior ? 148.0 : 180.0;
            return Stack(
              children: [
                if (coverPath != null && coverPath.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 500,
                    child: IgnorePointer(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .28, .62, .88, 1],
                          colors: [
                            Color(0xDD000000),
                            Color(0xAA000000),
                            Color(0x38000000),
                            Colors.transparent,
                            Colors.transparent,
                          ],
                        ).createShader(bounds),
                        child: Opacity(
                          opacity: dark ? .46 : .22,
                          child: AmbientArtwork(
                            state: widget.state,
                            song: Song({
                              'id': widget.id,
                              'title': item['name'],
                              'coverPath': coverPath,
                              'coverVersion': artworkVersion(item),
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ContentWidth(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) {
                      final h = bounds.height <= 0 ? 1.0 : bounds.height;
                      final fadeStart = ((topInset - 14) / h).clamp(0.0, 0.25);
                      final fadeEnd = ((topInset + 12) / h).clamp(
                        fadeStart + 0.01,
                        0.30,
                      );
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, fadeStart, fadeEnd, 1],
                        colors: const [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                        ],
                      ).createShader(bounds);
                    },
                    child: CustomScrollView(
                      key: PageStorageKey(
                        'playlist:${widget.state.instanceId}:${widget.id}',
                      ),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            topInset + 12,
                            20,
                            16,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Column(
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: dark ? .18 : .70,
                                            ),
                                            width: .8,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: dark ? .46 : .16,
                                              ),
                                              blurRadius: 28,
                                              spreadRadius: -4,
                                              offset: const Offset(0, 14),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          child: Artwork(
                                            state: widget.state,
                                            path: coverPath,
                                            label: item['name'] as String,
                                            revision: artworkVersion(item),
                                            size: coverSize,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        item['name'] as String,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -.4,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item['count'] ?? songs.length} 首 · 家庭共享',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontSize: widget.state.senior
                                                  ? 16
                                                  : 13,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                      if ((item['description'] as String? ?? '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 320,
                                          ),
                                          child: Text(
                                            item['description'] as String,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurfaceVariant
                                                      .withValues(alpha: .85),
                                                  height: 1.45,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (songs.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            AppPalette.brand,
                                            AppPalette.brandDeep,
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppPalette.brand.withValues(
                                              alpha: .34,
                                            ),
                                            blurRadius: 20,
                                            spreadRadius: -4,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(168, 46),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 26,
                                          ),
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          shape: const StadiumBorder(),
                                          textStyle: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        onPressed: () => openSinging(
                                          context,
                                          widget.state,
                                          Song(songs.first),
                                        ),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 20,
                                        ),
                                        label: const Text('开始练唱'),
                                      ),
                                    ),
                                  ),
                                ],
                                if ((item['missingCount'] as num? ?? 0) >
                                    0) ...[
                                  const SizedBox(height: 14),
                                  Notice(
                                    '${item['missingCount']} 首歌曲暂不可用，请在 NAS 管理端整理。',
                                  ),
                                ],
                                if (songs.isEmpty) ...[
                                  const SizedBox(height: 14),
                                  const Notice('歌单还没有可播放的歌曲。'),
                                ],
                                if (songs.isNotEmpty) ...[
                                  const SizedBox(height: 22),
                                  SectionTitle(
                                    '全部曲目',
                                    trailing: Text(
                                      '${songs.length} 首',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 44),
                          sliver: SliverList.builder(
                            itemCount: songs.length,
                            itemBuilder: (context, index) => SongRow(
                              state: widget.state,
                              song: Song(songs[index]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 36,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scaffoldBg.withValues(alpha: 0),
                            scaffoldBg.withValues(alpha: .86),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SongDetail extends StatefulWidget {
  const SongDetail({
    super.key,
    required this.state,
    required this.song,
    this.credits = const [],
  });
  final AppState state;
  final Song song;
  final List<(String, String)> credits;
  @override
  State<SongDetail> createState() => _SongDetailState();
}

class _SongDetailState extends State<SongDetail> {
  late Future<dynamic> detail = widget.state.get(
    '/api/v1/mobile/library/songs/${Uri.encodeComponent(widget.song.id)}',
  );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    child: ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => FutureBuilder<dynamic>(
        future: detail,
        builder: (context, result) {
          final song = result.hasData ? Song(result.data as Json) : widget.song;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '歌曲信息',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(
                    state: widget.state,
                    path: song.cover,
                    label: song.title,
                    revision: song.coverVersion,
                    size: 64,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist.isEmpty ? '歌手未知' : song.artist,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Table(
                columnWidths: const {0: IntrinsicColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                children: [
                  for (final field in [
                    ('版本', song.version),
                    (
                      '格式',
                      '${song.mediaType == 'AUDIO' ? '音频' : '视频'} · ${song.format}',
                    ),
                    ('来源', song.source.isEmpty ? '家庭曲库' : song.source),
                    if (song.data['album'] != null)
                      ('专辑', '${song.data['album']}'),
                    ...widget.credits,
                  ])
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                          child: Text(
                            field.$1,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(field.$2),
                        ),
                      ],
                    ),
                ],
              ),
              if (result.hasError)
                Notice(
                  '详细信息暂不可读。',
                  action: () => setState(
                    () => detail = widget.state.get(
                      '/api/v1/mobile/library/songs/${Uri.encodeComponent(song.id)}',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    uiTask(context, () => widget.state.favorite(song)),
                icon: Icon(
                  widget.state.isFavorite(song)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                label: Text(widget.state.isFavorite(song) ? '取消收藏' : '收藏歌曲'),
              ),
              const SizedBox(height: 12),
              Text(
                '练唱不开麦。主动开始录音后，声音只保存在此手机。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
