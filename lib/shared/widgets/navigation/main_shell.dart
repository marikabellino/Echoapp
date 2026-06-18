import 'package:apptest/features/map/presentation/pages/create_page.dart';
import 'package:apptest/features/map/presentation/pages/discover_page.dart';
import 'package:apptest/features/map/presentation/pages/map_page.dart';
import 'package:apptest/features/map/presentation/pages/profile_page.dart';
import 'package:apptest/features/map/providers/map_providers.dart';
import 'package:apptest/features/messaging/presentation/pages/messages_page.dart';
import 'package:apptest/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:apptest/features/notifications/providers/notification_provider.dart';
import 'package:apptest/features/onboarding/providers/onboarding_provider.dart';
import 'package:apptest/shared/widgets/navigation/floating_navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _pages = [
    DiscoverPage(),
    MapPage(),
    CreatePage(),
    MessagesPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    final seenAsync = ref.watch(onboardingProvider);
    // Inizializza il NotificationService non appena l'utente è autenticato
    ref.watch(notificationsProvider);
    final seen = seenAsync.asData?.value;

    return Stack(
      children: [
        Scaffold(
          extendBody: true,
          body: IndexedStack(index: index, children: _pages),
          bottomNavigationBar: FloatingNavbar(
            currentIndex: index,
            onTap: (i) => ref.read(shellIndexProvider.notifier).setIndex(i),
          ),
        ),
        if (seen == false)
          Material(
            type: MaterialType.transparency,
            child: OnboardingPage(
              onDone: () =>
                  ref.read(onboardingProvider.notifier).markSeen(),
            ),
          ),
      ],
    );
  }
}
