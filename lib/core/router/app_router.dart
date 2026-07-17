import 'package:flutter/material.dart';
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
import '../../features/patients/add_patient_screen.dart';
import '../../features/patients/patient_encounter_input_screen.dart';
import '../../features/patients/patient_directory_screen.dart';
import '../../features/patients/patient_overview_screen.dart';
import '../../features/pasien_portal/pasien_home_screen.dart';
import '../../features/pasien_portal/pasien_monitoring_screen.dart';
import '../../features/pasien_portal/pasien_profile_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/receiving/receiving_facility_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/timeline/timeline_screen.dart';
import '../../models/app_profile.dart';
import '../../models/referral.dart';
import '../../state/auth_state.dart';
import '../../state/referral_state.dart';

const _legacyBidanRoutes = {
  '/home': '/bidan/home',
  '/intake': '/bidan/patients',
  '/facility-match': '/bidan/referral/facility-match',
  '/receiving': '/bidan/referral/response',
  '/timeline': '/bidan/referral/timeline',
  '/patients': '/bidan/patients',
  '/patients/add': '/bidan/patients/add',
  '/referral/intake': '/bidan/patients',
  '/referral/facility-match': '/bidan/referral/facility-match',
  '/referral/receiving': '/bidan/referral/response',
  '/referral/timeline': '/bidan/referral/timeline',
};

GoRouter createRouter(AppAuthState auth, {ReferralState? referralState}) =>
    GoRouter(
      initialLocation: '/bidan/home',
      refreshListenable: referralState == null
          ? auth
          : Listenable.merge([auth, referralState]),
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

        if (role == AppRole.bidan && location == '/bidan/referral/response') {
          final referralStep = referralState?.referral.step;
          if (referralStep == ReferralStep.accepted) {
            return '/bidan/referral/timeline';
          }
          if (referralStep == ReferralStep.arrived) {
            return '/bidan/home';
          }
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
                GoRoute(
                  path: '/bidan/home',
                  builder: (_, _) => const HomeScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/bidan/patients',
                  builder: (_, _) => const PatientDirectoryScreen(),
                  routes: [
                    GoRoute(
                      path: 'add',
                      builder: (_, _) => const AddPatientScreen(),
                    ),
                    GoRoute(
                      path: ':id/encounter',
                      builder: (_, state) => PatientEncounterInputScreen(
                        patientId: state.pathParameters['id']!,
                      ),
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
        GoRoute(
          path: '/bidan/referral/intake',
          redirect: (_, _) => '/bidan/patients',
        ),
        GoRoute(
          path: '/bidan/referral/facility-match',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: FacilityMatchScreen()),
        ),
        GoRoute(
          path: '/bidan/referral/response',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: ReceivingFacilityScreen()),
        ),
        GoRoute(
          path: '/bidan/referral/timeline',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: TimelineScreen()),
        ),
        GoRoute(
          path: '/bidan/documentation',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: NarrativeInputScreen()),
        ),
        GoRoute(
          path: '/bidan/documentation/review',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: SoapReviewScreen()),
        ),
        GoRoute(
          path: '/bidan/documentation/handoff',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: HandoffPreviewScreen()),
        ),
        GoRoute(
          path: '/bidan/documentation/family',
          builder: (_, _) =>
              const _StandaloneBidanRoute(child: FamilyInstructionScreen()),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/access-error',
          builder: (_, _) => const AccessConfigurationScreen(),
        ),
      ],
    );

class _StandaloneBidanRoute extends StatelessWidget {
  const _StandaloneBidanRoute({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child,
          ),
        ),
      ),
    );
  }
}
