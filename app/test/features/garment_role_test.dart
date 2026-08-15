import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/tryon/garment_role.dart';

/// The client-side mirror of the server's canonical taxonomy (spec Phase 27).
///
/// Two properties matter more than any individual mapping:
///
///  * it can HIDE an affordance early, never GRANT one — the server re-checks
///    every request and is the only authority on eligibility;
///  * it never guesses. A category it does not recognise answers "ask the
///    server", which is the whole point of the change.
void main() {
  group('canonical roles', () {
    test('the closet picker values map to the server vocabulary', () {
      expect(canonicalRoleOf('Tops'), kRoleTop);
      expect(canonicalRoleOf('T-Shirts'), kRoleTop);
      expect(canonicalRoleOf('Jeans'), kRoleBottom);
      expect(canonicalRoleOf('Skirts'), kRoleBottom);
      expect(canonicalRoleOf('Dresses'), kRoleOnePiece);
      expect(canonicalRoleOf('Traditional'), kRoleOnePiece);
      expect(canonicalRoleOf('Outerwear'), kRoleOuterwear);
      expect(canonicalRoleOf('Hijab'), kRoleHijabScarf);
      expect(canonicalRoleOf('Eyewear'), kRoleGlasses);
      expect(canonicalRoleOf('Bags'), kRoleBag);
      expect(canonicalRoleOf('Hats'), kRoleHatHeadwear);
    });

    test('matching is case-insensitive and canonical values round-trip', () {
      expect(canonicalRoleOf('tops'), kRoleTop);
      expect(canonicalRoleOf(kRoleOnePiece), kRoleOnePiece);
      expect(canonicalRoleOf(kLookReferenceCategory), kLookReferenceCategory);
    });

    test('lifestyle buckets are unknown, not guessed', () {
      // "Activewear" says WHEN a piece is worn, not WHAT it is. Answering with
      // a role here would be the client inventing the very thing this change
      // stops the AI from inventing.
      for (final bucket in ['Activewear', 'Party', 'Travel', 'Accessories']) {
        expect(canonicalRoleOf(bucket), isNull, reason: bucket);
      }
      expect(canonicalRoleOf(null), isNull);
      expect(canonicalRoleOf('   '), isNull);
    });
  });

  group('eligibility mirror', () {
    test('a known-unsupported role is hidden early', () {
      expect(looksTryOnCapable('Belts'), isFalse);
      expect(looksTryOnCapable('Other'), isFalse);
    });

    test('an unknown category defers to the server rather than blocking', () {
      // The server can still resolve it from the item's name, so refusing here
      // would take away a render that actually works.
      expect(looksTryOnCapable('Activewear'), isTrue);
      expect(looksTryOnCapable(null), isTrue);
    });

    test('supported roles pass', () {
      for (final c in ['Tops', 'Jeans', 'Dresses', 'Hijab', 'Eyewear']) {
        expect(looksTryOnCapable(c), isTrue, reason: c);
      }
    });

    test('only a piece with NOTHING on it is treated as unidentifiable', () {
      expect(needsCategoryForTryOn(category: null, title: null), isTrue);
      expect(needsCategoryForTryOn(category: '  ', title: ''), isTrue);
      // A name alone is enough — the server resolves the role from it.
      expect(
        needsCategoryForTryOn(category: null, title: 'Running Shorts'),
        isFalse,
      );
      expect(needsCategoryForTryOn(category: 'Tops', title: null), isFalse);
    });
  });

  group('conflicts', () {
    test('two pieces for the same region conflict', () {
      expect(conflictIn(['Tops', 'Shirts']), isNotNull);
      expect(conflictIn(['Jeans', 'Skirts']), isNotNull);
    });

    test('a one-piece cannot share a look with separates', () {
      expect(conflictIn(['Dresses', 'Tops']), isNotNull);
      expect(conflictIn(['Dresses', 'Jeans']), isNotNull);
      expect(conflictIn(['Dresses', 'Outerwear']), isNotNull);
    });

    test('a whole-look reference conflicts with separate clothing', () {
      expect(conflictIn([kLookReferenceCategory, 'Tops']), isNotNull);
      expect(conflictIn([kLookReferenceCategory, 'Dresses']), isNotNull);
    });

    test('real outfits do not conflict', () {
      expect(conflictIn(['Tops', 'Jeans']), isNull);
      expect(conflictIn(['Tops', 'Jeans', 'Hijab', 'Eyewear']), isNull);
      expect(conflictIn(['Dresses', 'Hijab', 'Eyewear']), isNull);
      expect(conflictIn(['Tops', 'Jeans', 'Outerwear', 'Shoes']), isNull);
    });

    test('unknown categories never manufacture a conflict', () {
      // Two unidentified pieces might well clash, but the client cannot know
      // that — and blocking a look on a suspicion is worse than letting the
      // server answer.
      expect(conflictIn(['Activewear', 'Party']), isNull);
      expect(conflictIn([null, null]), isNull);
    });
  });
}
