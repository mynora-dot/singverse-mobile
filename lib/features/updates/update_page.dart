import 'package:flutter/material.dart';

import '../../core/app_updates.dart';
import '../../app/design.dart';

class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key, required this.updates});
  final AppUpdates updates;

  Widget _primaryButton(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppPalette.brand, AppPalette.brandDeep],
              )
            : null,
        border: enabled
            ? Border.all(color: Colors.white.withValues(alpha: .26), width: .8)
            : null,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppPalette.brand.withValues(alpha: .34),
                  blurRadius: 22,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: enabled ? Colors.transparent : null,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: theme.textTheme.titleMedium?.copyWith(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final release = updates.release;
      final host = updates.origin.replaceFirst(RegExp(r'^https?://'), '');
      final canCheck =
          !updates.checking &&
          !updates.downloading &&
          updates.origin.isNotEmpty;
      return AppBackdropPage(
        appBar: AppToolbar(
          leading: Navigator.canPop(context)
              ? const Padding(
                  padding: EdgeInsets.only(left: 12, top: 2, bottom: 2),
                  child: GlassSurface(
                    radius: 24,
                    variant: GlassVariant.liquid,
                    child: BackButton(),
                  ),
                )
              : null,
          title: const Text('应用更新'),
        ),
        body: SafeArea(
          bottom: false,
          child: ContentWidth(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                40 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                GlassSurface(
                  radius: 26,
                  material: GlassMaterialSpec.standard,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: release != null
                                  ? const [AppPalette.brand, AppPalette.coral]
                                  : const [
                                      Color(0xFF10B981),
                                      Color(0xFF059669),
                                    ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (release != null
                                            ? AppPalette.brand
                                            : const Color(0xFF10B981))
                                        .withValues(alpha: .32),
                                blurRadius: 22,
                                spreadRadius: -4,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '当前版本 ${updates.currentVersion}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            updates.status,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ),
                        if (host.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(
                                alpha: dark ? .08 : .05,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '来源 · $host',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
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
                const SizedBox(height: 20),
                if (release != null) ...[
                  GlassSurface(
                    radius: 24,
                    material: GlassMaterialSpec.standard,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '新版本 ${release['versionName']}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${((release['size'] as num) / 1048576).toStringAsFixed(1)} MB',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (release['notes'] case final String notes
                              when notes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            MotionExpand(
                              child: Text(
                                notes,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (updates.downloading) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 7,
                                color: AppPalette.brand,
                                backgroundColor: scheme.onSurface.withValues(
                                  alpha: .12,
                                ),
                                value: updates.progress?.clamp(0, 1),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  '${((updates.progress ?? 0) * 100).toStringAsFixed(0)}%',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: updates.cancel,
                                  child: const Text('取消下载'),
                                ),
                              ],
                            ),
                          ] else if (updates.ready)
                            _primaryButton(
                              context,
                              label: '确认安装',
                              onPressed: updates.install,
                            )
                          else
                            _primaryButton(
                              context,
                              label: '下载更新',
                              onPressed: updates.download,
                            ),
                          if (!updates.downloading) ...[
                            const SizedBox(height: 4),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.onSurfaceVariant,
                              ),
                              onPressed: updates.skip,
                              child: Text(
                                updates.skipped ? '已跳过自动提醒' : '跳过此版本',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    onPressed: canCheck
                        ? () => updates.check(manual: true)
                        : null,
                    child: Text(updates.checking ? '正在检查…' : '重新检查更新'),
                  ),
                ] else
                  _primaryButton(
                    context,
                    label: updates.checking ? '正在检查…' : '检查更新',
                    onPressed: canCheck
                        ? () => updates.check(manual: true)
                        : null,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
