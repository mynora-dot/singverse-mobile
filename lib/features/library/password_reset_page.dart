import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/design.dart';
import '../../core/app_state.dart';
import '../../core/login_store.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.state,
    required this.store,
    required this.username,
  });
  final AppState state;
  final LoginStore store;
  final String username;
  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  late final username = TextEditingController(text: widget.username);
  final token = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, visible = false, completed = false;
  String deployment = 'docker';
  String? error;

  String get commands {
    if (deployment == 'native') return 'bin/singverse --issue-password-reset';
    final compose = deployment == 'local'
        ? 'docker compose --env-file .env.local --project-directory . -f infra/docker/compose/compose.yaml -f infra/docker/compose/compose.local.yaml'
        : 'docker compose --project-directory . -f infra/docker/compose/compose.yaml';
    return '$compose stop singverse-go-backend\n$compose run --rm --no-deps singverse-go-backend --issue-password-reset\n$compose up -d --no-deps --no-build --pull never singverse-go-backend';
  }

  @override
  void dispose() {
    username.dispose();
    token.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || widget.state.busy) return;
    setState(() => error = null);
    if (username.text.trim().isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token.text.trim())) {
      setState(() => error = '请输入账号和完整的 43 位重置码');
      return;
    }
    if (password.text.runes.length < 15 || password.text.runes.length > 128) {
      setState(() => error = '新密码需要 15～128 个字符');
      return;
    }
    if (password.text != confirmation.text) {
      setState(() => error = '两次输入的新密码不一致');
      return;
    }
    setState(() => busy = true);
    final instance = widget.state.instanceId;
    try {
      await widget.state.resetPassword(
        username: username.text,
        resetToken: token.text,
        newPassword: password.text,
      );
      if (widget.state.error != null) {
        if (mounted) {
          setState(
            () => error =
                '${widget.state.error}${widget.state.retryAfter?.isNotEmpty == true ? '，请在 ${widget.state.retryAfter} 秒后重试' : ''}',
          );
        }
        return;
      }
      completed = true;
      token.clear();
      password.clear();
      confirmation.clear();
      try {
        await widget.store.forgetServerPasswords(instance);
      } catch (_) {
        if (mounted) {
          setState(() => error = '密码已重置，但未能清除手机上的旧密码。请在历史登录中移除该曲库的旧记录。');
        }
        return;
      }
      if (mounted) Navigator.pop(context, username.text.trim());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('忘记密码')),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '重新设置 NAS 密码',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('使用部署主机生成的一次性重置码。当前曲库：${widget.state.origin}'),
              const SizedBox(height: 20),
              Card(
                child: ExpansionTile(
                  title: const Text('如何获取重置码'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '在 NAS 的 Go 后端项目目录执行命令，按提示输入 RESET。重启服务后，将重置码粘贴到下方；15 分钟内有效，仅可使用一次。',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: deployment,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '运行方式'),
                      items: const [
                        DropdownMenuItem(
                          value: 'docker',
                          child: Text('正式镜像 Docker'),
                        ),
                        DropdownMenuItem(
                          value: 'local',
                          child: Text('本地源码 Docker'),
                        ),
                        DropdownMenuItem(value: 'native', child: Text('原生进程')),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => deployment = value!),
                    ),
                    const SizedBox(height: 16),
                    if (deployment == 'native')
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('先停止业务进程，沿用原配置执行命令，然后重启业务进程。'),
                      ),
                    SelectableText(
                      commands,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton.icon(
                      onPressed: () => uiTask(context, () async {
                        await Clipboard.setData(ClipboardData(text: commands));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('命令已复制')),
                          );
                        }
                      }),
                      icon: const Icon(Icons.copy_outlined, size: 20),
                      label: const Text('复制命令'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!completed) ...[
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        key: const ValueKey('reset-username'),
                        controller: username,
                        enabled: !busy,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: '管理员账号'),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('reset-token'),
                        controller: token,
                        enabled: !busy,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: '一次性重置码',
                          hintText: '粘贴部署主机生成的重置码',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('reset-password'),
                        controller: password,
                        enabled: !busy,
                        obscureText: !visible,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: '新密码',
                          helperText: '15～128 个字符，支持空格',
                          helperMaxLines: 2,
                          suffixIcon: IconButton(
                            tooltip: visible ? '隐藏新密码' : '显示新密码',
                            onPressed: busy
                                ? null
                                : () => setState(() => visible = !visible),
                            icon: Icon(
                              visible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('reset-confirmation'),
                        controller: confirmation,
                        enabled: !busy,
                        obscureText: !visible,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(labelText: '确认新密码'),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('reset-submit'),
                  onPressed: busy ? null : submit,
                  child: Text(busy ? '正在重置…' : '重置密码'),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(error!, key: const ValueKey('reset-error')),
                  ),
                ),
              if (completed)
                FilledButton(
                  onPressed: () => Navigator.pop(context, username.text.trim()),
                  child: const Text('返回登录'),
                ),
              const SizedBox(height: 20),
              const Text('重置后所有设备需要重新登录，原有二次验证保留。若二次验证也已丢失，请在部署主机进行管理员恢复。'),
            ],
          ),
        ),
      ),
    ),
  );
}
