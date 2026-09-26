import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/onboarding_state.dart';
import '../domain/profile_claim.dart';
import '../domain/voice_answer.dart';

class ClaimsReviewStep extends StatelessWidget {
  const ClaimsReviewStep({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final voiceAnswer = state.voiceAnswer;

    return Scaffold(
      appBar: AppBar(title: const Text('Review your profile')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(context, state, voiceAnswer),
      ),
    );
  }

  Widget _buildBody(BuildContext context, OnboardingState state, VoiceAnswer? voiceAnswer) {
    if (voiceAnswer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (voiceAnswer.status) {
      case VoiceAnswerStatus.uploaded:
      case VoiceAnswerStatus.transcribing:
      case VoiceAnswerStatus.transcribed:
      case VoiceAnswerStatus.extracting:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("We're turning your recording into a draft profile..."),
            ],
          ),
        );

      case VoiceAnswerStatus.failed:
        return Center(
          child: Text(
            voiceAnswer.failureReason ?? 'Something went wrong processing your recording.',
            textAlign: TextAlign.center,
          ),
        );

      case VoiceAnswerStatus.draftReady:
      case VoiceAnswerStatus.userApproved:
        final visibleClaims = voiceAnswer.claims.where((c) => !c.discarded).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Edit or remove anything that\'s not quite right, then approve what you want to keep.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: visibleClaims.length,
                itemBuilder: (context, index) =>
                    _ClaimCard(claim: visibleClaims[index], state: state),
              ),
            ),
            if (state.errorMessage != null) ...[
              Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: state.isLoading ? null : () => state.finalizeReview(),
              child: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Looks good, continue'),
            ),
          ],
        );
    }
  }
}

class _ClaimCard extends StatefulWidget {
  const _ClaimCard({required this.claim, required this.state});

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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: widget.claim.approved ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _editing
                ? TextField(controller: _controller, maxLines: null)
                : Text(widget.claim.text),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_editing)
                  TextButton(
                    onPressed: () {
                      widget.state.editClaim(widget.claim.id, _controller.text.trim());
                      setState(() => _editing = false);
                    },
                    child: const Text('Save'),
                  )
                else
                  TextButton(
                    onPressed: () => setState(() => _editing = true),
                    child: const Text('Edit'),
                  ),
                TextButton(
                  onPressed: () => widget.state.discardClaim(widget.claim.id),
                  child: const Text('Discard'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => widget.state.approveClaim(widget.claim.id),
                  icon: Icon(
                    widget.claim.approved ? Icons.check_circle : Icons.check_circle_outline,
                    color: widget.claim.approved ? Colors.green : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
