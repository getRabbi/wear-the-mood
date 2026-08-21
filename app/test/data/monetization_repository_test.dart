import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/monetization.dart';
import 'package:app/data/repositories/monetization_repository.dart';

import '../helpers/fake_dio.dart';

/// The monetization snapshot, and the defaults it falls back to.
///
/// The defaults are the point. An app that cannot reach `/v1/monetization/config`
/// — an old backend, a dropped request, a partial response — must still behave
/// like today's production app rather than like an experiment nobody authorized
/// (RETENTION spec §53).
void main() {
  group('defaults', () {
    test('an empty response reproduces current production costs', () {
      final config = MonetizationConfig.fromJson(const {});
      expect(config.renderCosts.standard, 1);
      expect(config.renderCosts.hd, 4);
      expect(config.renderCosts.enhance, 4);
      expect(config.trialEnabled, isFalse);
      expect(config.rolloverEnabled, isFalse);
      expect(config.paywallV2, isFalse);
      expect(config.renderGateV2, isFalse);
      expect(config.experiments, isEmpty);
    });

    test(
      'a missing paywall policy allows an interruption rather than blocking',
      () {
        // Fail OPEN: a wrong `true` is one closable paywall; a wrong `false` is a
        // user who can never be told they have run out.
        final config = MonetizationConfig.fromJson(const {});
        expect(config.paywall.mayInterrupt, isTrue);
        expect(config.paywall.cooldownHours, 24);
        expect(config.paywall.postPurchaseCooldownHours, 72);
      },
    );
  });

  group('the render gate', () {
    MonetizationConfig config({required String tier, required int remaining}) =>
        MonetizationConfig.fromJson({
          'tier': tier,
          'free_render_remaining': remaining,
          'free_render_limit': 3,
        });

    test('a free user with renders left is not gated', () {
      expect(config(tier: 'free', remaining: 1).freeRendersExhausted, isFalse);
    });

    test('a free user with none left is gated', () {
      expect(config(tier: 'free', remaining: 0).freeRendersExhausted, isTrue);
    });

    test('a subscriber is never render-gated by the FREE allowance', () {
      // A Pro user out of PLAN credits sees the top-up path, not the free-trial
      // gate — conflating the two would tell a paying customer their free trial
      // is over, which is both wrong and insulting.
      for (final tier in ['pro', 'pro_max']) {
        expect(
          config(tier: tier, remaining: 0).freeRendersExhausted,
          isFalse,
          reason: '$tier must not hit the free-render gate',
        );
      }
    });
  });

  group('plans', () {
    test('the catalog price is parsed but is not the display price', () {
      final config = MonetizationConfig.fromJson(const {
        'plans': [
          {
            'tier': 'pro',
            'kind': 'subscription',
            'price_usd': 8.99,
            'monthly_credits': 75,
            'hd_allowed': false,
            'play_product_id': 'pro_monthly',
          },
        ],
      });
      final pro = config.plans.single;
      expect(pro.tier, 'pro');
      expect(pro.monthlyCredits, 75);
      expect(pro.hdAllowed, isFalse);
      expect(pro.playProductId, 'pro_monthly');
      // Present for reconciliation; the paywall shows the STORE's string (§7.2).
      expect(pro.priceUsd, 8.99);
    });
  });

  group('the pressure ledger', () {
    test('a recorded event names its surface, action and intent', () async {
      final (dio, adapter) = fakeDio((_) => jsonResponse({'recorded': true}));
      await MonetizationRepository(dio).recordEvent(
        surface: MonetizationSurface.paywall,
        action: MonetizationAction.dismissed,
        interruptive: true,
      );
      final body =
          jsonDecode(jsonEncode(adapter.lastRequest!.data))
              as Map<String, dynamic>;
      expect(body['surface'], 'paywall');
      expect(body['action'], 'dismissed');
      expect(body['interruptive'], isTrue);
    });

    test('a user-opened surface is recorded as non-interruptive', () async {
      final (dio, adapter) = fakeDio((_) => jsonResponse({'recorded': true}));
      await MonetizationRepository(dio).recordEvent(
        surface: MonetizationSurface.paywall,
        action: MonetizationAction.viewed,
      );
      final body =
          jsonDecode(jsonEncode(adapter.lastRequest!.data))
              as Map<String, dynamic>;
      // Defaults to false, so a paywall the user opened cannot start a
      // cooldown against itself.
      expect(body['interruptive'], isFalse);
    });

    test('a failed ledger write never surfaces to the caller', () async {
      // A paywall must not fail to open because its bookkeeping did.
      final (dio, _) = fakeDio((_) => jsonResponse({}, status: 500));
      await expectLater(
        MonetizationRepository(dio).recordEvent(
          surface: MonetizationSurface.topupSheet,
          action: MonetizationAction.purchased,
        ),
        completes,
      );
    });
  });
}
