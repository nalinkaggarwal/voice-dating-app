import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../application/onboarding_state.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Add a photo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "This won't be visible to anyone until you both express interest and pass a "
              'quick liveness check.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_picked != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_picked!.path), height: 240, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _pickImage, child: const Text('Choose a photo')),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _picked == null || state.isLoading ? null : () => _upload(state),
              child: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Finish'),
            ),
          ],
        ),
      ),
    );
  }
}
