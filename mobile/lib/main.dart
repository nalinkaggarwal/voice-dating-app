import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/notifications/push_notifications.dart';
import 'core/splash/brand_splash.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_state.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_entry_screen.dart';
import 'features/discovery/presentation/discovery_home_screen.dart';
import 'features/onboarding/presentation/onboarding_flow_screen.dart';
import 'shared/models/user.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: every screen is designed as a tall phone layout, and
  // landscape squeezed onboarding into overflow. (Also locked natively in
  // AndroidManifest, so this needn't be awaited before the first frame.)
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Dark-only theme -> light status/nav bar icons, edge-to-edge canvas.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.ink,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Draw first: the splash must be on screen the moment the app opens.
  runApp(const LollyApp());
  // WP7: Firebase + notification channel + tap handlers, in the
  // background. Never throws -- on a build without google-services.json
  // push is simply off. Token sync awaits this same init internally.
  PushNotifications.instance.initialize();
}

class LollyApp extends StatelessWidget {
  const LollyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState(pushRegistrar: PushNotifications.instance)..bootstrap(),
      child: MaterialApp(
        title: 'Lolly.ai',
        theme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        // Lets a notification tap push a screen without a BuildContext.
        navigatorKey: PushNotifications.instance.navigatorKey,
        // The brand splash sits above the Navigator so it covers whatever
        // the auth bootstrap resolves to, then fades out of the way.
        builder: (context, child) => BrandSplash(child: child ?? const SizedBox.shrink()),
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
  AuthStatus? _lastStatus;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthState>().status;

    // This widget is the root route; screens like Discovery (pushed from
    // onboarding's last step) or OTP verify sit ON TOP of it. When auth
    // flips -- logout, or login completing -- the swap happens down here,
    // so anything stacked above must go or it hides the change ("log out
    // does nothing"). Pop back to the root on every transition.
    if (_lastStatus != null && _lastStatus != status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PushNotifications.instance.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      });
    }
    _lastStatus = status;

    if (status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (status == AuthStatus.unauthenticated) {
      // Clear the cached fetch -- otherwise a logout followed by logging
      // back in (same or different account) would reuse the PREVIOUS
      // session's already-resolved Future below and show stale user data.
      _currentUserFuture = null;
      PushNotifications.instance.detachSession();
      return const AuthEntryScreen();
    }

    // Authenticated -- fetch the user once (not on every rebuild) to know
    // which onboarding step to resume at, rather than always restarting
    // a returning user at basicInfo. The push layer learns the user id
    // from the same single fetch (a notification tap needs it to build
    // the screen it opens), outside build so it may navigate freely.
    _currentUserFuture ??= _authRepository.getCurrentUser().then((user) {
      PushNotifications.instance.attachSession(user.id);
      return user;
    });

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
        return OnboardingFlowScreen(
          resumeFrom: snapshot.data!.status,
          currentUserId: snapshot.data!.id,
          // Re-fetch the user (now ACTIVE) so this root shows Discovery
          // itself and keeps reacting to auth changes.
          onFinished: () => setState(() => _currentUserFuture = null),
        );
      },
    );
  }
}
