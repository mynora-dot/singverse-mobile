import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/design.dart';
import '../../core/nas_discovery.dart';

class NasDiscoveryPage extends StatefulWidget {
  const NasDiscoveryPage({super.key, required this.discovery});
  final NasDiscovery discovery;
  @override
  State<NasDiscoveryPage> createState() => _NasDiscoveryPageState();
}

class _NasDiscoveryPageState extends State<NasDiscoveryPage>
    with WidgetsBindingObserver {
  NasDiscoverySnapshot snapshot = const NasDiscoverySnapshot(searching: true);
  StreamSubscription<NasDiscoverySnapshot>? subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = widget.discovery.snapshots.listen(
      (value) {
        if (mounted) setState(() => snapshot = value);
      },
      onError: (Object _) {
        if (mounted) {
          setState(
            () => snapshot = const NasDiscoverySnapshot(
              error: '无法查找局域网设备，请检查网络后重试',
            ),
          );
        }
      },
    );
    start();
  }

  Future<void> start() async {
    setState(() => snapshot = const NasDiscoverySnapshot(searching: true));
    try {
      await widget.discovery.start();
    } catch (_) {
      if (mounted) {
        setState(
          () => snapshot = const NasDiscoverySnapshot(
            error: '无法查找局域网设备，请检查网络后重试',
          ),
        );
      }
    }
  }

  Future<void> stop() async {
    try {
      await widget.discovery.stop();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(subscription?.cancel());
    unawaited(stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppToolbar(title: const Text('查找局域网 NAS')),
    body: SafeArea(
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              snapshot.searching
                  ? '正在查找设备'
                  : snapshot.services.isEmpty
                  ? '未发现设备'
                  : '找到 ${snapshot.services.length} 台 NAS',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              snapshot.searching
                  ? '请让手机与 NAS 连接同一局域网。查找将在 15 秒后结束。'
                  : '请让手机与 NAS 连接同一局域网。选择设备，或重新查找。',
            ),
            const SizedBox(height: 20),
            if (snapshot.searching) const LinearProgressIndicator(),
            if (snapshot.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(snapshot.error!),
              ),
            const SizedBox(height: 20),
            for (final service in snapshot.services)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    key: ValueKey('discovered-nas:${service.origin}'),
                    leading: const Icon(Icons.dns_outlined, size: 24),
                    title: Text(service.name),
                    subtitle: Text(service.origin),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () async {
                      await stop();
                      if (context.mounted) Navigator.pop(context, service);
                    },
                  ),
                ),
              ),
            if (!snapshot.searching)
              FilledButton.icon(
                onPressed: start,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('重新查找'),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('手动输入 IP 或域名'),
            ),
            const SizedBox(height: 20),
            const Text('请在 NAS 开启局域网发现。未开启发现、使用访客 Wi-Fi 或网络隔离时，可手动输入地址。'),
          ],
        ),
      ),
    ),
  );
}
