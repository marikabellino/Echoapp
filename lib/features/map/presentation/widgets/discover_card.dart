import 'dart:ui';

import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/shared/widgets/glass_card.dart';
import 'package:flutter/material.dart';

class DiscoverCard extends StatelessWidget {
  final String title;

  final String description;

  final String place;

  const DiscoverCard({
    super.key,
    required this.title,
    required this.description,
    required this.place,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,

          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,

                  decoration:
                      const BoxDecoration(
                        shape: BoxShape.circle,

                        color: Colors.white,
                      ),
                ),

                const SizedBox(width: 10),

                Text(
                  place,

                  style:
                      AppTextStyles
                          .bodySecondary(
                            context,
                          ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Text(
              title,

              style:
                  AppTextStyles.headline(
                    context,
                  ),
            ),

            const SizedBox(height: 16),

            Text(
              description,

              style:
                  AppTextStyles.body(
                    context,
                  ),
            ),

            const SizedBox(height: 24),

            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                    24,
                  ),

              child: Stack(
                children: [
                  Container(
                    height: 220,

                    decoration:
                        const BoxDecoration(
                          gradient:
                              LinearGradient(
                                colors: [
                                  Color(
                                    0xFF2A2E37,
                                  ),

                                  Color(
                                    0xFF17191F,
                                  ),
                                ],
                              ),
                        ),
                  ),

                  Positioned.fill(
                    child: BackdropFilter(
                      filter:
                          ImageFilter.blur(
                            sigmaX: 30,
                            sigmaY: 30,
                          ),

                      child: Container(
                        color: Colors.white
                            .withOpacity(
                              0.02,
                            ),
                      ),
                    ),
                  ),

                  const Positioned(
                    right: 24,
                    bottom: 24,

                    child: Icon(
                      Icons.arrow_outward,

                      color: Colors.white70,
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
}