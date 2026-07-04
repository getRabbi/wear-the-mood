import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal/legal_links.dart';
import '../../core/router/routes.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'stub_scaffold.dart';

// The credit top-up sheet (showTopUpSheet) + Paywall shipped in P6 — see
// ui/paywall/. Their stubs were deleted when the real screens replaced them.

/// Settings stub (board 12 + §3.1 appended rows).
class SettingsStub extends StatelessWidget {
  const SettingsStub({super.key});

  @override
  Widget build(BuildContext context) {
    Future<void> infoSheet(String title, String note) =>
        showWtmSheet(context, title: title, subtitle: note);

    return WtmStubScreen(
      title: 'Settings',
      eyebrow: 'Preferences & account',
      phase: 'P7',
      children: [
        WtmRow(
          glyph: WtmGlyph.user,
          title: 'Account',
          subtitle: 'Personal information',
          onTap: () => context.push(AppRoute.wtmProfileEdit),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.sliders,
          title: 'Preferences',
          subtitle: 'App behavior & language',
          onTap: () =>
              infoSheet('Preferences', 'App behavior settings land in P7.'),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.bell,
          title: 'Notifications',
          subtitle: 'Manage your alerts',
          onTap: () =>
              infoSheet('Notifications', 'Alert controls land in P7.'),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.shield,
          title: 'Privacy',
          subtitle: 'Control your data',
          onTap: () => infoSheet(
              'Privacy', 'Data controls & export land in P7.'),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.ruler,
          title: 'Units',
          subtitle: 'Centimeters · kilograms',
          onTap: () => infoSheet('Units', 'Unit switching lands in P7.'),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.help,
          title: 'Help & Support',
          subtitle: 'FAQs & contact',
          onTap: () => infoSheet('Help & Support', 'Help center lands in P7.'),
        ),
        const SizedBox(height: 9),
        // §3.1 appended rows.
        WtmRow(
          glyph: WtmGlyph.sparkle,
          title: 'Subscription',
          subtitle: 'Gold Tier · manage & restore',
          onTap: () => context.push(AppRoute.wtmPaywall),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.bookmark,
          title: 'Legal',
          subtitle: 'Privacy Policy & Terms',
          onTap: () => showWtmSheet(
            context,
            title: 'Legal',
            children: [
              WtmRow(
                glyph: WtmGlyph.shield,
                title: 'Privacy Policy',
                onTap: () => launchUrl(Uri.parse(LegalLinks.privacy),
                    mode: LaunchMode.externalApplication),
              ),
              const SizedBox(height: 9),
              WtmRow(
                glyph: WtmGlyph.bookmark,
                title: 'Terms of Service',
                onTap: () => launchUrl(Uri.parse(LegalLinks.terms),
                    mode: LaunchMode.externalApplication),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.erase,
          title: 'Delete Account',
          subtitle: 'Erase account & data',
          titleColor: WtmColors.danger,
          iconColor: WtmColors.danger,
          onTap: () async {
            // §3.1: danger, double-confirm (App Store requirement). The live
            // deletion flow already exists in the shipped app; it re-wires
            // here in P7.
            final first = await wtmConfirmDialog(
              context,
              title: 'Delete your account?',
              message: 'Your closet, looks, and posts will be erased.',
              confirmLabel: 'Continue',
              danger: true,
            );
            if (!first || !context.mounted) return;
            final second = await wtmConfirmDialog(
              context,
              title: 'This is permanent',
              message: 'There is no way back. Delete everything?',
              confirmLabel: 'Delete forever',
              danger: true,
            );
            if (second && context.mounted) {
              wtmStubSnack(
                  context, 'Deletion flow re-wires here in P7 (stub).');
            }
          },
        ),
        const SizedBox(height: 9),
        WtmRow(
          glyph: WtmGlyph.back,
          title: 'Sign Out',
          onTap: () async {
            final confirmed = await wtmConfirmDialog(
              context,
              title: 'Sign out?',
              message: 'You can sign back in any time.',
              confirmLabel: 'Sign out',
            );
            if (confirmed && context.mounted) {
              wtmStubSnack(context, 'Sign-out wires at cutover (stub).');
            }
          },
        ),
        const SizedBox(height: WtmSpace.s18),
        const EyebrowLabel('Body photo'),
        const SizedBox(height: WtmSpace.s10),
        Container(
          padding: const EdgeInsets.all(WtmSpace.s12),
          decoration: BoxDecoration(
            gradient: WtmGradients.cardFill,
            borderRadius: BorderRadius.circular(WtmRadius.card),
            border: Border.all(color: WtmColors.line),
          ),
          child: Row(
            children: [
              const AuroraBox(
                width: 50,
                height: 64,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              const SizedBox(width: WtmSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your try-on photo', style: WtmType.labelMedium),
                    const SizedBox(height: 3),
                    Text('Used for fit & AI try-on', style: WtmType.micro),
                  ],
                ),
              ),
              GoldPill(
                label: 'Update',
                onTap: () => context.push(AppRoute.wtmBodyPhoto),
              ),
            ],
          ),
        ),
        const SizedBox(height: WtmSpace.s16),
        Center(
          child: Text('Wear The Mood · Atelier preview',
              style: WtmType.micro),
        ),
      ],
    );
  }
}

/// Edit-profile form stub (§3.1 — Edit Profile pill).
class ProfileEditStub extends StatelessWidget {
  const ProfileEditStub({super.key});

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String hint) => InputDecoration(
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
        );

    return WtmStubScreen(
      title: 'Edit Profile',
      eyebrow: 'Account',
      phase: 'P7',
      children: [
        const Center(child: WtmStubAvatar('AR', size: 76)),
        const SizedBox(height: WtmSpace.s10),
        Center(
          child: GoldPill(
            label: 'Change photo',
            onTap: () =>
                wtmStubSnack(context, 'Avatar picker lands in P7 (stub).'),
          ),
        ),
        const SizedBox(height: WtmSpace.s16),
        TextField(
            style: WtmType.body,
            cursorColor: WtmColors.gold,
            decoration: field('Name — Anika Rehman')),
        const SizedBox(height: WtmSpace.s10),
        TextField(
            style: WtmType.body,
            cursorColor: WtmColors.gold,
            maxLines: 3,
            decoration: field('Bio — Fashion creator ✦')),
        const SizedBox(height: WtmSpace.s10),
        TextField(
            style: WtmType.body,
            cursorColor: WtmColors.gold,
            decoration: field('Location — Dhaka')),
        const SizedBox(height: WtmSpace.s16),
        GradientCta(
          label: 'Save',
          onPressed: () {
            wtmStubSnack(context, 'Saved (stub — real in P7).');
            wtmStubBack(context);
          },
        ),
      ],
    );
  }
}

/// Brand & Store form stub (Upload Hub row 4).
class BrandStoreStub extends StatelessWidget {
  const BrandStoreStub({super.key});

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String hint) => InputDecoration(
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
        );

    return WtmStubScreen(
      title: 'Brand & Store',
      eyebrow: 'Link a brand',
      phase: 'P9',
      children: [
        Text(
          'Connect a brand or store to surface its drops and offers.',
          style: WtmType.sub,
        ),
        const SizedBox(height: WtmSpace.s14),
        TextField(
            style: WtmType.body,
            cursorColor: WtmColors.gold,
            decoration: field('Brand name')),
        const SizedBox(height: WtmSpace.s10),
        TextField(
            style: WtmType.body,
            cursorColor: WtmColors.gold,
            decoration: field('Website or store link')),
        const SizedBox(height: WtmSpace.s16),
        GradientCta(
          label: 'Submit',
          onPressed: () {
            wtmStubSnack(context, 'Submitted (stub — review lands in P9).');
            wtmStubBack(context);
          },
        ),
      ],
    );
  }
}

// PaywallStub shipped as the real WtmPaywallScreen in P6 (ui/paywall/).
