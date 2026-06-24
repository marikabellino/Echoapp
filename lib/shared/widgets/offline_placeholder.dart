import 'package:echo/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

class OfflinePlaceholder extends StatelessWidget {
  const OfflinePlaceholder({
    super.key,
    this.message = 'Torna online per accedere a questa sezione.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 34,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.30)
                    : Colors.black.withValues(alpha: 0.22),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Sei offline',
              style: AppTextStyles.headline(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppTextStyles.bodySecondary(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
