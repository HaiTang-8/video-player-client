import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/password_text_field.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDesktop = WindowControls.isDesktop;
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;
    final playbackSettings = ref.watch(playbackSettingsProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: colors.groupedBackground,
      appBar: isDesktop
          ? const DesktopTitleBar(
              title: Text('我的'),
              centerTitle: true,
            )
          : AppBar(
              title: const Text('我的'),
            ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (authState.authEnabled && authState.user != null) ...[
            _buildUserCard(context, theme, isDark, colors, authState),
            const SizedBox(height: 24),
            _buildSectionHeader('账户', theme),
            _buildSettingsCard(
              context,
              theme,
              isDark,
              children: [
                _buildListTile(
                  context,
                  icon: CupertinoIcons.lock,
                  iconColor: Colors.blue,
                  title: '修改密码',
                  onTap: () => _showChangePasswordDialog(context, ref),
                ),
                _buildDivider(theme),
                _buildListTile(
                  context,
                  icon: CupertinoIcons.square_arrow_left,
                  iconColor: Colors.red,
                  title: '退出登录',
                  onTap: () => _handleLogout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          _buildSectionHeader('播放', theme),
          _buildSettingsCard(
            context,
            theme,
            isDark,
            children: [
              _buildListTile(
                context,
                icon: CupertinoIcons.forward_end,
                iconColor: Colors.orange,
                title: '快进/快退时长',
                subtitle: '${playbackSettings.seekDuration}秒',
                onTap: () => context.push('/playback-settings'),
              ),
              _buildDivider(theme),
              _buildListTile(
                context,
                icon: CupertinoIcons.speedometer,
                iconColor: Colors.blue,
                title: '播放速度',
                subtitle: '${playbackSettings.playbackSpeed}x',
                onTap: () => context.push('/playback-settings'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('通用', theme),
          _buildSettingsCard(
            context,
            theme,
            isDark,
            children: [
              _buildListTile(
                context,
                icon: CupertinoIcons.settings,
                iconColor: Colors.grey,
                title: '设置',
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AppColors colors,
    AuthState authState,
  ) {
    final user = authState.user!;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                CupertinoIcons.person_fill,
                size: 24,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: user.isAdmin
                          ? Colors.orange.withValues(alpha: 0.15)
                          : Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      user.isAdmin ? '管理员' : '用户',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: user.isAdmin ? Colors.orange : Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final oldPwdController = TextEditingController();
    final newPwdController = TextEditingController();
    final confirmPwdController = TextEditingController();

    DialogUtils.showCustomDialog(
      context: context,
      builder: (context) => shadcn.AlertDialog(
        barrierColor: Colors.transparent,
        surfaceOpacity: 1,
        title: const Text('修改密码'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300),
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PasswordTextField(
                  controller: oldPwdController,
                  placeholder: const Text('当前密码'),
                ),
                const SizedBox(height: 12),
                PasswordTextField(
                  controller: newPwdController,
                  placeholder: const Text('新密码'),
                ),
                const SizedBox(height: 12),
                PasswordTextField(
                  controller: confirmPwdController,
                  placeholder: const Text('确认新密码'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          shadcn.OutlineButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          shadcn.PrimaryButton(
            onPressed: () async {
              final oldPwd = oldPwdController.text;
              final newPwd = newPwdController.text;
              final confirmPwd = confirmPwdController.text;

              if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
                DialogUtils.showToast(context: context, message: '请填写所有字段', isError: true);
                return;
              }
              if (newPwd != confirmPwd) {
                DialogUtils.showToast(context: context, message: '两次输入的新密码不一致', isError: true);
                return;
              }
              if (newPwd.length < 6) {
                DialogUtils.showToast(context: context, message: '密码长度不能少于6位', isError: true);
                return;
              }

              try {
                await ref.read(authProvider.notifier).changePassword(oldPwd, newPwd);
                if (context.mounted) {
                  Navigator.pop(context);
                  DialogUtils.showToast(context: context, message: '密码已修改，请重新登录');
                }
              } catch (e) {
                if (context.mounted) {
                  DialogUtils.showToast(
                    context: context,
                    message: e.toString().replaceFirst('Exception: ', ''),
                    isError: true,
                  );
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '退出登录',
      content: '确定要退出当前账户吗？',
      confirmText: '退出',
      isDestructive: true,
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    ThemeData theme,
    bool isDark, {
    required List<Widget> children,
  }) {
    return Builder(
      builder: (context) {
        final colors = context.appColors;
        return Container(
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        );
      },
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: theme.dividerColor.withValues(alpha: 0.3),
      ),
    );
  }
}
