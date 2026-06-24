import 'package:echo/features/map/presentation/pages/create_page.dart';
import 'package:echo/features/map/presentation/pages/discover_page.dart';
import 'package:echo/features/map/presentation/pages/map_page.dart';
import 'package:echo/features/map/presentation/pages/profile_page.dart';
import 'package:echo/features/map/providers/map_providers.dart';
import 'package:echo/features/messaging/presentation/pages/messages_page.dart';
import 'package:echo/features/notifications/domain/models/notification_model.dart';
import 'package:echo/features/notifications/providers/notification_provider.dart';
import 'package:echo/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:echo/features/onboarding/providers/onboarding_provider.dart';
import 'package:echo/shared/widgets/echo_toast.dart';
import 'package:echo/shared/widgets/navigation/floating_navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late PageController _pageController;

  static const _pages = [
    DiscoverPage(),
    MapPage(),
    CreatePage(),
    MessagesPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    final current = ref.read(shellIndexProvider);
    if (i == current) return;
    ref.read(shellIndexProvider.notifier).setIndex(i);
    ref.read(scrollOffsetProvider.notifier).reset();
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellIndexProvider);
    final seenAsync = ref.watch(onboardingProvider);
    final seen = seenAsync.asData?.value;

    ref.listen<int>(shellIndexProvider, (prev, next) {
      if (_pageController.hasClients &&
          _pageController.page?.round() != next) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      }
    });

    ref.watch(notificationsProvider);

    ref.listen<List<AppNotification>>(notificationsProvider, (prev, next) {
      if (!mounted) return;
      if (next.length > (prev?.length ?? 0)) {
        final n = next.first;
        final toastMsg = n.type == NotificationType.message
            ? '${n.title}: ${n.body}'
            : n.title;
        EchoToast.show(context, toastMsg, type: _toastType(n.type));
      }
    });

    return Stack(
      children: [
        Scaffold(
          extendBody: true,
          body: MediaQuery(
            // Strip the navbar height from padding.bottom so inner pages'
            // SafeArea only reserves the physical system inset, not the full
            // navbar slot — otherwise a blank background band appears below
            // the content and around the pill.
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.of(context).padding.copyWith(
                bottom: MediaQuery.of(context).viewPadding.bottom,
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification &&
                    n.metrics.axis == Axis.vertical) {
                  ref
                      .read(scrollOffsetProvider.notifier)
                      .updateOffset(n.metrics.pixels);
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) {
                  ref.read(shellIndexProvider.notifier).setIndex(i);
                  ref.read(scrollOffsetProvider.notifier).reset();
                },
                itemCount: _pages.length,
                itemBuilder: (_, i) => _KeepAlivePage(child: _pages[i]),
              ),
            ),
          ),
          bottomNavigationBar: FloatingNavbar(
            currentIndex: index,
            onTap: _goTo,
            onSwipedLeft: index < _pages.length - 1 ? () => _goTo(index + 1) : null,
            onSwipedRight: index > 0 ? () => _goTo(index - 1) : null,
          ),
        ),

        if (seen == false)
          Material(
            type: MaterialType.transparency,
            child: OnboardingPage(
              onDone: () => ref.read(onboardingProvider.notifier).markSeen(),
            ),
          ),

       
      ],
    );
  }

  EchoToastType _toastType(NotificationType type) => switch (type) {
        NotificationType.like => EchoToastType.success,
        NotificationType.connectionRequest => EchoToastType.info,
        NotificationType.proximity => EchoToastType.info,
        NotificationType.message => EchoToastType.info,
      };
}

/// Keeps a page alive in [PageView] so state isn't lost when swiping away.
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
