import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/core/utils/in_app_link_policy.dart';

/// The security core of the in-app Newsroom reader. Every navigation the viewer
/// is asked to make — the first load, a tap inside the page, a redirect — goes
/// through [decideInAppLink], so these cases ARE the policy.
void main() {
  group('decideInAppLink · loads in-app', () {
    test('an ordinary https article', () {
      expect(
        decideInAppLink('https://vogue.com/fashion/story-1'),
        const InAppLinkDecision(
          InAppLinkAction.loadInApp,
          url: 'https://vogue.com/fashion/story-1',
        ),
      );
    });

    test('a cleartext article, UPGRADED to https rather than refused', () {
      // Every prod Newsroom URL is https today, but a syndicated feed is not
      // ours to police and one cleartext link used to mean "That link isn't
      // safe to open." over a perfectly good story. The upgrade only ever moves
      // in the safe direction; if the host has no TLS the load fails and the
      // reader offers Retry.
      final decision = decideInAppLink('http://vogue.com/story');
      expect(decision.action, InAppLinkAction.loadInApp);
      expect(decision.url, 'https://vogue.com/story');
    });

    test('whitespace around a link is trimmed, not treated as malformed', () {
      expect(
        decideInAppLink('  https://vogue.com/a  ').url,
        'https://vogue.com/a',
      );
    });

    test('an upgrade never invents a host or loses the path', () {
      expect(
        decideInAppLink('http://ft.com/a/b?x=1#top').url,
        'https://ft.com/a/b?x=1#top',
      );
    });

    test('https with a query and a fragment', () {
      expect(
        decideInAppLink('https://ft.com/a?utm=x&b=2#top').action,
        InAppLinkAction.loadInApp,
      );
    });

    test('an https subdomain of our own site that is not a deep link', () {
      // wearthemood.com/about is our marketing site, not an app destination —
      // it stays in the reader rather than trying to become a route.
      expect(
        decideInAppLink('https://wearthemood.com/about').action,
        InAppLinkAction.loadInApp,
      );
    });
  });

  group('decideInAppLink · blocks', () {
    // The whole point: none of these may reach a platform handler.
    const blocked = <String, String>{
      'javascript:': 'javascript:alert(document.cookie)',
      'file:': 'file:///data/data/com.fashionos.app/databases/app.db',
      'intent:': 'intent://scan/#Intent;scheme=zxing;end',
      'data:': 'data:text/html,<script>fetch("//evil.test")</script>',
      'tel:': 'tel:+8801700000000',
      'mailto:': 'mailto:someone@example.com',
      'sms:': 'sms:+8801700000000',
      'market:': 'market://details?id=com.fashionos.app',
      'custom app scheme': 'com.fashionos.app://login-callback',
      'unknown vendor scheme': 'weirdapp://do-something',
      // NOT here any more: plain http, which is upgraded rather than refused —
      // see the loadInApp group. Nothing cleartext is ever fetched.
      'userinfo spoof': 'https://vogue.com@evil.test/story',
      'userinfo spoof over http': 'http://vogue.com@evil.test/story',
      'scheme-relative': '//evil.test/story',
      'no host': 'https:///story',
      'empty': '',
      'whitespace': '   ',
      'not a url at all': 'not a url',
    };

    blocked.forEach((label, url) {
      test(label, () {
        expect(
          decideInAppLink(url).action,
          InAppLinkAction.block,
          reason: '$label must never leave the in-app reader',
        );
      });
    });
  });

  group('decideInAppLink · routes through go_router', () {
    test('a Wear The Mood referral link opens the real referral screen', () {
      final decision = decideInAppLink('https://wearthemood.com/r/ABC123');
      expect(decision.action, InAppLinkAction.routeInApp);
      expect(decision.route, AppRoute.wtmReferral);
    });

    test('the www host too', () {
      expect(
        decideInAppLink('https://www.wearthemood.com/r/XYZ').action,
        InAppLinkAction.routeInApp,
      );
    });

    test('a cleartext invite is upgraded, then routed', () {
      // The referral check now runs on the NORMALIZED url, so an http invite
      // reaches the native referral screen instead of being rendered as a web
      // page. It grants nothing new: anyone able to put this link in front of
      // the user could have written the https form.
      final decision = decideInAppLink('http://wearthemood.com/r/ABC123');
      expect(decision.action, InAppLinkAction.routeInApp);
      expect(decision.route, AppRoute.wtmReferral);
    });

    test('a look-alike host is not our deep link', () {
      final decision = decideInAppLink('https://wearthemood.com.evil.test/r/A');
      expect(decision.action, InAppLinkAction.loadInApp);
      expect(decision.route, isNull);
    });
  });

  group('isNotifiableBlock', () {
    // A publisher page navigates constantly on its own. Announcing every
    // refusal is what put "That link isn't safe to open." over an article that
    // had loaded fine — and, before the snack was scoped, over the screens
    // after it.
    test('page mechanics are refused silently', () {
      for (final url in const [
        'javascript:void(0)',
        'about:blank',
        'blob:https://vogue.com/9f2c',
        'data:text/html,<b>x</b>',
        '',
        'not a url',
      ]) {
        expect(isNotifiableBlock(url), isFalse, reason: url);
      }
    });

    test('a real destination is worth telling the user about', () {
      for (final url in const [
        'market://details?id=com.fashionos.app',
        'intent://scan/#Intent;scheme=zxing;end',
        'weirdapp://do-something',
        'ftp://files.example.com/a',
      ]) {
        expect(isNotifiableBlock(url), isTrue, reason: url);
      }
    });
  });

  group('displayDomain', () {
    test('strips www so the reader shows the publisher plainly', () {
      expect(displayDomain('https://www.vogue.com/a/b'), 'vogue.com');
    });

    test('keeps a real subdomain', () {
      expect(displayDomain('https://runway.vogue.com/a'), 'runway.vogue.com');
    });

    test('lowercases a shouty host', () {
      expect(displayDomain('https://VOGUE.com/a'), 'vogue.com');
    });

    test('null when there is no host to show', () {
      expect(displayDomain('not a url'), isNull);
      expect(displayDomain(''), isNull);
    });
  });
}
