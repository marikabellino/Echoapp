import 'package:apptest/core/theme/app_colors.dart';
import 'package:apptest/core/theme/app_spacing.dart';
import 'package:apptest/core/theme/app_text_styles.dart';
import 'package:apptest/shared/widgets/backgrounds/animated_gradient_background.dart';
import 'package:apptest/shared/widgets/backgrounds/floating_glow.dart';
import 'package:apptest/shared/widgets/glass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class HomePage extends StatelessWidget{
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBackground(
        child: Stack(
          children: [
            const FloatingGlow(
              alignment: Alignment.topLeft,
              size: 240,
              color: AppColors.primary,
            ),

            const FloatingGlow(
              alignment: Alignment.bottomRight,
              size: 180,
              color: AppColors.accent,
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Echo',
                      style:
                          AppTextStyles.displayLarge(
                            context,
                          ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'The world remembers.',
                      style:
                          AppTextStyles.bodySecondary(
                            context,
                          ),
                    ),

                    const SizedBox(height: 40),

                    GlassCard(
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        padding:
                            const EdgeInsets.all(
                              AppSpacing.lg,
                            ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              'Nearby memory',
                              style:
                                  AppTextStyles
                                      .bodySecondary(
                                        context,
                                      ),
                            ),

                            const Spacer(),

                            Text(
                              '"Someone left a memory here 2 years ago."',
                              style:
                                  AppTextStyles
                                      .headline(
                                        context,
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
