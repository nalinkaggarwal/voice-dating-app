import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/segmented_pill.dart';
import '../../../shared/widgets/ui_kit.dart';
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

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Date of birth',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
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
    final textTheme = Theme.of(context).textTheme;
    final isEmail = _channel == AuthChannel.email;
    final dob = _dateOfBirth;

    final compact = isCompactHeight(context);

    final topPad = compact ? AppSpacing.md : AppSpacing.lg;
    const bottomPad = AppSpacing.md;

    // Fills the whole screen: brand header at the top, the "no passwords"
    // footer at the bottom, and the form centred between them (equal
    // flexible space above and below) -- so neither mode (log in has one
    // field fewer) leaves a lopsided gap. On a short screen / with the
    // keyboard up the gaps collapse and FadingScrollView takes over
    // (fades + hint instead of cutting off).
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: AuroraBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => FadingScrollView(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, topPad, AppSpacing.lg, bottomPad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - topPad - bottomPad),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AuthHero(compact: compact),
                      SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                      const Spacer(),
                      GlassCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
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
                            Row(
                              children: [
                                _ChannelTab(
                                  icon: Icons.phone_iphone_rounded,
                                  label: 'Phone',
                                  selected: !isEmail,
                                  onTap: () => setState(() => _channel = AuthChannel.phone),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                _ChannelTab(
                                  icon: Icons.alternate_email_rounded,
                                  label: 'Email',
                                  selected: isEmail,
                                  onTap: () => setState(() => _channel = AuthChannel.email),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm + 4),
                            TextField(
                              controller: _identifierController,
                              keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(authState),
                              style: textTheme.titleMedium,
                              decoration: InputDecoration(
                                labelText: isEmail ? 'Email' : 'Phone number',
                                hintText: isEmail ? 'you@example.com' : '+91 98765 43210',
                                prefixIcon: Icon(isEmail ? Icons.mail_outline_rounded : Icons.phone_iphone_rounded),
                              ),
                            ),
                            // Same timing as the Sign up / Log in slide, so the
                            // switch reads as one motion.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              child: _isSignup
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: AppSpacing.sm + 4),
                                      child: _DobField(
                                        text: dob == null ? null : '${dob.day} ${_months[dob.month - 1]} ${dob.year}',
                                        onTap: _pickDateOfBirth,
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                            if (authState.errorMessage != null) ...[
                              const SizedBox(height: AppSpacing.sm + 4),
                              ErrorBanner(authState.errorMessage!),
                            ],
                            const SizedBox(height: AppSpacing.md + 4),
                            GradientButton(
                              label: _isSignup ? 'Send my code' : 'Log in',
                              icon: Icons.arrow_forward_rounded,
                              loading: authState.isLoading,
                              height: compact ? 52 : 56,
                              onPressed: () => _submit(authState),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                      const Spacer(),
                      // Icon inline with the text, so it stays beside the first
                      // word however the centred line wraps.
                      Text.rich(
                        TextSpan(
                          children: [
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.textMuted),
                              ),
                            ),
                            TextSpan(
                                text: 'No passwords. We send a one-time code to your ${isEmail ? 'inbox' : 'phone'}.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand header: glowing mark beside the wordmark (one row, to keep the
/// page scroll-free), then the motto and the promise.
class _AuthHero extends StatelessWidget {
  const _AuthHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.55), blurRadius: 30, spreadRadius: -4),
                ],
              ),
              child: LollyMark(
                size: compact ? 40 : 46,
                style: LollyMarkStyle.onGradient,
                withBackground: true,
                inset: 0.12,
              ),
            ),
            const SizedBox(width: 12),
            const AppWordmark(fontSize: 24, color: AppTheme.textPrimary, accentColor: AppTheme.coralLight),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFFFD1E6)],
          ).createShader(bounds),
          child: Text(
            kAppTagline,
            style: textTheme.displaySmall?.copyWith(fontSize: compact ? 30 : 36, color: Colors.white),
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Row(
          children: [
            const VoiceWaveform(active: true, barCount: 5, height: 16, barWidth: 3, gap: 3, color: AppTheme.coral),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Text(
                'Voice first. Photos come later, once you both say yes.',
                style: textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChannelTab extends StatelessWidget {
  const _ChannelTab({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: selected ? AppTheme.magenta.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: selected ? AppTheme.magenta.withValues(alpha: 0.7) : AppTheme.stroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? const Color(0xFFFF8AC2) : AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date of birth, styled as an input field that opens the date picker.
class _DobField extends StatelessWidget {
  const _DobField({required this.text, required this.onTap});

  final String? text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppTheme.surface2,
      borderRadius: BorderRadius.circular(AppRadius.md + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        // A tap target, not a focusable field: otherwise focus returns
        // here when the date picker closes and the grey focus highlight
        // sticks.
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 18),
          child: Row(
            children: [
              const Icon(Icons.cake_outlined, color: AppTheme.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text ?? 'Date of birth',
                  style:
                      text == null ? textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted) : textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.calendar_month_rounded, color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
