import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/offers_repository.dart';
import '../../features/social/social_providers.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Search (board §3.16, P9) — scoped search across the Closet, Community,
/// and Brands. Filtering is client-side over already-loaded data (there is no
/// server search endpoint); recent terms are kept for the session.
class WtmSearchScreen extends ConsumerStatefulWidget {
  const WtmSearchScreen({super.key, this.initialScope});

  final String? initialScope;

  @override
  ConsumerState<WtmSearchScreen> createState() => _WtmSearchScreenState();
}

enum _Scope { closet, community, brands }

class _WtmSearchScreenState extends ConsumerState<WtmSearchScreen> {
  final _controller = TextEditingController();
  final _recent = <String>[];
  late _Scope _scope = switch (widget.initialScope) {
    'community' => _Scope.community,
    'brands' => _Scope.brands,
    _ => _Scope.closet,
  };
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    setState(() {
      _query = t;
      _recent.remove(t);
      _recent.insert(0, t);
      if (_recent.length > 6) _recent.removeLast();
    });
  }

  List<Widget> _results(AppLocalizations l10n) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    switch (_scope) {
      case _Scope.closet:
        final items = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
        final hits = [
          for (final i in items)
            if ('${i.title ?? ''} ${i.category ?? ''}'
                .toLowerCase()
                .contains(q))
              i,
        ];
        return [
          for (final i in hits.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: WtmRow(
                glyph: WtmGlyph.hanger,
                title: i.title ?? l10n.wtmSearchUntitled,
                subtitle: i.category,
                onTap: () => context.push(AppRoute.wtmClosetItem, extra: i),
              ),
            ),
        ];
      case _Scope.community:
        final posts = ref.watch(feedProvider).asData?.value ?? const [];
        final hits = [
          for (final p in posts)
            if ('${p.caption ?? ''} ${p.authorName ?? ''}'
                .toLowerCase()
                .contains(q))
              p,
        ];
        return [
          for (final p in hits.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: WtmRow(
                glyph: WtmGlyph.image,
                title: p.authorName ?? l10n.wtmSocialSomeone,
                subtitle: p.caption,
                onTap: () => context.push(AppRoute.wtmPost, extra: p),
              ),
            ),
        ];
      case _Scope.brands:
        final offers = ref.watch(offersProvider).asData?.value ?? const [];
        final hits = [
          for (final o in offers)
            if ('${o.brand ?? ''} ${o.title}'.toLowerCase().contains(q)) o,
        ];
        return [
          for (final o in hits.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: WtmRow(
                glyph: WtmGlyph.store,
                title: o.brand ?? o.title,
                subtitle: o.discountLabel,
                onTap: () =>
                    context.push('${AppRoute.wtmOfferDetail}?id=${o.id}'),
              ),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = _results(l10n);

    return WtmPage(
      title: l10n.wtmSearchTitle,
      eyebrow: switch (_scope) {
        _Scope.closet => l10n.wtmSearchCloset,
        _Scope.community => l10n.wtmSearchCommunity,
        _Scope.brands => l10n.wtmSearchBrands,
      },
      children: [
        TextField(
          controller: _controller,
          style: WtmType.body.copyWith(fontSize: 13.5),
          cursorColor: WtmColors.gold,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v.trim()),
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: l10n.wtmSearchHint,
            hintStyle:
                WtmType.body.copyWith(fontSize: 13.5, color: WtmColors.faint),
            prefixIcon: const Padding(
              padding: EdgeInsets.all(12),
              child: WtmIcon(WtmGlyph.search, size: 15, color: WtmColors.muted),
            ),
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
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        WtmChipRow(
          children: [
            for (final (i, label) in [
              l10n.wtmSearchCloset,
              l10n.wtmSearchCommunity,
              l10n.wtmSearchBrands,
            ].indexed)
              WtmChip(
                label: label,
                on: _scope.index == i,
                onTap: () => setState(() => _scope = _Scope.values[i]),
              ),
          ],
        ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: WtmSpace.s14),
          EyebrowLabel(l10n.wtmSearchRecent),
          const SizedBox(height: WtmSpace.s8),
          WtmChipRow(
            children: [
              for (final term in _recent)
                WtmChip(
                  label: term,
                  onTap: () {
                    _controller.text = term;
                    _submit(term);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: WtmSpace.s14),
        if (_query.isEmpty)
          Text(l10n.wtmSearchPrompt, style: WtmType.micro)
        else if (results.isEmpty)
          Text(l10n.wtmSearchNoResults, style: WtmType.micro)
        else ...[
          EyebrowLabel(l10n.wtmSearchResults),
          const SizedBox(height: WtmSpace.s8),
          ...results,
        ],
      ],
    );
  }
}
