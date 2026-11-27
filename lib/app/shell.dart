import 'dart:async';
import 'dart:math' as math;

import '../features/updates/update_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../features/admin/admin_page.dart';
import '../features/library/connection.dart';
import '../features/library/library_pages.dart';
import '../features/library/widgets.dart';
import '../features/singing/works_page.dart';
import '../features/tv_control/tv_page.dart';
import 'design.dart';
import 'main_tab_header.dart';
import 'mini_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});
  final AppState state;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  final collapsed = ValueNotifier(false);
  final backdrop = BackdropKey();

  @override
  void dispose() {
    collapsed.dispose();
    super.dispose();
  }

  bool trackScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification) {
      return false;
    }
    final state = widget.state;
    final offset = notification.metrics.pixels;
    final delta = notification.scrollDelta ?? 0;
    final next =
        !state.senior &&
        !state.taking &&
        MediaQuery.textScalerOf(context).scale(16) <= 21 &&
        offset >= 60 &&
        (delta < -4
            ? false
            : offset > 120 && delta > 3
            ? true
            : collapsed.value);
    collapsed.value = next;
    return false;
  }

  void selectTab(int value) {
    if (tab == value) return;
    final state = widget.state;
    if (!state.taking &&
        AppMotionScope.levelOf(context) == AppMotionLevel.full) {
      unawaited(HapticFeedback.selectionClick());
    }
    collapsed.value = false;
    setState(() => tab = value);
    if (value == 1) unawaited(state.refreshPersonal());
  }

  Widget tools(AppState state) {
    final style = IconButton.styleFrom(
      minimumSize: Size.square(MainTabHeader.actionSize(state.senior)),
    );
    return GlassToolbar(
      state: state,
      children: [
        IconButton(
          key: const Key('open-tv'),
          tooltip: '扫一扫',
          style: style,
          onPressed: () => openTv(context, state),
          icon: AppVectorIcon(AppGlyph.scan, size: state.senior ? 22 : 19),
        ),
        IconButton(
          key: const Key('open-settings'),
          tooltip: '设置',
          style: style,
          onPressed: () => openSettings(context, state),
          icon: AppVectorIcon(AppGlyph.person, size: state.senior ? 22 : 19),
        ),
      ],
    );
  }

  double navigationHeight(BuildContext context, AppState state) => math.max(
    state.senior ? 74 : 62,
    (state.senior ? 26 : 21) +
        MediaQuery.textScalerOf(context).scale(state.senior ? 17 : 11.5) *
            1.45 +
        20,
  );

  Widget navigation(
    BuildContext context,
    AppState state,
    int drafts,
    bool compact,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final solid =
        AppMotionScope.solidOf(context) ||
        state.reduceTransparency ||
        state.senior ||
        state.performanceMode;
    final full = AppMotionScope.levelOf(context) == AppMotionLevel.full;
    final height = compact && !state.senior
        ? 54.0
        : navigationHeight(context, state);
    return Glass(
      state: state,
      radius: 999,
      variant: GlassVariant.liquid,
      backdropContext: GlassBackdropContext.content,
      child: AnimatedContainer(
        duration: full ? AppMotion.expand : Duration.zero,
        curve: AppMotion.fluid,
        height: height,
        padding: const EdgeInsets.all(5),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                alignment: Alignment(tab - 1.0, 0),
                duration: full ? AppMotion.navigation : Duration.zero,
                curve: AppMotion.bouncySpring,
                child: FractionallySizedBox(
                  widthFactor: 1 / 3,
                  heightFactor: 1,
                  child: LiquidDropletBox(radius: 999, solid: solid),
                ),
              ),
            ),
            Row(
              children: [
                for (final entry in const [
                  (
                    0,
                    Icons.music_note_outlined,
                    Icons.music_note_rounded,
                    '点歌',
                    'nav-songs',
                  ),
                  (
                    1,
                    Icons.favorite_outline_rounded,
                    Icons.favorite_rounded,
                    '常唱',
                    'nav-frequent',
                  ),
                  (
                    2,
                    Icons.graphic_eq_rounded,
                    Icons.graphic_eq_rounded,
                    '作品',
                    'nav-works',
                  ),
                ])
                  Expanded(
                    child: Semantics(
                      selected: tab == entry.$1,
                      label: compact ? entry.$4 : null,
                      child: TextButton(
                        key: Key(entry.$5),
                        style: TextButton.styleFrom(
                          shape: const StadiumBorder(),
                          minimumSize: Size(44, height - 10),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: tab == entry.$1
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        onPressed: () => selectTab(entry.$1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                entry.$1 == 2
                                    ? AppVectorIcon(
                                        AppGlyph.waveform,
                                        size: state.senior ? 25 : 21,
                                        filled: tab == 2,
                                        color: tab == 2
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      )
                                    : Icon(
                                        tab == entry.$1 ? entry.$3 : entry.$2,
                                        size: state.senior ? 26 : 21,
                                      ),
                                if (entry.$1 == 2 && drafts > 0)
                                  Positioned(
                                    right: -10,
                                    top: -5,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppPalette.brand,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color:
                                              Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? const Color(0xFF23232D)
                                              : Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$drafts',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 2),
                              Text(
                                entry.$4,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: state.senior ? 17 : 11.5,
                                  height: 1.2,
                                  fontWeight: tab == entry.$1
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget dock(
    BuildContext context,
    AppState state,
    int drafts,
    bool collapsed,
  ) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final compact =
        collapsed &&
        !state.senior &&
        !state.taking &&
        MediaQuery.textScalerOf(context).scale(16) <= 21;
    final hideRedundantDraftMini =
        tab == 2 &&
        state.pendingReviewId.isNotEmpty &&
        !state.taking &&
        !state.isPlaying;
    final hasPlayer = state.current != null && !hideRedundantDraftMini;
    final full = AppMotionScope.levelOf(context) == AppMotionLevel.full;
    final duration = full ? AppMotion.expand : Duration.zero;
    final background = Theme.of(context).scaffoldBackgroundColor;
    final solidDock =
        AppMotionScope.solidOf(context) ||
        state.reduceTransparency ||
        state.senior ||
        state.performanceMode;
    final safe = MediaQuery.viewPaddingOf(context).bottom;
    final navHeight = compact ? 54.0 : navigationHeight(context, state);
    final miniHeight = hasPlayer
        ? MiniPlayer.heightOf(context, state, compact: compact)
        : 0.0;
    final controlsHeight = compact
        ? math.max(navHeight, miniHeight)
        : navHeight + (hasPlayer ? miniHeight + 9 : 0);
    final dockHeight = controlsHeight + safe + 10;
    return ContentWidth(
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.fluid,
        height: dockHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Soft bottom vignette shields the dock's rounded corners and gap
            // from peeking list thumbnails while keeping top glass luminous.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: solidDock ? dockHeight + 36 : dockHeight + 16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: solidDock
                          ? const [0, .24, .52, .80, 1]
                          : const [0, .26, .62, 1],
                      colors: solidDock
                          ? [
                              background.withValues(alpha: 0),
                              background.withValues(alpha: .42),
                              background.withValues(alpha: .84),
                              background.withValues(alpha: .96),
                              background,
                            ]
                          : [
                              background.withValues(alpha: 0),
                              background.withValues(alpha: .24),
                              background.withValues(alpha: .78),
                              background.withValues(alpha: .95),
                            ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: safe + 10,
              height: controlsHeight,
              child: LayoutBuilder(
                builder: (context, box) {
                  final totalWidth = box.maxWidth;
                  const compactNavWidth = 148.0;
                  const gap = 8.0;
                  final compactRow =
                      compact &&
                      hasPlayer &&
                      totalWidth >= compactNavWidth + gap + 120;
                  final navWidth = compact ? compactNavWidth : totalWidth;
                  final navLeft = compact && !compactRow
                      ? (totalWidth - navWidth) / 2
                      : 0.0;
                  final miniLeft = compactRow ? compactNavWidth + gap : 0.0;
                  final miniWidth = compactRow
                      ? totalWidth - compactNavWidth - gap
                      : totalWidth;
                  final miniBottom = compactRow ? 0.0 : navHeight + 9.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (hasPlayer)
                        AnimatedPositioned(
                          duration: duration,
                          curve: AppMotion.fluid,
                          left: miniLeft,
                          bottom: miniBottom,
                          width: miniWidth,
                          height: miniHeight,
                          child: MiniPlayer(
                            state: state,
                            inset: false,
                            compact: compactRow,
                          ),
                        ),
                      AnimatedPositioned(
                        duration: duration,
                        curve: AppMotion.fluid,
                        left: navLeft,
                        bottom: 0,
                        width: navWidth,
                        height: navHeight,
                        child: navigation(context, state, drafts, compact),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final drafts = state.visibleWorks
          .where((w) => w['status'] != 'SAVED' && w['status'] != 'MISSING')
          .length;
      final overlay = Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark;
      final shell = PopScope(
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) selectTab(0);
        },
        child: AppBackdropPage(
          extendBody: true,
          glow: ShellAmbientGlow(state: state),
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay.copyWith(
              statusBarColor: Colors.transparent,
              systemStatusBarContrastEnforced: false,
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: ContentWidth(
                child: NotificationListener<ScrollNotification>(
                  onNotification: trackScroll,
                  child: IndexedStack(
                    index: tab,
                    children: [
                      TickerMode(
                        enabled: tab == 0,
                        child: MotionTabPane(
                          active: tab == 0,
                          child: state.authenticated
                              ? SongsPage(
                                  key: ValueKey(state.instanceId),
                                  state: state,
                                  embedded: true,
                                  showBrowse: true,
                                  headerActions: tools(state),
                                )
                              : _Disconnected(
                                  state: state,
                                  headerActions: tools(state),
                                  onOpenWorks: () => selectTab(2),
                                ),
                        ),
                      ),
                      TickerMode(
                        enabled: tab == 1,
                        child: MotionTabPane(
                          active: tab == 1,
                          child: FrequentPage(
                            key: ValueKey('personal:${state.instanceId}'),
                            state: state,
                            headerActions: tools(state),
                          ),
                        ),
                      ),
                      TickerMode(
                        enabled: tab == 2,
                        child: MotionTabPane(
                          active: tab == 2,
                          child: WorksPage(
                            state: state,
                            embedded: true,
                            headerActions: tools(state),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder<bool>(
            valueListenable: collapsed,
            builder: (context, value, _) => dock(context, state, drafts, value),
          ),
        ),
      );
      return BackdropGroup(backdropKey: backdrop, child: shell);
    },
  );
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({
    required this.state,
    required this.headerActions,
    required this.onOpenWorks,
  });
  final AppState state;
  final Widget headerActions;
  final VoidCallback onOpenWorks;
  @override
  Widget build(BuildContext context) {
    final material = AppSurfaces.of(context);
    final inset = MainTabHeader.insetOf(context);
    final children = [
      if (state.error != null) Notice(state.error!),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F1F2B), Color(0xFF331826), Color(0xFF15151D)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 34,
              spreadRadius: -8,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -50,
              child: IgnorePointer(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppPalette.brand.withValues(alpha: .42),
                        AppPalette.brand.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .24),
                          width: .8,
                        ),
                      ),
                      child: Icon(
                        Icons.library_music_rounded,
                        size: 30,
                        color: material.onSpotlight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    state.origin.isEmpty ? '连接家庭曲库' : '重新连接家庭曲库',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: material.onSpotlight,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '从 NAS 选歌练唱，录音保存在手机。已保存的作品可以离线回听。',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: material.spotlightMuted),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: Size.fromHeight(state.senior ? 58 : 52),
                      backgroundColor: AppPalette.brand,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => openConnection(context, state),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(state.origin.isEmpty ? '连接 NAS' : '重新登录'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Glass(
        state: state,
        radius: 999,
        material: GlassMaterialSpec.standard,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(state.senior ? 58 : 50),
            backgroundColor: Colors.transparent,
            shape: const StadiumBorder(),
          ),
          onPressed: onOpenWorks,
          icon: Icon(
            Icons.headphones_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          label: const Text('查看本机作品'),
        ),
      ),
    ];
    return CustomScrollView(
      slivers: [
        MainTabHeader(senior: state.senior, actions: headerActions),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, AppSpace.xxs, inset, 0),
          sliver: SliverList.list(children: children),
        ),
        const SliverBottomSpace(),
      ],
    );
  }
}

class FrequentPage extends StatefulWidget {
  const FrequentPage({super.key, required this.state, this.headerActions});
  final AppState state;
  final Widget? headerActions;
  @override
  State<FrequentPage> createState() => _FrequentPageState();
}

class _FrequentPageState extends State<FrequentPage> {
  bool history = false;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> clear() async {
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空最近练唱？'),
        content: const Text('只清除此 NAS 在手机上的记录，不影响收藏和作品。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空记录'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await uiTask(context, () async {
        await widget.state.store.clearHistory(widget.state.instanceId);
        await widget.state.refreshPersonal();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final actions = widget.headerActions;
    final inset = actions == null
        ? AppSpace.page
        : MainTabHeader.insetOf(context);
    final rows = (history ? state.history : state.favorites)
        .where(
          (s) => '${s.title} ${s.artist}'.toLowerCase().contains(
            search.text.toLowerCase(),
          ),
        )
        .toList();
    final searchField = GlassSearchField(
      state: state,
      controller: search,
      focusNode: searchFocus,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => searchFocus.unfocus(),
      hintText: history ? '搜索最近练唱' : '搜索收藏歌曲',
      suffix: search.text.isEmpty
          ? null
          : IconButton(
              tooltip: '清除搜索',
              onPressed: () => setState(search.clear),
              icon: const Icon(Icons.cancel_rounded),
            ),
    );
    return CustomScrollView(
      key: PageStorageKey('personal-scroll:${state.instanceId}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (actions != null)
          MainTabHeader(
            senior: state.senior,
            actions: actions,
            search: searchField,
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            inset,
            actions == null ? AppSpace.xxs : 0,
            inset,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (actions == null) ...[
                  searchField,
                  const SizedBox(height: 10),
                ],
                AppSegments<bool>(
                  liquid: true,
                  values: const [(false, '收藏'), (true, '最近练唱')],
                  selected: history,
                  senior: state.senior,
                  onChanged: (value) => setState(() => history = value),
                ),
                if (search.text.isEmpty && !state.senior) ...[
                  const SizedBox(height: 16),
                  _CollectionCover(
                    state: state,
                    history: history,
                    songs: history ? state.history : state.favorites,
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
                  child: SectionTitle(
                    history ? '最近练唱' : '收藏曲目',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          !history && !state.favoritesReady
                              ? '待读取'
                              : '${history ? state.history.length : state.favorites.length} 首',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        if (history && state.history.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton(onPressed: clear, child: const Text('清空')),
                        ] else if (!history) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: '刷新收藏',
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(32),
                              fixedSize: const Size.square(32),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed:
                                state.favoritesLoading || state.favoriteSaving
                                ? null
                                : () => state.refreshFavorites(),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!history) ...[
                  if (state.favoritesLoading) const LinearProgressIndicator(),
                  if (state.favoritesError != null)
                    Notice('收藏读取失败：${state.favoritesError}。当前内容可能尚未更新。'),
                  if (!state.authenticated)
                    const Notice('连接 NAS 并登录后读取共享收藏。练唱记录仍可在本机查看。'),
                ],
                if (rows.isEmpty &&
                    (history ||
                        (state.authenticated &&
                            state.favoritesReady &&
                            !state.favoritesLoading &&
                            state.favoritesError == null)))
                  Notice(
                    search.text.isNotEmpty
                        ? '没有匹配的歌曲，试试其他关键词。'
                        : history
                        ? '唱过的歌曲会出现在这里。'
                        : '还没有收藏。点歌曲旁的爱心，就能在这里快速找到。',
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => MotionEntrance(
              key: ValueKey('personal:${state.instanceId}:${rows[index].id}'),
              index: index,
              child: SongRow(state: state, song: rows[index]),
            ),
          ),
        ),
        const SliverBottomSpace(),
      ],
    );
  }
}

class _CollectionCover extends StatelessWidget {
  const _CollectionCover({
    required this.state,
    required this.history,
    required this.songs,
  });
  final AppState state;
  final bool history;
  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final large = MediaQuery.textScalerOf(context).scale(16) > 21;
    return Glass(
      state: state,
      radius: 26,
      material: GlassMaterialSpec.standard,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        history
                            ? Icons.history_rounded
                            : Icons.favorite_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          history ? '本机记录' : '多端同步',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    history ? '唱过，还想再唱' : '喜欢的，都在这里',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    history ? '保存在此手机的练唱足迹' : '手机、电视与后台实时共享',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!large && songs.isNotEmpty) ...[
              const SizedBox(width: 14),
              SizedBox(
                width: 108,
                height: 92,
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      for (
                        var index = songs.take(3).length - 1;
                        index >= 0;
                        index--
                      )
                        Positioned(
                          right: index * 14.0,
                          top: (2 - index) * 3.0,
                          child: Transform.rotate(
                            angle: -index * .10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .82),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .22),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Artwork(
                                state: state,
                                path: songs[index].cover,
                                revision: songs[index].coverVersion,
                                size: 76 - index * 4.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void openSettings(BuildContext context, AppState state) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'settings'),
    builder: (_) => SettingsPage(state: state),
  ),
);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
      Widget group(
        String title,
        List<Widget> children, {
        double dividerIndent = 16,
      }) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Glass(
              state: state,
              radius: 24,
              material: GlassMaterialSpec.standard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: dividerIndent, endIndent: 16),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      Widget badge(IconData data, List<Color> colors) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Icon(data, size: 18, color: Colors.white),
      );
      return AppBackdropPage(
        glow: ShellAmbientGlow(state: state),
        appBar: const AppToolbar(title: Text('设置')),
        body: ContentWidth(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              topInset + 10,
              20,
              28 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              group('家庭曲库', [
                ListTile(
                  leading: badge(Icons.dns_rounded, const [
                    AppPalette.brand,
                    AppPalette.coral,
                  ]),
                  title: const Text('NAS 连接与账号'),
                  subtitle: Text(
                    state.authenticated
                        ? '${state.accountName.isEmpty ? '已登录' : state.accountName}\n${state.origin}'
                        : state.origin.isEmpty
                        ? '尚未连接'
                        : '需要登录\n${state.origin}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openConnection(context, state),
                ),
                ListTile(
                  key: const Key('open-admin'),
                  leading: badge(Icons.tune_rounded, const [
                    Color(0xFF3B82F6),
                    Color(0xFF6366F1),
                  ]),
                  title: const Text('管理端'),
                  subtitle: Text(
                    state.origin.isEmpty
                        ? '连接 NAS 后管理曲库和系统设置'
                        : '管理当前 NAS 的曲库和系统设置',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openAdmin(context, state),
                ),
                ListenableBuilder(
                  listenable: state.updates,
                  builder: (context, _) => ListTile(
                    leading: badge(Icons.system_update_rounded, const [
                      Color(0xFF10B981),
                      Color(0xFF059669),
                    ]),
                    title: const Text('应用更新'),
                    subtitle: Text(state.updates.status),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: 'updates'),
                        builder: (_) => UpdatePage(updates: state.updates),
                      ),
                    ),
                  ),
                ),
              ], dividerIndent: 58),
              group('外观', [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      for (final item in const [
                        (ThemeMode.light, Icons.light_mode_rounded, '浅色'),
                        (ThemeMode.dark, Icons.dark_mode_rounded, '深色'),
                        (
                          ThemeMode.system,
                          Icons.brightness_auto_rounded,
                          '跟随系统',
                        ),
                      ]) ...[
                        if (item.$1 != ThemeMode.light)
                          const SizedBox(width: 8),
                        Expanded(
                          child: () {
                            final active = state.themeMode == item.$1;
                            final dark =
                                Theme.of(context).brightness == Brightness.dark;
                            return Semantics(
                              selected: active,
                              button: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => uiTask(
                                  context,
                                  () => state.setTheme(item.$1),
                                ),
                                child: active
                                    ? LiquidDropletBox(
                                        radius: 16,
                                        accent: true,
                                        solid:
                                            AppMotionScope.solidOf(context) ||
                                            state.reduceTransparency ||
                                            state.senior ||
                                            state.performanceMode,
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: state.senior ? 14 : 11,
                                            horizontal: 6,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                item.$2,
                                                size: state.senior ? 22 : 19,
                                                color: scheme.primary,
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                item.$3,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      fontSize: state.senior
                                                          ? 15
                                                          : 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: scheme.primary,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : AnimatedContainer(
                                        duration: AppMotionScope.durationOf(
                                          context,
                                          AppMotion.release,
                                        ),
                                        curve: AppMotion.fluid,
                                        padding: EdgeInsets.symmetric(
                                          vertical: state.senior ? 14 : 11,
                                          horizontal: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          color: scheme.onSurface.withValues(
                                            alpha: dark ? .05 : .035,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: dark ? .07 : .45,
                                            ),
                                            width: .6,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              item.$2,
                                              size: state.senior ? 22 : 19,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              item.$3,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontSize: state.senior
                                                        ? 15
                                                        : 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            );
                          }(),
                        ),
                      ],
                    ],
                  ),
                ),
                SwitchListTile(
                  key: const Key('liquid-glass-mode'),
                  value: state.liquidGlass,
                  onChanged: (value) =>
                      uiTask(context, () => state.setLiquidGlass(value)),
                  title: const Text('液态玻璃效果'),
                  subtitle: Text(
                    state.liquidGlass
                        ? (state.senior
                              ? '已开启，长辈模式下自动使用清晰实底'
                              : '已开启，启用实时折射、模糊与流畅动效')
                        : '已关闭，使用清晰实底并节省性能',
                  ),
                ),
              ]),
              group('使用体验', [
                SwitchListTile(
                  value: state.senior,
                  onChanged: (value) => uiTask(
                    context,
                    () => state.setUiMode(
                      value ? UiMode.senior : UiMode.standard,
                    ),
                  ),
                  title: Text(state.senior ? '长辈模式已开启' : '长辈模式'),
                  subtitle: const Text('放大文字和按钮'),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '歌曲与收藏来自 NAS，后台、手机和电视共用收藏。练唱记录与录音作品保存在此手机。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (state.defaultPassword) ...[
                const SizedBox(height: 14),
                Glass(
                  state: state,
                  radius: 18,
                  material: GlassMaterialSpec.standard,
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppPalette.brand.withValues(alpha: .14),
                      ),
                      child: Icon(
                        Icons.gpp_maybe_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      'NAS 仍使用初始密码，请在管理端修改。',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openAdmin(context, state),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
