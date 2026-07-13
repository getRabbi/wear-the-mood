import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/referral/app_link_channel.dart';
import 'package:app/core/referral/install_referrer_channel.dart';

void main() {
  group('parseReferralToken (Play install referrer)', () {
    test('extracts referral_token, ignoring organic/utm noise', () {
      expect(
        parseReferralToken('referral_token=ABC123&utm_source=referral&utm_medium=share'),
        'ABC123',
      );
      expect(parseReferralToken('utm_source=referral&referral_token=XYZ'), 'XYZ');
    });

    test('organic / empty / malformed → null (no attribution)', () {
      expect(parseReferralToken(null), isNull);
      expect(parseReferralToken(''), isNull);
      expect(parseReferralToken('utm_source=google-play&utm_medium=organic'), isNull);
      expect(parseReferralToken('referral_token='), isNull); // present but empty
      expect(parseReferralToken('not a query string'), isNull);
    });
  });

  group('referralCodeFromLink (App Link /r/<code>)', () {
    test('valid https referral links → uppercase code', () {
      expect(referralCodeFromLink('https://wearthemood.com/r/ab2cd3ef'), 'AB2CD3EF');
      expect(referralCodeFromLink('https://www.wearthemood.com/r/CODE12'), 'CODE12');
      expect(
        referralCodeFromLink('https://wearthemood.com/r/CODE12?utm=x'),
        'CODE12',
      );
    });

    test('rejects wrong host / scheme / path / empty', () {
      expect(referralCodeFromLink('http://wearthemood.com/r/CODE'), isNull); // not https
      expect(referralCodeFromLink('https://evil.com/r/CODE'), isNull); // wrong host
      expect(referralCodeFromLink('https://wearthemood.com/about'), isNull); // not /r/
      expect(referralCodeFromLink('https://wearthemood.com/r/'), isNull); // no code
      expect(referralCodeFromLink(null), isNull);
      expect(referralCodeFromLink(''), isNull);
    });
  });
}
