import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_state.dart';
import 'features/auth/presentation/auth_entry_screen.dart';
import 'features/onboarding/presentation/onboarding_placeholder_screen.dart';

void main() {
  runApp(const LollyApp());
}

class LollyApp extends StatelessWidget {
  const LollyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState()..bootstrap(),
      child: MaterialApp(
        title: 'Lolly.ai',
        theme: AppTheme.light,
        home: const _AppRoot(),
      ),
    );
  }
}

/// Root-level routing on auth status. WP1 keeps this simple (a single
/// switch, no named routes) -- a real router (go_router or similar) lands
/// once there's enough screen depth to justify one.
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthState>().status;
    switch (status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.authenticated:
        return const OnboardingPlaceholderScreen();
      case AuthStatus.unauthenticated:
        return const AuthEntryScreen();
    }
  }
}
