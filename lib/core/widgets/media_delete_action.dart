import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../data/services/api_client.dart';
import '../../providers/providers.dart';
import 'dialog_utils.dart';

/// 媒体删除通用流程：二次确认 → 加载提示 → 调用接口 → 刷新媒体库分类、海报墙与观看记录。
/// 成功返回接口响应；取消或失败返回 null（失败时已提示错误）。
Future<ApiResponse<T>?> confirmAndDeleteMedia<T>({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required String content,
  required Future<ApiResponse<T>> Function() request,
}) async {
  final confirmed = await DialogUtils.showConfirmDialog(
    context: context,
    title: title,
    content: content,
    confirmText: '删除',
    isDestructive: true,
  );
  if (confirmed != true || !context.mounted) return null;

  DialogUtils.showLoadingDialog(context: context, message: '正在删除...');
  final resp = await request();
  if (context.mounted) Navigator.pop(context);
  if (!context.mounted) return null;

  if (!resp.isSuccess) {
    DialogUtils.showToast(
      context: context,
      message: resp.error ?? '删除失败',
      isError: true,
    );
    return null;
  }

  ref.read(categoriesProvider.notifier).refresh();
  ref.read(postersProvider.notifier).refresh();
  ref.read(watchHistoryProvider.notifier).scheduleRefresh();
  DialogUtils.showToast(context: context, message: '已删除');
  return resp;
}

/// 媒体删除提示中的通用说明
const String mediaDeleteKeepFilesNote =
    '不会删除存储中的源文件。下次扫描时会重新入库；如需永久排除，请在资源库中把所在目录加入黑名单。';

/// 操作菜单中的删除项（危险色），context 需为菜单所在的 context
shadcn.MenuButton mediaDeleteMenuButton({
  required BuildContext context,
  required String label,
  required VoidCallback onPressed,
}) {
  // shadcn destructive 在深色下偏暗，文字用 Material error 以保证两种模式下的对比度
  final color = Theme.of(context).colorScheme.error;
  return shadcn.MenuButton(
    leading: Icon(CupertinoIcons.trash, size: 18, color: color),
    child: Text(label, style: TextStyle(color: color)),
    onPressed: (menuContext) {
      shadcn.closeOverlay(menuContext);
      onPressed();
    },
  );
}
