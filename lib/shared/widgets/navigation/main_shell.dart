import 'package:apptest/features/map/presentation/pages/create_page.dart';
import 'package:apptest/features/map/presentation/pages/discover_page.dart';
import 'package:apptest/features/map/presentation/pages/map_page.dart';
import 'package:apptest/features/map/presentation/pages/profile_page.dart';
import 'package:apptest/features/map/providers/map_providers.dart';
import 'package:apptest/features/messaging/presentation/pages/messages_page.dart';
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
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: FloatingNavbar(
        currentIndex: index,
        onTap: (i) => ref.read(shellIndexProvider.notifier).setIndex(i),
      ),
    );
  }
}
