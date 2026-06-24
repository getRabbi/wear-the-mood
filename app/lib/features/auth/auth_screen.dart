import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'auth_controller.dart';
import 'auth_error.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Email/password + Google sign-in (CLAUDE.md §23 — Google + email first).
/// Opened from the welcome gate (§11) — [initialSignUp] pre-selects sign-up when
/// reached via "Create account". Pops back on success (the auth-state listener
/// in FashionOsApp closes it once the session is active).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.initialSignUp = false});

  /// Start on the sign-up tab instead of sign-in.
  final bool initialSignUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late bool _isSignUp = widget.initialSignUp;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
          break; // the auth-state listener closes this screen once active
        case SignUpResult.needsConfirmation:
          _snack(l10n.authCheckEmail); // account made; confirm before sign-in
        case SignUpResult.alreadyRegistered:
          _snack(l10n.authErrorEmailRegistered);
          _setMode(false); // flip to sign-in so they can just log in
        case SignUpResult.failed:
          break; // the mapped error is shown from the controller state
      }
    } else {
      // On success the auth stream emits `signedIn`, which closes this screen
      // (see FashionOsApp); errors surface from the controller state.
      await controller.signInEmail(email, _password.text);
    }
  }

  /// Switch sign-in ↔ sign-up: clear the password and any stale error so the two
  /// forms don't share leftover state.
  void _setMode(bool signUp) {
    if (signUp == _isSignUp) return;
    _password.clear();
    _confirmPassword.clear();
    ref.read(authControllerProvider.notifier).clear();
    setState(() => _isSignUp = signUp);
  }

  Future<void> _google() async {
    // Native sign-in and the browser-OAuth deep-link return both complete as a
    // `signedIn` auth event, which closes this screen (see FashionOsApp) — so we
    // don't pop here (the browser flow isn't done when this call returns).
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
  }

  Future<void> _forgotPassword() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authForgotTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.authForgotBody),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.authEmail,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.profileCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.authForgotSend),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null) return;
    if (!_emailRe.hasMatch(email)) {
      _snack(l10n.authEmailInvalid);
      return;
    }
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(email);
    if (ok && mounted) _snack(l10n.authForgotSent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(authControllerProvider);
    final loading = state.isLoading;
    final error = state.hasError ? authErrorMessage(state.error, l10n) : null;

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
                // Mode switcher — makes "sign in" vs "sign up" unmistakable.
                Center(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.login),
                        label: Text(l10n.authSignIn),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(l10n.authSignUp),
                      ),
                    ],
                    selected: {_isSignUp},
                    onSelectionChanged:
                        loading ? null : (s) => _setMode(s.first),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(
                  _isSignUp ? l10n.authSignUpTitle : l10n.authSignInTitle,
                  style: text.displaySmall,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  _isSignUp ? l10n.authSignUpSubtitle : l10n.authSignInSubtitle,
                  style: text.bodySmall,
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
                if (!_isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: loading ? null : _forgotPassword,
                      child: Text(l10n.authForgotPassword),
                    ),
                  ),
                if (_isSignUp) ...[
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.authConfirmPassword,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == _password.text ? null : l10n.authPasswordMismatch,
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Text(
                    error,
                    style: text.bodySmall?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpace.lg),
                PrimaryButton(
                  label: _isSignUp ? l10n.authSignUpCta : l10n.authSignInCta,
                  isLoading: loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  onPressed: loading ? null : _google,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(l10n.authGoogle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
