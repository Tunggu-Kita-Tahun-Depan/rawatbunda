import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/facility_match/facility_match_screen.dart';
import '../../features/intake/intake_screen.dart';
import '../../features/receiving/receiving_facility_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../state/auth_state.dart';

GoRouter createRouter(AppAuthState auth) => GoRouter(
      initialLocation: '/intake',
      refreshListenable: auth,
      redirect: (context, state) {
        if (!auth.authEnabled) return null; // in-memory demo mode: no login
        final loggingIn = state.matchedLocation == '/login';
        if (!auth.isSignedIn) return loggingIn ? null : '/login';
        if (loggingIn) return '/intake';
        return null;
      },
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/intake', builder: (_, _) => const IntakeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/facility-match', builder: (_, _) => const FacilityMatchScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/receiving', builder: (_, _) => const ReceivingFacilityScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/timeline', builder: (_, _) => const TimelineScreen()),
            ]),
          ],
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        // Future scope (stub).
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
      ],
    );
