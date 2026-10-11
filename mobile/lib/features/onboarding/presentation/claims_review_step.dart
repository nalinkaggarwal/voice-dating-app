import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/onboarding_state.dart';
import '../domain/profile_claim.dart';
import '../domain/voice_answer.dart';
import 'onboarding_progress.dart';

class ClaimsReviewStep extends StatelessWidget {
  const ClaimsReviewStep({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final voiceAnswer = state.voiceAnswer;
    final ready = voiceAnswer != null &&
        (voiceAnswer.status == VoiceAnswerStatus.draftReady ||
            voiceAnswer.status == VoiceAnswerStatus.userApproved);

    return OnboardingScaffold(
      step: onboardingStepNumber(state.currentStep),
      totalSteps: kOnboardingStepCount,
      emoji: '✨',
      title: ready ? 'Here\'s what we heard' : 'Listening closely…',
      subtitle: ready
          ? 'Highlights from your voice intro. Fix anything that\'s off, then tap Keep on the ones you want.'
          : 'Turning your recording into a draft profile. Just a moment.',
      errorMessage: ready ? state.errorMessage : null,
      primaryLabel: ready ? 'Looks good, continue' : null,
      loading: state.isLoading,
      onPrimary: ready ? () => state.finalizeReview() : null,
      child: _buildBody(context, state, voiceAnswer),
    );
  }

  Widget _buildBody(BuildContext context, OnboardingState state, VoiceAnswer? voiceAnswer) {
    final textTheme = Theme.of(context).textTheme;
    if (voiceAnswer == null) {
      return const _Processing();
    }

    switch (voiceAnswer.status) {
      case VoiceAnswerStatus.uploaded:
      case VoiceAnswerStatus.transcribing:
      case VoiceAnswerStatus.transcribed:
      case VoiceAnswerStatus.extracting:
        return const _Processing();

      case VoiceAnswerStatus.failed:
        return GlassCard(
          child: Column(
            children: [
              const Text('😕', style: TextStyle(fontSize: 40)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                voiceAnswer.failureReason ?? 'Something went wrong processing your recording.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge,
              ),
            ],
          ),
        );

      case VoiceAnswerStatus.draftReady:
      case VoiceAnswerStatus.userApproved:
        final visibleClaims = voiceAnswer.claims.where((c) => !c.discarded).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final claim in visibleClaims) ...[
              _ClaimCard(key: ValueKey(claim.id), claim: claim, state: state),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
    }
  }
}

class _Processing extends StatelessWidget {
  const _Processing();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
      child: Column(
        children: [
          const VoiceWaveform(active: true, barCount: 15, height: 48, barWidth: 5, gap: 5, color: AppTheme.coral),
          const SizedBox(height: AppSpacing.lg),
          Text('Transcribing your voice', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          // Copy must match the extraction guardrail (README WP2): claims
          // only summarize what the user said, never infer who they are.
          Text('Pulling out the things you said', style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(minHeight: 4),
          ),
        ],
      ),
    );
  }
}

/// Small icon+label text action, tighter than a TextButton.
class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w700, fontSize: 13.5, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Keep" pill: outlined when not approved, Bloom gradient when approved.
class _ApproveToggle extends StatelessWidget {
  const _ApproveToggle({required this.approved, required this.onTap});

  final bool approved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: approved ? 'Approved' : 'Approve',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: approved ? brandGradient() : null,
            border: approved ? null : Border.all(color: const Color(0x40FFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(approved ? Icons.check_circle_rounded : Icons.check_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                approved ? 'Kept' : 'Keep',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaimCard extends StatefulWidget {
  const _ClaimCard({super.key, required this.claim, required this.state});

  final ProfileClaim claim;
  final OnboardingState state;

  @override
  State<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends State<_ClaimCard> {
  late final _controller = TextEditingController(text: widget.claim.text);
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final approved = widget.claim.approved;
    // Compact on purpose: text, then ONE slim action row (edit / remove on
    // the left, the approve toggle on the right) -- three drafts fit on
    // a phone screen without scrolling.
    return GlassCard(
      selected: approved,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.sm + 2, AppSpacing.sm),
      radius: AppRadius.lg - 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _editing
                ? TextField(
                    controller: _controller,
                    maxLines: null,
                    autofocus: true,
                    style: textTheme.bodyLarge,
                    decoration: const InputDecoration(isDense: true),
                  )
                : Text(
                    widget.claim.text,
                    style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_editing)
                _MiniAction(
                  icon: Icons.check_rounded,
                  label: 'Save',
                  color: AppTheme.coralLight,
                  onTap: () {
                    widget.state.editClaim(widget.claim.id, _controller.text.trim());
                    setState(() => _editing = false);
                  },
                )
              else
                _MiniAction(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  color: AppTheme.coralLight,
                  onTap: () => setState(() => _editing = true),
                ),
              const SizedBox(width: 4),
              _MiniAction(
                icon: Icons.close_rounded,
                label: 'Remove',
                color: AppTheme.textMuted,
                onTap: () => widget.state.discardClaim(widget.claim.id),
              ),
              const Spacer(),
              _ApproveToggle(
                approved: approved,
                onTap: () => widget.state.approveClaim(widget.claim.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
