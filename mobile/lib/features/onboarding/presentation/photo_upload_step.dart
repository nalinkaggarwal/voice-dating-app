import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/onboarding_state.dart';
import 'onboarding_progress.dart';

class PhotoUploadStep extends StatefulWidget {
  const PhotoUploadStep({super.key});

  @override
  State<PhotoUploadStep> createState() => _PhotoUploadStepState();
}

class _PhotoUploadStepState extends State<PhotoUploadStep> {
  final _picker = ImagePicker();
  XFile? _picked;

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _picked = file);
  }

  Future<void> _upload(OnboardingState state) async {
    final file = _picked;
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final contentType = file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    await state.uploadPhoto(bytes, contentType: contentType);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final textTheme = Theme.of(context).textTheme;
    final picked = _picked;

    return OnboardingScaffold(
      step: onboardingStepNumber(state.currentStep),
      totalSteps: kOnboardingStepCount,
      emoji: '📸',
      title: 'Add your best photo',
      subtitle: 'Last step! Pick one that looks like you today.',
      errorMessage: state.errorMessage,
      primaryLabel: 'Finish',
      primaryIcon: Icons.auto_awesome_rounded,
      loading: state.isLoading,
      onPrimary: picked == null ? null : () => _upload(state),
      secondary: picked == null
          ? null
          : TextButton.icon(
              onPressed: state.isLoading ? null : _pickImage,
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Choose a different photo'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _pickImage,
            // Sized to the screen rather than a fixed 4:5, so the tile,
            // the privacy note and the button fit without scrolling.
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).height * 0.4).clamp(200.0, 400.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  gradient: picked == null ? null : brandGradient(),
                  color: picked == null ? AppTheme.surface1 : null,
                  border: picked == null ? Border.all(color: AppTheme.magenta.withValues(alpha: 0.4), width: 1.5) : null,
                  boxShadow: picked == null
                      ? null
                      : [BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.35), blurRadius: 30, spreadRadius: -8)],
                ),
                padding: EdgeInsets.all(picked == null ? 0 : 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xl - 3),
                  child: picked != null
                      ? Image.file(File(picked.path), fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(shape: BoxShape.circle, gradient: brandGradient()),
                              child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 32),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text('Tap to choose a photo', style: textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text('From your gallery', style: textTheme.bodySmall),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.visibility_off_rounded, color: AppTheme.coralLight),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  // Mutual Reveal happens at MUTUAL_INTEREST, before Live
                  // Snap (README WP4) -- the copy must not promise a
                  // liveness check comes first.
                  child: Text(
                    'Hidden until you and a match have both heard each other and said yes.',
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
