import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/profile.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/data/repositories/profile_repository.dart';
import 'package:app/data/repositories/tryon_photos_repository.dart';
import 'package:app/features/profile/avatar_screen.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/profile/pose_validator.dart';
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
    String? phone,
    String? avatarUrl,
    String? profilePictureUrl,
    BodyData? bodyData,
    String? bio,
    List<String>? styleTags,
    bool? isPublic,
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
  Uint8List? uploadedTryon;

  @override
  Future<XFile?> pick(ImageSource source, {bool preferFront = false}) async =>
      pickResult == null ? null : XFile('fake.jpg');

  @override
  Future<Uint8List> compress(XFile file) async => pickResult ?? Uint8List(0);

  @override
  Future<String> writeTempJpeg(Uint8List bytes) async => 'temp_tryon.jpg';

  @override
  Future<String> upload(Uint8List bytes) async => 'u1/avatar.jpg';

  @override
  Future<String> uploadTryonPhoto(Uint8List bytes) async {
    uploadedTryon = bytes;
    return 'u1/tryon/1.jpg';
  }

  @override
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async =>
      'https://signed/$path';
}

class _FakeTryonPhotosRepository implements TryonPhotosRepository {
  final List<TryonPhoto> initial = const [];
  String? addedPath;
  int? addedScore;
  String? deletedId;

  @override
  Future<List<TryonPhoto>> list() async => initial;

  @override
  Future<TryonPhoto> add({required String storagePath, int? qualityScore}) async {
    addedPath = storagePath;
    addedScore = qualityScore;
    return TryonPhoto(
      id: 'p1',
      storagePath: storagePath,
      qualityScore: qualityScore,
      isSelected: true,
    );
  }

  @override
  Future<void> delete(String id) async => deletedId = id;
}

/// Skips the real ML Kit call; reports a fixed issue + score.
class _FakePoseValidator extends PoseValidator {
  _FakePoseValidator({this.issue = PoseIssue.none, this.score = 90});

  final PoseIssue issue;
  final int score;

  @override
  Future<PoseCheck> validateFile(String path) async => PoseCheck(issue);

  @override
  Future<({PoseCheck check, int score})> inspectFile(String path) async =>
      (check: PoseCheck(issue), score: issue == PoseIssue.none ? score : 0);

  @override
  void dispose() {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpAvatar(
    WidgetTester tester, {
    required Profile profile,
    required _FakeProfileRepository repo,
    _FakeAvatarService? avatar,
    _FakePoseValidator? pose,
    _FakeTryonPhotosRepository? photos,
  }) async {
    tester.view.physicalSize = const Size(800, 2200);
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
          poseValidatorProvider.overrideWith(
            (ref) => pose ?? _FakePoseValidator(),
          ),
          tryonPhotosRepositoryProvider.overrideWithValue(
            photos ?? _FakeTryonPhotosRepository(),
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

  testWidgets('saving body details updates the profile', (tester) async {
    final repo = _FakeProfileRepository();
    await pumpAvatar(
      tester,
      profile: const Profile(id: 'u1', biometricConsent: true),
      repo: repo,
    );
    await tester.pump(); // resolve the gallery future

    // First TextField is the cm height field (ft/in toggle defaults to cm).
    await tester.enterText(find.byType(TextField).first, '175');
    await tester.tap(find.text('Average'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Save'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(repo.updated?['height'], 175);
    expect(repo.updated?['bodyType'], 'Average');
  });

  testWidgets('adding a full-body photo posts it with its score', (
    tester,
  ) async {
    final repo = _FakeProfileRepository();
    final avatar = _FakeAvatarService(pickResult: _png);
    final photos = _FakeTryonPhotosRepository();
    await pumpAvatar(
      tester,
      profile: const Profile(id: 'u1', biometricConsent: true),
      repo: repo,
      avatar: avatar,
      photos: photos,
      pose: _FakePoseValidator(score: 88),
    );
    await tester.pump();

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle(); // show the camera/gallery sheet
    await tester.tap(find.text('Camera'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(avatar.uploadedTryon, isNotNull);
    expect(photos.addedPath, 'u1/tryon/1.jpg');
    expect(photos.addedScore, 88);
  });

  testWidgets('a photo missing feet is rejected and not posted', (
    tester,
  ) async {
    final repo = _FakeProfileRepository();
    final avatar = _FakeAvatarService(pickResult: _png);
    final photos = _FakeTryonPhotosRepository();
    await pumpAvatar(
      tester,
      profile: const Profile(id: 'u1', biometricConsent: true),
      repo: repo,
      avatar: avatar,
      photos: photos,
      pose: _FakePoseValidator(issue: PoseIssue.feetNotVisible),
    );
    await tester.pump();

    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('Your feet aren\'t visible. Step back so the whole body shows.'),
      findsOneWidget,
    );
    expect(photos.addedPath, isNull);
    expect(avatar.uploadedTryon, isNull);
  });
}
