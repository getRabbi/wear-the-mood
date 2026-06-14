import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Reached from a password-reset email (an `AuthChangeEvent.passwordRecovery`
/// deep link). The recovery session is already active, so NO current password is
/// needed here — the user just sets a new one (CLAUDE.md §10/§11).
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      _snack(l10n.accountPasswordChanged);
      context.go(AppRoute.home);
    } catch (_) {
      _snack(l10n.accountAuthError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setPasswordTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.setPasswordTitle, style: text.displaySmall),
                const SizedBox(height: AppSpace.xl),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.accountPasswordLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').length >= 8 ? null : l10n.authPasswordTooShort,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.authConfirmPassword,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == _password.text ? null : l10n.authPasswordMismatch,
                ),
                const SizedBox(height: AppSpace.lg),
                PrimaryButton(
                  label: l10n.setPasswordCta,
                  icon: Icons.lock_reset_rounded,
                  isLoading: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
