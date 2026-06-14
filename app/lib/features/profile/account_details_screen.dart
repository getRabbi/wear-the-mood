import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Personal details (CLAUDE.md §10). Edit display name + phone (profile), and
/// change the sign-in email/password (Supabase auth). Email changes are confirmed
/// via a link Supabase emails to the new address.
class AccountDetailsScreen extends ConsumerStatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  ConsumerState<AccountDetailsScreen> createState() =>
      _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends ConsumerState<AccountDetailsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _initialised = false;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _prime(Profile p) {
    if (_initialised) return;
    _initialised = true;
    _nameController.text = p.displayName ?? '';
    _phoneController.text = p.phone ?? '';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, {required String onError}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException {
      _snack(onError);
    } catch (_) {
      // Supabase AuthException + anything else -> the same friendly message.
      _snack(onError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    final l10n = AppLocalizations.of(context);
    await _run(onError: l10n.accountSaveError, () async {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            displayName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
      ref.invalidate(profileProvider);
      _snack(l10n.accountSaved);
    });
  }

  Future<void> _changeEmail() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    await _run(onError: l10n.accountAuthError, () async {
      await ref.read(authRepositoryProvider).updateEmail(email);
      _emailController.clear();
      _snack(l10n.accountEmailChanged);
    });
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final email = ref.read(signedInEmailProvider);
    final current = _currentPasswordController.text;
    final password = _passwordController.text;
    if (password.length < 8) {
      _snack(l10n.accountPasswordTooShort);
      return;
    }
    if (email == null) {
      _snack(l10n.accountAuthError);
      return;
    }
    setState(() => _busy = true);
    try {
      // Re-verify the CURRENT password before changing it, so an open session
      // alone can't reset the password (§11).
      try {
        await ref
            .read(authRepositoryProvider)
            .reauthenticate(email: email, password: current);
      } catch (_) {
        _snack(l10n.accountCurrentPasswordWrong);
        return; // finally resets _busy
      }
      await ref.read(authRepositoryProvider).updatePassword(password);
      _currentPasswordController.clear();
      _passwordController.clear();
      _snack(l10n.accountPasswordChanged);
    } catch (_) {
      _snack(l10n.accountAuthError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);
    final email = ref.watch(signedInEmailProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountDetailsTitle)),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.avatarLoadError,
            onRetry: () => ref.invalidate(profileProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (profile) {
            _prime(profile);
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  children: [
                    _SectionTitle(l10n.accountSectionProfile),
                    const SizedBox(height: AppSpace.sm),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: l10n.accountNameLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l10n.accountPhoneLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    PrimaryButton(
                      label: l10n.accountSave,
                      icon: Icons.check_rounded,
                      isLoading: _busy,
                      onPressed: _saveProfile,
                    ),

                    const SizedBox(height: AppSpace.xl),
                    _SectionTitle(l10n.accountSectionSecurity),
                    const SizedBox(height: AppSpace.sm),
                    if (email != null)
                      Text(
                        l10n.accountEmailCurrent(email),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: l10n.accountEmailLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      l10n.accountEmailNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.graphite,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _changeEmail,
                      icon: const Icon(Icons.alternate_email_rounded),
                      label: Text(l10n.accountChangeEmail),
                    ),

                    const SizedBox(height: AppSpace.lg),
                    TextField(
                      controller: _currentPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.accountCurrentPasswordLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.accountPasswordLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _changePassword,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: Text(l10n.accountChangePassword),
                    ),
                  ],
                ),
                if (_busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}
