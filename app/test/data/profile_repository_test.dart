import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/repositories/profile_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

Map<String, dynamic> _profile() => {
  'id': 'u1',
  'display_name': 'Mim',
  'bio': 'minimal modest',
  'style_tags': ['modest', 'minimal'],
  'is_public': true,
};

void main() {
  test('updateProfile sends bio / style_tags / is_public and parses them', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_profile()));

    final profile = await ProfileRepository(dio).updateProfile(
      bio: 'minimal modest',
      styleTags: ['modest', 'minimal'],
      isPublic: true,
    );

    expect(adapter.lastRequest!.path, '/v1/profile');
    expect(adapter.lastRequest!.method, 'PATCH');
    final body = _body(adapter.lastRequest!.data);
    expect(body['bio'], 'minimal modest');
    expect(body['style_tags'], ['modest', 'minimal']);
    expect(body['is_public'], true);
    expect(profile.bio, 'minimal modest');
    expect(profile.styleTags, ['modest', 'minimal']);
  });

  test('updateProfile omits null fields', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_profile()));
    await ProfileRepository(dio).updateProfile(displayName: 'Sam');
    final body = _body(adapter.lastRequest!.data);
    expect(body['display_name'], 'Sam');
    expect(body.containsKey('bio'), isFalse);
    expect(body.containsKey('style_tags'), isFalse);
    expect(body.containsKey('is_public'), isFalse);
  });

  test('updateProfile can clear bio and tags with empty values', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_profile()));
    await ProfileRepository(dio).updateProfile(bio: '', styleTags: const []);
    final body = _body(adapter.lastRequest!.data);
    // Empty (not null) is sent so the backend clears the field.
    expect(body['bio'], '');
    expect(body['style_tags'], <String>[]);
  });

  test('updateProfile sends show_public_closet when set', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_profile()));
    await ProfileRepository(dio).updateProfile(showPublicCloset: true);
    final body = _body(adapter.lastRequest!.data);
    expect(body['show_public_closet'], true);
  });
}
