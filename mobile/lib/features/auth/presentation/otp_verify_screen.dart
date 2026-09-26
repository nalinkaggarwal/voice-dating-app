import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Enter your code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('We sent you a 6-digit code. It expires in a few minutes.'),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            if (authState.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(authState.errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: authState.isLoading ? null : () => _submit(authState),
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
