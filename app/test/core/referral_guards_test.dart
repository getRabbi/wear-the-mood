import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Policy guards for the referral work (§24): the mandated technical direction
/// (no Firebase Dynamic Links, official Install Referrer lib) and no invasive
/// permissions.
void main() {
  test('no Firebase Dynamic Links dependency is introduced', () {
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    expect(pubspec.contains('firebase_dynamic_links'), isFalse);
    expect(pubspec.contains('dynamic_links'), isFalse);
  });

  test('AndroidManifest adds no Contacts / advertising-id permission', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('READ_CONTACTS'), isFalse);
    expect(manifest.contains('GET_ACCOUNTS'), isFalse);
    expect(manifest.contains('com.google.android.gms.permission.AD_ID'), isFalse);
    // The referral App Link is present, verified, and scoped to the /r/ path.
    expect(manifest.contains('android:autoVerify="true"'), isTrue);
    expect(manifest.contains('android:pathPrefix="/r/"'), isTrue);
  });

  test('the official Play Install Referrer library is declared', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(
      gradle.contains('com.android.installreferrer:installreferrer'),
      isTrue,
    );
  });
}
