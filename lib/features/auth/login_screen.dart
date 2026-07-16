import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Placeholder for authentication (PRD FR-001).
/// Deliberately not implemented yet — planned after the core referral
/// flow is done. Wire a real auth provider here later and add a router
/// redirect guard in core/router/app_router.dart.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            const Text('Authentication — planned, not yet implemented'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/intake'),
              child: const Text('Continue to demo'),
            ),
          ],
        ),
      ),
    );
  }
}
