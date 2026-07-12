import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal/legal_links.dart';
import '../../core/router/routes.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_error.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Sign In / Sign Up (board §3.2, P10) — email + Google (and Apple on iOS)
/// on the shipped [AuthController]. On success it returns to the splash, which
/// routes on to onboarding or home.
class WtmAuthScreen extends ConsumerStatefulWidget {
  const WtmAuthScreen({super.key});

  @override
  ConsumerState<WtmAuthScreen> createState() => _WtmAuthScreenState();
}

class _WtmAuthScreenState extends ConsumerState<WtmAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toggle() {
    ref.read(authControllerProvider.notifier).clear();
    setState(() => _isSignUp = !_isSignUp);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    final ctrl = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      final result = await ctrl.signUpEmail(email, password);
      if (!mounted) return;
      switch (result) {
        case SignUpResult.signedIn:
          context.go(AppRoute.wtmSplash);
        case SignUpResult.needsConfirmation:
          wtmSnack(context, l10n.wtmAuthCheckEmail);
        case SignUpResult.alreadyRegistered:
          wtmSnack(context, l10n.wtmAuthAlready);
          setState(() => _isSignUp = false);
        case SignUpResult.failed:
          break;
      }
    } else {
      final ok = await ctrl.signInEmail(email, password);
      if (ok && mounted) context.go(AppRoute.wtmSplash);
    }
  }

  Future<void> _google() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle();
    if (ok && mounted) context.go(AppRoute.wtmSplash);
  }

  Future<void> _apple() async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .signInWithApple();
    if (ok && mounted) context.go(AppRoute.wtmSplash);
  }

  Future<void> _forgot() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) {
      wtmSnack(context, l10n.wtmAuthEnterEmail);
      return;
    }
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(email);
    if (ok && mounted) wtmSnack(context, l10n.wtmAuthResetSent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(authControllerProvider);
    final loading = state.isLoading;
    final isApple = Theme.of(context).platform == TargetPlatform.iOS;

    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                WtmSpace.screenH,
                WtmSpace.s22,
                WtmSpace.screenH,
                WtmSpace.s16,
              ),
              children: [
                const Center(child: TheOrb(size: 64)),
                const SizedBox(height: WtmSpace.s18),
                Text(
                  _isSignUp ? l10n.wtmAuthCreateTitle : l10n.wtmAuthSignInTitle,
                  textAlign: TextAlign.center,
                  style: WtmType.h1.copyWith(fontSize: 26),
                ),
                const SizedBox(height: WtmSpace.s6),
                Text(
                  l10n.wtmAuthSubtitle,
                  textAlign: TextAlign.center,
                  style: WtmType.sub,
                ),
                const SizedBox(height: WtmSpace.s22),
                _Field(
                  controller: _email,
                  hint: l10n.wtmAuthEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: WtmSpace.s10),
                _Field(
                  controller: _password,
                  hint: l10n.wtmAuthPassword,
                  obscure: true,
                ),
                if (state.hasError) ...[
                  const SizedBox(height: WtmSpace.s10),
                  Text(
                    authErrorMessage(state.error, l10n),
                    style: WtmType.micro.copyWith(color: WtmColors.danger),
                  ),
                ],
                const SizedBox(height: WtmSpace.s16),
                GradientCta(
                  label: _isSignUp ? l10n.wtmAuthCreate : l10n.wtmAuthSignIn,
                  onPressed: loading ? null : _submit,
                ),
                if (!_isSignUp) ...[
                  const SizedBox(height: WtmSpace.s10),
                  Center(
                    child: _TextButton(
                      label: l10n.wtmAuthForgot,
                      onTap: loading ? null : _forgot,
                    ),
                  ),
                ],
                const SizedBox(height: WtmSpace.s14),
                Row(
                  children: [
                    const Expanded(child: Divider(color: WtmColors.lineSoft)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WtmSpace.s10,
                      ),
                      child: Text(l10n.wtmAuthOr, style: WtmType.micro),
                    ),
                    const Expanded(child: Divider(color: WtmColors.lineSoft)),
                  ],
                ),
                const SizedBox(height: WtmSpace.s14),
                GhostButton(
                  label: l10n.wtmAuthGoogle,
                  onPressed: loading ? null : _google,
                ),
                if (isApple) ...[
                  const SizedBox(height: WtmSpace.s10),
                  GhostButton(
                    label: l10n.wtmAuthApple,
                    onPressed: loading ? null : _apple,
                  ),
                ],
                const SizedBox(height: WtmSpace.s16),
                Center(
                  child: _TextButton(
                    label: _isSignUp
                        ? l10n.wtmAuthHaveAccount
                        : l10n.wtmAuthNeedAccount,
                    onTap: loading ? null : _toggle,
                  ),
                ),
                const SizedBox(height: WtmSpace.s16),
                _Legal(l10n: l10n),
              ],
            ),
          ),
          if (loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: WtmColors.gold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: WtmType.body,
      cursorColor: WtmColors.gold,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
        filled: true,
        fillColor: WtmColors.iconBtnBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.chipOnBorder),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: WtmSpace.s8),
            child: Text(
              label,
              style: WtmType.micro.copyWith(color: WtmColors.gold),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legal extends StatelessWidget {
  const _Legal({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String url) => GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(label, style: WtmType.micro.copyWith(color: WtmColors.gold)),
    );
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: WtmSpace.s6,
        runSpacing: WtmSpace.s4,
        children: [
          Text(l10n.wtmAuthLegal, style: WtmType.micro),
          link(l10n.wtmSettingsPrivacyPolicy, LegalLinks.privacy),
          Text('·', style: WtmType.micro),
          link(l10n.wtmSettingsTerms, LegalLinks.terms),
        ],
      ),
    );
  }
}
