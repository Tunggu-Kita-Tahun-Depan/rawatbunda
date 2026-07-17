import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/facility_match/facility_match_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/intake/intake_screen.dart';
import '../../features/patients/add_patient_screen.dart';
import '../../features/patients/patient_directory_screen.dart';
import '../../features/patients/patient_overview_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/receiving/receiving_facility_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../state/auth_state.dart';

GoRouter createRouter(AppAuthState auth) => GoRouter(
  initialLocation: '/home',
  refreshListenable: auth,
  redirect: (context, state) {
    if (!auth.authEnabled) return null;
    final loggingIn = state.matchedLocation == '/login';
    if (!auth.isSignedIn) return loggingIn ? null : '/login';
    if (loggingIn) return '/home';
    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/patients',
              builder: (_, _) => const PatientDirectoryScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (_, _) => const AddPatientScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (_, state) => PatientOverviewScreen(
                    patientId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/referral/intake',
          routes: [
            GoRoute(
              path: '/referral/intake',
              builder: (_, _) => const IntakeScreen(),
            ),
            GoRoute(
              path: '/referral/facility-match',
              builder: (_, _) => const FacilityMatchScreen(),
            ),
            GoRoute(
              path: '/referral/receiving',
              builder: (_, _) => const ReceivingFacilityScreen(),
            ),
            GoRoute(
              path: '/referral/timeline',
              builder: (_, _) => const TimelineScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ],
        ),
      ],
    ),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
    // Keep old demo links working after the navigation restructure.
    GoRoute(path: '/intake', redirect: (_, _) => '/referral/intake'),
    GoRoute(
      path: '/facility-match',
      redirect: (_, _) => '/referral/facility-match',
    ),
    GoRoute(path: '/receiving', redirect: (_, _) => '/referral/receiving'),
    GoRoute(path: '/timeline', redirect: (_, _) => '/referral/timeline'),
  ],
);
