import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'auth_controller.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Email/password + Google sign-in (CLAUDE.md §23 — Google + email first).
/// Reached from Profile; pops back on success. Not a hard gate — the first
/// try-on isn't blocked behind sign-up (§17).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();

    if (_isSignUp) {
      final result = await controller.signUpEmail(email, _password.text);
      if (!mounted) return;
      switch (result) {
        case SignUpResult.signedIn:
          Navigator.of(context).pop();
        case SignUpResult.needsConfirmation:
          _snack(l10n.authCheckEmail); // account made; confirm before sign-in
        case SignUpResult.failed:
          break; // error is shown from the controller state
      }
    } else {
      final ok = await controller.signInEmail(email, _password.text);
      if (ok && mounted) Navigator.of(context).pop();
    }
  }

  /// Switch sign-in ↔ sign-up: clear the password and any stale error so the two
  /// forms don't share leftover state.
  void _toggleMode() {
    _password.clear();
    ref.read(authControllerProvider.notifier).clear();
    setState(() => _isSignUp = !_isSignUp);
  }

  Future<void> _google() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle();
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(authControllerProvider);
    final loading = state.isLoading;
    final error = state.hasError ? state.error.toString() : null;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isSignUp ? l10n.authSignUpTitle : l10n.authSignInTitle,
                  style: text.displaySmall,
                ),
                const SizedBox(height: AppSpace.xl),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: l10n.authEmail,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => _emailRe.hasMatch(v?.trim() ?? '')
                      ? null
                      : l10n.authEmailInvalid,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: l10n.authPassword,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').length >= 8 ? null : l10n.authPasswordTooShort,
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Text(
                    error,
                    style: text.bodySmall?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpace.lg),
                PrimaryButton(
                  label: _isSignUp ? l10n.authSignUp : l10n.authSignIn,
                  isLoading: loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  onPressed: loading ? null : _google,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(l10n.authGoogle),
                ),
                const SizedBox(height: AppSpace.sm),
                TextButton(
                  onPressed: loading ? null : _toggleMode,
                  child: Text(
                    _isSignUp
                        ? l10n.authToggleToSignIn
                        : l10n.authToggleToSignUp,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
