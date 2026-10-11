import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/auth_state.dart';

enum _VerifyMode { signup, login }

const _codeLength = 6;

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key, required this.isSignup});

  final bool isSignup;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> with WidgetsBindingObserver {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  late final _VerifyMode _mode = widget.isSignup ? _VerifyMode.signup : _VerifyMode.login;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codeController.addListener(() => setState(() {}));
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // People leave this screen to read the code (SMS, mail, another app).
  // Android hides the keyboard while the field keeps focus; bring it back
  // on return so they can type straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _focusNode.hasFocus) _showKeyboard();
  }

  /// Focus the hidden field AND make sure the keyboard is up. requestFocus
  /// alone is a no-op when the field already has focus but the keyboard
  /// was dismissed -- which is why a single tap used to do nothing.
  void _showKeyboard() {
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _submit(AuthState authState) async {
    final code = _codeController.text.trim();
    if (code.isEmpty || authState.isLoading) return;
    final success = _mode == _VerifyMode.signup
        ? await authState.verifySignup(code)
        : await authState.verifyLogin(code);
    if (success && mounted) {
      // AuthStatus flips to authenticated and the app root (listening to
      // AuthState) swaps its home to the main shell -- but this screen was
      // pushed on top of that home, so it would stay covering the swap.
      // Pop back to the root route to reveal it.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final textTheme = Theme.of(context).textTheme;
    final code = _codeController.text;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(),
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: brandGradient(),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: -8),
                      ],
                    ),
                    child: const Icon(Icons.mark_chat_unread_rounded, color: Colors.white, size: 30),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Enter your code', style: textTheme.headlineLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'We sent a 6-digit code to ${widget.isSignup ? 'the number or email you just entered' : 'you'}. '
                  'It expires in a few minutes.',
                  style: textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted),
                ),
                if (AppConfig.demoMode) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _DemoCodeHint(),
                ],
                const SizedBox(height: AppSpacing.xl),
                // One real (invisible) field drives six display boxes, so
                // paste / SMS autofill / backspace all just work.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showKeyboard,
                  child: Stack(
                    children: [
                      // Never hit-tested itself: every tap goes to the
                      // GestureDetector above, which reliably reopens
                      // the keyboard.
                      IgnorePointer(
                        child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _codeController,
                          focusNode: _focusNode,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          maxLength: _codeLength,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (value) {
                            if (value.length == _codeLength) _submit(authState);
                          },
                          onSubmitted: (_) => _submit(authState),
                          decoration: const InputDecoration(counterText: ''),
                        ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < _codeLength; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _DigitBox(
                                digit: i < code.length ? code[i] : null,
                                active: _focusNode.hasFocus && i == code.length.clamp(0, _codeLength - 1),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (authState.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ErrorBanner(authState.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.xl),
                GradientButton(
                  label: 'Verify',
                  icon: Icons.favorite_rounded,
                  loading: authState.isLoading,
                  onPressed: code.length == _codeLength ? () => _submit(authState) : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Use a different number or email'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({required this.digit, required this.active});

  final String? digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final filled = digit != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppTheme.magenta.withValues(alpha: 0.12) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: active
              ? AppTheme.magenta
              : filled
                  ? AppTheme.magenta.withValues(alpha: 0.45)
                  : AppTheme.stroke,
          width: active ? 2 : 1,
        ),
      ),
      child: Text(
        digit ?? '',
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

/// Demo builds only: tells a tester the fixed code.
class _DemoCodeHint extends StatelessWidget {
  const _DemoCodeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: AppTheme.amber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Demo build: the code is always 000000',
              style: TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w700, color: AppTheme.amber),
            ),
          ),
        ],
      ),
    );
  }
}
