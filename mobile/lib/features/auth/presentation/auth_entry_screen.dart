import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/segmented_pill.dart';
import '../application/auth_state.dart';
import '../domain/auth_channel.dart';
import 'otp_verify_screen.dart';

class AuthEntryScreen extends StatefulWidget {
  const AuthEntryScreen({super.key});

  @override
  State<AuthEntryScreen> createState() => _AuthEntryScreenState();
}

class _AuthEntryScreenState extends State<AuthEntryScreen> {
  bool _isSignup = true;
  AuthChannel _channel = AuthChannel.phone;
  final _identifierController = TextEditingController();
  DateTime? _dateOfBirth;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _submit(AuthState authState) async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) return;

    final bool success;
    if (_isSignup) {
      if (_dateOfBirth == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your date of birth')),
        );
        return;
      }
      success = await authState.startSignup(
        channel: _channel,
        identifier: identifier,
        dateOfBirth: _dateOfBirth!,
      );
    } else {
      success = await authState.startLogin(channel: _channel, identifier: identifier);
    }

    if (success && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtpVerifyScreen(isSignup: _isSignup)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEmail = _channel == AuthChannel.email;

    return Scaffold(
      body: Column(
        children: [
          const _AuthHero(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedPill<bool>(
                    values: const [true, false],
                    labels: const ['Sign up', 'Log in'],
                    selected: _isSignup,
                    onChanged: (v) => setState(() => _isSignup = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedPill<AuthChannel>(
                    values: const [AuthChannel.phone, AuthChannel.email],
                    labels: const ['Phone', 'Email'],
                    selected: _channel,
                    onChanged: (v) => setState(() => _channel = v),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _identifierController,
                    keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(authState),
                    decoration: InputDecoration(
                      labelText: isEmail ? 'Email' : 'Phone number',
                      hintText: isEmail ? 'you@example.com' : '+14155552671',
                      prefixIcon: Icon(isEmail ? Icons.mail_outline_rounded : Icons.phone_iphone_rounded),
                    ),
                  ),
                  if (_isSignup) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _pickDateOfBirth,
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(
                        _dateOfBirth == null
                            ? 'Date of birth'
                            : 'Born ${_dateOfBirth!.toIso8601String().split('T').first}',
                      ),
                    ),
                  ],
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
                        : Text(_isSignup ? 'Send my code' : 'Log in'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No passwords. We send a one-time code to your ${isEmail ? 'inbox' : 'phone'}.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand header: mark, wordmark, the motto. Same gradient as the splash so
/// the hand-over from splash to this screen feels like one surface.
class _AuthHero extends StatelessWidget {
  const _AuthHero();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: brandGradient(),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LollyMark(size: 56, style: LollyMarkStyle.onGradient),
              const SizedBox(height: AppSpacing.md),
              const AppWordmark(fontSize: 36, color: Colors.white, accentColor: AppTheme.peach),
              const SizedBox(height: AppSpacing.xs),
              Text(
                kAppTagline,
                style: textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Voice first. Photos come later, once you both say yes.',
                style: textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
