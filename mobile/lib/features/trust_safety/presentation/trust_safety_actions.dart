import 'package:flutter/material.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/trust_safety_repository.dart';
import '../domain/report_reason.dart';

/// Blocking is a meaningful, hard-to-undo action -- never a single
/// accidental tap. Shows a confirmation dialog first; only calls the
/// backend if the user confirms. Returns true if the block actually went
/// through (so the caller can navigate away / refresh), false on
/// cancel OR failure (the failure's message is shown here via a
/// SnackBar -- the caller doesn't need its own error handling for this).
Future<bool> confirmAndBlockUser(
  BuildContext context, {
  required String userId,
  TrustSafetyRepository? repository,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final error = Theme.of(dialogContext).colorScheme.error;
      return AlertDialog(
        scrollable: true,
        icon: _DialogBadge(icon: Icons.block_rounded, color: error),
        title: const Text('Block this person?', textAlign: TextAlign.center),
        content: const Text(
          "They won't be able to message you, start a Live Snap call, or see your profile again. This can't be undone from here.",
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 48),
              backgroundColor: error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await (repository ?? TrustSafetyRepository()).blockUser(userId);
    return true;
  } on AppException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

/// Reporting a profile, a message, or a Live Snap session -- independent
/// of blocking (see TrustSafetyRepository's own note). Shows a reason
/// picker + optional free-text details, then submits. Returns true on a
/// successful submission.
Future<bool> showReportDialog(
  BuildContext context, {
  required String reportedUserId,
  required ReportContext reportContext,
  String? contextId,
  TrustSafetyRepository? repository,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ReportDialog(
      reportedUserId: reportedUserId,
      reportContext: reportContext,
      contextId: contextId,
      repository: repository,
    ),
  );
  return result ?? false;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.reportedUserId,
    required this.reportContext,
    required this.contextId,
    required this.repository,
  });

  final String reportedUserId;
  final ReportContext reportContext;
  final String? contextId;
  final TrustSafetyRepository? repository;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason _reason = ReportReason.inappropriateContent;
  final _detailsController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await (widget.repository ?? TrustSafetyRepository()).reportUser(
        reportedUserId: widget.reportedUserId,
        reason: _reason,
        context: widget.reportContext,
        contextId: widget.contextId,
        details: _detailsController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      // Scrollable so the keyboard (details field) can never push the
      // dialog into an overflow.
      scrollable: true,
      icon: const _DialogBadge(icon: Icons.flag_rounded, color: AppTheme.coral),
      title: const Text('Report', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reason', style: textTheme.titleSmall?.copyWith(color: AppTheme.textMuted)),
          const SizedBox(height: AppSpacing.sm + 2),
          // Same single-choice reason picker as before, as pills.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final reason in ReportReason.values)
                ChoicePill(
                  label: reason.label,
                  selected: reason == _reason,
                  onTap: _isSubmitting ? () {} : () => setState(() => _reason = reason),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _detailsController,
            enabled: !_isSubmitting,
            maxLines: 3,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Details (optional)', alignLabelWithHint: true),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ErrorBanner(_errorMessage!),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: AppTheme.accentButton(Theme.of(context).colorScheme).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(120, 48)),
          ),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}

/// Round tinted icon heading a safety dialog.
class _DialogBadge extends StatelessWidget {
  const _DialogBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
