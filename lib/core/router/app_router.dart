import 'package:go_router/go_router.dart';

import '../../features/admin/admin_facilities_screen.dart';
import '../../features/auth/access_configuration_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/documentation/family_instruction_screen.dart';
import '../../features/documentation/handoff_preview_screen.dart';
import '../../features/documentation/narrative_input_screen.dart';
import '../../features/documentation/soap_review_screen.dart';
import '../../features/facility_match/facility_match_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/intake/intake_screen.dart';
import '../../features/pasien_portal/pasien_home_screen.dart';
import '../../features/pasien_portal/pasien_monitoring_screen.dart';
import '../../features/pasien_portal/pasien_profile_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/receiving/receiving_facility_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../models/app_profile.dart';
import '../../state/auth_state.dart';

const _legacyBidanRoutes = {
  '/home': '/bidan/home',
  '/intake': '/bidan/referral/intake',
  '/facility-match': '/bidan/referral/facility-match',
  '/receiving': '/bidan/referral/response',
  '/timeline': '/bidan/referral/timeline',
  '/referral/intake': '/bidan/referral/intake',
  '/referral/facility-match': '/bidan/referral/facility-match',
  '/referral/receiving': '/bidan/referral/response',
  '/referral/timeline': '/bidan/referral/timeline',
};

GoRouter createRouter(AppAuthState auth) => GoRouter(
  initialLocation: '/bidan/home',
  refreshListenable: auth,
  redirect: (context, state) {
    final location = state.matchedLocation;
    final loggingIn = location == '/login';

    if (auth.authEnabled && !auth.isSignedIn) {
      return loggingIn ? null : '/login';
    }

    final role = auth.role;
    if (role == null) {
      return location == '/access-error' ? null : '/access-error';
    }

    if (loggingIn || location == '/access-error' || location == '/') {
      return role.homeLocation;
    }

    final legacyTarget = _legacyBidanRoutes[location];
    if (legacyTarget != null) {
      return role == AppRole.bidan ? legacyTarget : role.homeLocation;
    }

    if (!location.startsWith('/${role.name}/')) {
      return role.homeLocation;
    }

    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, role: AppRole.bidan),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/bidan/home', builder: (_, _) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/bidan/referral/intake',
          routes: [
            GoRoute(
              path: '/bidan/referral/intake',
              builder: (_, _) => const IntakeScreen(),
            ),
            GoRoute(
              path: '/bidan/referral/facility-match',
              builder: (_, _) => const FacilityMatchScreen(),
            ),
            GoRoute(
              path: '/bidan/referral/response',
              builder: (_, _) => const ReceivingFacilityScreen(),
            ),
            GoRoute(
              path: '/bidan/referral/timeline',
              builder: (_, _) => const TimelineScreen(),
            ),
            GoRoute(
              path: '/bidan/documentation',
              builder: (_, _) => const NarrativeInputScreen(),
            ),
            GoRoute(
              path: '/bidan/documentation/review',
              builder: (_, _) => const SoapReviewScreen(),
            ),
            GoRoute(
              path: '/bidan/documentation/handoff',
              builder: (_, _) => const HandoffPreviewScreen(),
            ),
            GoRoute(
              path: '/bidan/documentation/family',
              builder: (_, _) => const FamilyInstructionScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/bidan/profile',
              builder: (_, _) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, role: AppRole.pasien),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/pasien/home',
              builder: (_, _) => const PasienHomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/pasien/monitoring',
              builder: (_, _) => const PasienMonitoringScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/pasien/profile',
              builder: (_, _) => const PasienProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, role: AppRole.admin),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/facilities',
              builder: (_, _) => const AdminFacilitiesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/admin/profile',
              builder: (_, _) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(
      path: '/access-error',
      builder: (_, _) => const AccessConfigurationScreen(),
    ),
  ],
);
