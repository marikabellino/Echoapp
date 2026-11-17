import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/legal/legal_texts.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';

enum LegalDocument {
  privacy('Informativa privacy', privacySections),
  terms('Termini di servizio', termsSections),
  guidelines('Regole della community', guidelinesSections);

  const LegalDocument(this.title, this.sections);
  final String title;
  final List<LegalSection> sections;
}

void openLegal(BuildContext context, LegalDocument doc) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => LegalPage(document: doc)));
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.document});
  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, top + 8, 20, 8),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Text(
                document.title,
                style: AppTextStyles.displayLarge(
                  context,
                ).copyWith(fontSize: 30),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: document.sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: 22),
            itemBuilder: (context, i) {
              final s = document.sections[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      style: AppTextStyles.headline(
                        context,
                      ).copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.body,
                      style: AppTextStyles.body(context).copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SliverToBoxAdapter(child: SizedBox(height: bottom + 40)),
        ],
      ),
    );
  }
}
