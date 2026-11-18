import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
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
      final spotlight =
          widget.showBrowse &&
          !searching &&
          !state.senior &&
          MediaQuery.textScalerOf(context).scale(16) <= 21 &&
          query.items.isNotEmpty;
      final rows = spotlight ? query.items.skip(1).toList() : query.items;
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
                      child: const Icon(Icons.tune_rounded),
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
          if (widget.headerActions != null) ...[
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
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in query.tagIds)
                    InputChip(
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
                'spotlight:${state.instanceId}:${query.items.first.id}',
              ),
              index: 0,
              child: SongSpotlight(state: state, song: query.items.first),
            ),
          ],
          const SizedBox(height: 16),
          SectionTitle(
            searching ? '搜索结果' : '全部曲目',
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
      final body = RefreshIndicator(
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
              padding: EdgeInsets.fromLTRB(pageInset, 4, pageInset, 0),
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
      final content = pinnedSearch
          ? Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pageInset, 4, pageInset, 0),
                  child: searchHeader,
                ),
                Expanded(child: body),
              ],
            )
          : body;
      return widget.embedded
          ? content
          : Scaffold(
              appBar: AppToolbar(title: Text(widget.title)),
              body: ContentWidth(child: content),
            );
    },
  );
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
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        prefixIconConstraints: BoxConstraints(
          minWidth: state.senior ? 44 : 36,
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
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('筛选歌曲', style: theme.textTheme.titleLarge),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              key: const PageStorageKey('song-filter-options'),
              controller: scroll,
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
              children: [
                if (widget.tags.isEmpty) const Notice('曲库还没有可用分类。'),
                for (final dimension in dimensions)
                  if (widget.tags.any(
                    (tag) => (tag['dimension'] ?? 'CUSTOM') == dimension,
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(
                        tagDimensions[dimension] ?? dimension,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: widget.senior ? 17 : 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final tag in widget.tags.where(
                          (tag) => (tag['dimension'] ?? 'CUSTOM') == dimension,
                        ))
                          FilterChip(
                            key: ValueKey('song-filter:${tag['id']}'),
                            label: Text('${tag['name']} · ${tag['count']}'),
                            selected: selected.contains(tag['id']),
                            onSelected: (yes) => setState(() {
                              yes
                                  ? selected.add(tag['id'] as String)
                                  : selected.remove(tag['id']);
                            }),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, 8, inset, 12),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => setState(selected.clear),
                    child: const Text('清除全部'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, selected.toList()),
                    child: Text('应用筛选 (${selected.length})'),
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
        for (final item in [
          (Icons.person_outline_rounded, '歌手', '歌手'),
          (Icons.grid_view_outlined, '分类', '分类'),
          (Icons.queue_music_rounded, '家庭歌单', '共享歌单'),
        ])
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: EdgeInsets.symmetric(horizontal: stacked ? 12 : 0),
              minimumSize: Size(44, state.senior ? 56 : 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
                Icon(item.$1, size: state.senior ? 22 : 18),
                SizedBox(width: stacked ? 12 : 6),
                Flexible(
                  fit: stacked ? FlexFit.tight : FlexFit.loose,
                  child: Text(
                    item.$2,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: state.senior ? 18 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (stacked) const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
      ];
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: links,
            )
          : Row(children: [for (final link in links) Expanded(child: link)]);
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
                revision: item[artist ? 'portraitVersion' : 'revision']
                    ?.toString(),
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
      return Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => open(item),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] as String,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item['count'] ?? 0} 首歌曲',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
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
                Artwork(
                  state: widget.state,
                  path: item[artist ? 'portraitPath' : 'coverPath'] as String?,
                  round: artist,
                  size: artist ? math.min(124, size.maxWidth) : size.maxWidth,
                  revision: item[artist ? 'portraitVersion' : 'revision']
                      ?.toString(),
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
    return Scaffold(
      appBar: AppToolbar(
        title: Text(widget.kind == '共享歌单' ? '家庭歌单' : widget.kind),
      ),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: load,
          child: CustomScrollView(
            key: PageStorageKey(
              'browse:${widget.state.instanceId}:${widget.kind}',
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              if (!tags)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pageInset, 4, pageInset, 20),
                  sliver: SliverToBoxAdapter(
                    child: _SongSearchField(
                      state: widget.state,
                      fieldKey: const ValueKey('browse-search'),
                      controller: search,
                      focusNode: searchFocus,
                      hint: '搜索${widget.kind == '共享歌单' ? '家庭歌单' : widget.kind}',
                      suffix: IconButton(
                        tooltip: '搜索',
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(44),
                          fixedSize: const Size.square(44),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: load,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                      ),
                      onChanged: (_) {},
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
                            MediaQuery.textScalerOf(context).scale(15) > 21
                        ? 1
                        : 2;
                    final display = <({String? heading, List<Json> items})>[];
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
                            padding: const EdgeInsets.only(top: 20, bottom: 12),
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
                        Notice(error!, action: () => load(more: failedMore)),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
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
                      if (items.length < total && !loading && error == null)
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppToolbar(title: const Text('家庭歌单')),
    body: FutureBuilder<dynamic>(
      future: data,
      builder: (context, result) {
        if (result.hasError) {
          return Notice(
            result.error.toString(),
            action: () => setState(
              () => data = widget.state.get('/api/v1/playlists/${widget.id}'),
            ),
          );
        }
        if (!result.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final item = result.data as Json;
        final songs = (item['songs'] as List).cast<Json>();
        return ContentWidth(
          child: CustomScrollView(
            key: PageStorageKey(
              'playlist:${widget.state.instanceId}:${widget.id}',
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            Artwork(
                              state: widget.state,
                              path: item['coverPath'] as String?,
                              label: item['name'] as String,
                              revision: item['revision']?.toString(),
                              size: widget.state.senior ? 144 : 176,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              item['name'] as String,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item['count'] ?? songs.length} 首 · 家庭共享',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: widget.state.senior ? 16 : 13,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if ((item['description'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            item['description'] as String,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      if ((item['missingCount'] as num? ?? 0) > 0)
                        Notice('${item['missingCount']} 首歌曲暂不可用，请在 NAS 管理端整理。'),
                      if (songs.isEmpty) const Notice('歌单还没有可播放的歌曲。'),
                      if (songs.isNotEmpty) const SectionTitle('歌单里的歌曲'),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) =>
                      SongRow(state: widget.state, song: Song(songs[index])),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
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
