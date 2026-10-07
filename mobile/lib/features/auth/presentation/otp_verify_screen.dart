import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../application/auth_state.dart';

enum _VerifyMode { signup, login }

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key, required this.isSignup});

  final bool isSignup;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _codeController = TextEditingController();
  late final _VerifyMode _mode = widget.isSignup ? _VerifyMode.signup : _VerifyMode.login;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthState authState) async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    final success = _mode == _VerifyMode.signup
        ? await authState.verifySignup(code)
        : await authState.verifyLogin(code);
    if (success && mounted) {
      // AuthStatus flips to authenticated; the app root (listening to
      // AuthState) swaps to the main shell -- nothing to navigate here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.sms_rounded, color: scheme.onPrimaryContainer, size: 30),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Enter your code', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We sent a 6-digit code to ${widget.isSignup ? 'the number or email you just entered' : 'you'}. '
              'It expires in a few minutes.',
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(authState),
              style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 12, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              ),
            ),
            if (authState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(authState.errorMessage!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              style: AppTheme.accentButton(scheme),
              onPressed: authState.isLoading ? null : () => _submit(authState),
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Use a different number or email'),
            ),
          ],
        ),
      ),
    );
  }
}
