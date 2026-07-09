import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'giveaway_browse_view.dart';

/// The user's own giveaway listings (FEATURES_COMMUNITY_PLUS · Giveaway). Tap a
/// listing to view its requests inbox + manage it.
class GiveawaysMineScreen extends ConsumerWidget {
  const GiveawaysMineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(myGiveawaysProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.giveawayMine)),
      body: SafeArea(
        child: async.when(
          loading: () => PremiumLogoLoader(label: l10n.loadingGiveaways),
          error: (_, _) => ErrorState(
            title: l10n.giveawayError,
            onRetry: () => ref.invalidate(myGiveawaysProvider),
          ),
          data: (items) => items.isEmpty
              ? EmptyState(
                  icon: Icons.volunteer_activism_outlined,
                  title: l10n.giveawayMineEmpty,
                  message: l10n.giveawayEmptyMessage,
                  actionLabel: l10n.giveawayList,
                  onAction: () => context.push(AppRoute.giveawayCreate),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myGiveawaysProvider),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppSpace.screenH),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpace.md,
                      crossAxisSpacing: AppSpace.md,
                      childAspectRatio: 0.74,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => GiveawayCard(
                      giveaway: items[i],
                      onTap: () => context.push(
                        AppRoute.giveawayDetail,
                        extra: items[i].id,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
