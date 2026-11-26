import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/karen_models.dart';
import '../../features/home/home_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/schedules/schedules_screen.dart';
import '../../features/security/pin_lock_screen.dart';
import '../../features/settings/protocol_templates_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/users/authorized_users_screen.dart';
import '../providers/karen_providers.dart';

class _RouterLockRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterLockRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);

  ref.listen<bool>(
    karenControllerProvider.select((s) => s.requiresUnlock),
    (_, __) => refreshNotifier.refresh(),
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final requiresUnlock = ref.read(karenControllerProvider).requiresUnlock;
      final location = state.matchedLocation;

      // Allow splash to play briefly; every other route is strictly gated by PIN lock.
      if (requiresUnlock && location != '/lock' && location != '/splash') {
        return '/lock';
      }
      if (!requiresUnlock && location == '/lock') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/lock',
        builder: (_, __) => const PinLockScreen(),
      ),
      GoRoute(
        path: '/users/admin',
        builder: (_, __) => const AuthorizedUsersScreen(
          initialRole: DeviceUserRole.admin,
        ),
      ),
      GoRoute(
        path: '/users/member',
        builder: (_, __) => const AuthorizedUsersScreen(
          initialRole: DeviceUserRole.user,
        ),
      ),
      GoRoute(
        path: '/protocol-templates',
        builder: (_, __) => const ProtocolTemplatesScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _KarenShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedules',
                builder: (_, __) => const SchedulesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (_, __) => const ReportsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _KarenShellScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _KarenShellScaffold({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'صفحه اصلی',
          ),
          NavigationDestination(
            icon: Icon(Icons.upload_outlined),
            selectedIcon: Icon(Icons.upload_rounded),
            label: 'بارگذاری روزها',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: 'گزارشگیری',
          ),
        ],
      ),
    );
  }
}
