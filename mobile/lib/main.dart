import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_state.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_entry_screen.dart';
import 'features/discovery/presentation/discovery_home_screen.dart';
import 'features/onboarding/presentation/onboarding_flow_screen.dart';
import 'shared/models/user.dart';

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
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  final _authRepository = AuthRepository();
  Future<User>? _currentUserFuture;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthState>().status;

    if (status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (status == AuthStatus.unauthenticated) {
      // Clear the cached fetch -- otherwise a logout followed by logging
      // back in (same or different account) would reuse the PREVIOUS
      // session's already-resolved Future below and show stale user data.
      _currentUserFuture = null;
      return const AuthEntryScreen();
    }

    // Authenticated -- fetch the user once (not on every rebuild) to know
    // which onboarding step to resume at, rather than always restarting
    // a returning user at basicInfo.
    _currentUserFuture ??= _authRepository.getCurrentUser();

    return FutureBuilder<User>(
      future: _currentUserFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // A returning ACTIVE user (fresh app launch/login, onboarding
        // already fully done in a previous session) goes straight to
        // Discovery -- OnboardingFlowScreen's own resumeFrom mapping only
        // matters for a user still mid-onboarding.
        if (snapshot.data!.status == UserStatus.active) {
          return DiscoveryHomeScreen(currentUserId: snapshot.data!.id);
        }
        return OnboardingFlowScreen(resumeFrom: snapshot.data!.status, currentUserId: snapshot.data!.id);
      },
    );
  }
}
