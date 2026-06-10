import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/features/profile/avatar_screen.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/l10n/app_localizations.dart';

// Valid 1x1 PNG so Image.memory decodes without throwing.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakeProfileRepository implements ProfileRepository {
  int consentCalls = 0;
  Map<String, dynamic>? updated;

  @override
  Future<Profile> getProfile() async => const Profile(id: 'u1');

  @override
  Future<Profile> updateProfile({
    String? displayName,
    String? avatarUrl,
    BodyData? bodyData,
  }) async {
    updated = {
      'avatarUrl': avatarUrl,
      'height': bodyData?.heightCm,
      'bodyType': bodyData?.bodyType,
    };
    return Profile(id: 'u1', avatarUrl: avatarUrl, bodyData: bodyData);
  }

  @override
  Future<void> recordConsent({
    required String type,
    required String version,
  }) async {
    consentCalls++;
  }
}

class _FakeAvatarService implements AvatarService {
  _FakeAvatarService({this.pickResult});

  final Uint8List? pickResult;
  Uint8List? uploaded;

  @override
  Future<Uint8List?> pickAndCompress(ImageSource source) async => pickResult;

  @override
  Future<String> upload(Uint8List bytes) async {
    uploaded = bytes;
    return 'u1/avatar.jpg';
  }

  @override
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async =>
      'https://signed/$path';
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpAvatar(
    WidgetTester tester, {
    required Profile profile,
    required _FakeProfileRepository repo,
    _FakeAvatarService? avatar,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => profile),
          profileRepositoryProvider.overrideWithValue(repo),
          avatarServiceProvider.overrideWithValue(
            avatar ?? _FakeAvatarService(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AvatarScreen(),
        ),
      ),
    );
    await tester.pump(); // resolve the profile future
  }

  testWidgets('consent gate records biometric consent on agree', (
    tester,
  ) async {
    final repo = _FakeProfileRepository();
    await pumpAvatar(
      tester,
      profile: const Profile(id: 'u1', biometricConsent: false),
      repo: repo,
    );

    expect(find.text('I agree & continue'), findsOneWidget);
    await tester.tap(find.text('I agree & continue'));
    await tester.pump();
    await tester.pump();

    expect(repo.consentCalls, 1);
  });

  testWidgets('saving height + body type updates the profile', (tester) async {
    final repo = _FakeProfileRepository();
    await pumpAvatar(
      tester,
      profile: const Profile(id: 'u1', biometricConsent: true),
      repo: repo,
    );

    await tester.enterText(find.byType(TextField), '175');
    await tester.tap(find.text('Average'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(repo.updated?['height'], 175);
    expect(repo.updated?['bodyType'], 'Average');
  });

  testWidgets('capturing a selfie uploads it on save', (tester) async {
    final repo = _FakeProfileRepository();
    final avatar = _FakeAvatarService(pickResult: _png);
    await pumpAvatar(
      tester,
      profile: const Profile(id: 'u1', biometricConsent: true),
      repo: repo,
      avatar: avatar,
    );

    await tester.tap(find.text('Camera'));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(avatar.uploaded, isNotNull);
    expect(repo.updated?['avatarUrl'], 'u1/avatar.jpg');
  });
}
