import 'package:flutter/material.dart';

import '../../core/app_updates.dart';

class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key, required this.updates});
  final AppUpdates updates;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('应用更新')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '当前版本 ${updates.currentVersion}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(updates.status),
              if (updates.origin.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('安装包来自家庭 NAS：${updates.origin}'),
              ],
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed:
                    updates.checking ||
                        updates.downloading ||
                        updates.origin.isEmpty
                    ? null
                    : () => updates.check(manual: true),
                child: const Text('检查更新'),
              ),
              if (updates.release case final release?) ...[
                const SizedBox(height: 16),
                Text(
                  '可用版本 ${release['versionName']} · ${((release['size'] as num) / 1048576).toStringAsFixed(1)} MB',
                ),
                if (release['notes'] case final String notes
                    when notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(notes),
                ],
                if (updates.skipped)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('已跳过自动提醒，仍可手动更新'),
                  ),
                const SizedBox(height: 12),
                if (updates.downloading) ...[
                  LinearProgressIndicator(value: updates.progress?.clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text(
                    '${((updates.progress ?? 0) * 100).toStringAsFixed(0)}%',
                  ),
                  TextButton(
                    onPressed: updates.cancel,
                    child: const Text('取消下载'),
                  ),
                ] else if (updates.ready)
                  FilledButton(
                    onPressed: updates.install,
                    child: const Text('确认安装'),
                  )
                else
                  FilledButton(
                    onPressed: updates.download,
                    child: const Text('下载更新'),
                  ),
                TextButton(
                  onPressed: updates.downloading ? null : updates.skip,
                  child: const Text('跳过此版本'),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                '更新需要 Android 系统安装确认。首次安装需要允许此应用安装。更新保留本机作品、收藏与登录；请先结束录音、混音或导出。',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
