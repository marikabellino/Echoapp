import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pull_down_button/pull_down_button.dart';

/// Confirm dialog — iOS 17+ CupertinoAlertDialog, Android Material 3.
/// Returns `true` on confirm, `false`/`null` on cancel.
Future<bool?> showAdaptiveConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Conferma',
  String cancelLabel = 'Annulla',
  bool destructive = false,
}) {
  if (Platform.isIOS || Platform.isMacOS) {
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  // Android — Material 3
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.errorContainer,
                  foregroundColor:
                      Theme.of(ctx).colorScheme.onErrorContainer,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Descriptor for an action in an adaptive action sheet.
class AdaptiveAction<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool isDestructive;

  const AdaptiveAction({
    required this.value,
    required this.label,
    this.icon,
    this.isDestructive = false,
  });
}

/// Context menu — anchored pull-down menu in the iOS "Liquid Glass" style
/// (frosted, popping up from the triggering button/area instead of a bottom
/// sheet). Returns the selected action value, or `null` if dismissed.
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  String? title,
  required List<AdaptiveAction<T>> actions,
}) async {
  final box = context.findRenderObject() as RenderBox;
  final position = box.localToGlobal(Offset.zero) & box.size;

  T? result;
  await showPullDownMenu(
    context: context,
    position: position,
    menuOffset: 4,
    items: [
      if (title != null) PullDownMenuTitle(title: Text(title)),
      for (final a in actions)
        PullDownMenuItem(
          title: a.label,
          icon: a.icon,
          isDestructive: a.isDestructive,
          onTap: () => result = a.value,
        ),
    ],
  );
  return result;
}
