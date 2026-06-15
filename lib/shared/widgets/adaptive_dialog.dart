import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Mostra un dialog di conferma adattivo:
/// - iOS/macOS → CupertinoAlertDialog (stile iOS 17+)
/// - Android   → AlertDialog Material 3
///
/// Ritorna `true` se l'utente conferma, `false` / `null` se annulla.
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
