import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Lolly.ai')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Sign up')),
                ButtonSegment(value: false, label: Text('Log in')),
              ],
              selected: {_isSignup},
              onSelectionChanged: (s) => setState(() => _isSignup = s.first),
            ),
            const SizedBox(height: 16),
            SegmentedButton<AuthChannel>(
              segments: const [
                ButtonSegment(value: AuthChannel.phone, label: Text('Phone')),
                ButtonSegment(value: AuthChannel.email, label: Text('Email')),
              ],
              selected: {_channel},
              onSelectionChanged: (s) => setState(() => _channel = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _identifierController,
              keyboardType: _channel == AuthChannel.email
                  ? TextInputType.emailAddress
                  : TextInputType.phone,
              decoration: InputDecoration(
                labelText: _channel == AuthChannel.email ? 'Email' : 'Phone (e.g. +14155552671)',
              ),
            ),
            if (_isSignup) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _pickDateOfBirth,
                child: Text(
                  _dateOfBirth == null
                      ? 'Select date of birth'
                      : 'DOB: ${_dateOfBirth!.toIso8601String().split('T').first}',
                ),
              ),
            ],
            if (authState.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(authState.errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: authState.isLoading ? null : () => _submit(authState),
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isSignup ? 'Send code' : 'Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
