import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/env/app_env.dart';
import '../../data/models/weather.dart';
import '../../data/repositories/profile_repository.dart';
import '../../features/stylist/weather_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../home/wtm_mood.dart';
import '../widgets/widgets.dart';

/// Serif look name with the LAST word in gold italic (board LookCard / Today's
/// Look convention — e.g. "Moonlit *Confidence*").
Widget wtmLookTitle(String title, {double size = 18}) {
  final words = title.trim().split(RegExp(r'\s+'));
  final base = WtmType.h2.copyWith(fontSize: size);
  if (words.length < 2) {
    return Text(title, style: WtmType.goldItalic(base), maxLines: 2,
        overflow: TextOverflow.ellipsis);
  }
  final head = words.sublist(0, words.length - 1).join(' ');
  return Text.rich(
    TextSpan(
      text: '$head ',
      style: base,
      children: [
        TextSpan(text: words.last, style: WtmType.goldItalic(base)),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

/// Time-of-day greeting word (shared with Home).
String wtmHello(AppLocalizations l10n) => switch (DateTime.now().hour) {
      < 12 => l10n.homeHelloMorning,
      < 17 => l10n.homeHelloAfternoon,
      _ => l10n.homeHelloEvening,
    };

/// Daypart word for context lines.
String wtmDaypart(AppLocalizations l10n) => switch (DateTime.now().hour) {
      < 12 => l10n.wtmDaypartMorning,
      < 17 => l10n.wtmDaypartAfternoon,
      _ => l10n.wtmDaypartEvening,
    };

String wtmMoodZoneLabel(AppLocalizations l10n, WtmMoodZone zone) =>
    switch (zone) {
      WtmMoodZone.calm => l10n.wtmMoodCalm,
      WtmMoodZone.confident => l10n.wtmMoodConfident,
      WtmMoodZone.bold => l10n.wtmMoodBold,
      WtmMoodZone.rebel => l10n.wtmMoodRebel,
    };

/// Board `.assist` header — mini orb + "Your stylist" eyebrow + serif greeting
/// with the signed-in first name in gold italic (greeting-only for guests /
/// tests, where Supabase isn't configured).
class WtmStylistGreeting extends ConsumerWidget {
  const WtmStylistGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hello = wtmHello(l10n);
    // Supabase-backed providers assert without env config — same guard the app
    // root and Home use.
    final signedIn =
        AppEnv.hasSupabaseConfig && ref.watch(signedInEmailProvider) != null;
    final name = signedIn
        ? ref.watch(profileProvider).asData?.value.displayName?.trim()
        : null;
    final firstName =
        (name == null || name.isEmpty) ? null : name.split(RegExp(r'\s+')).first;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: WtmGradients.assistFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WtmColors.assistBorder),
      ),
      child: Row(
        children: [
          const TheOrb(size: TheOrb.miniSize),
          const SizedBox(width: WtmSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EyebrowLabel(
                  l10n.wtmStylistYourStylist,
                  color: WtmColors.assistEyebrow,
                ),
                const SizedBox(height: 4),
                if (firstName == null)
                  Text(hello, style: WtmType.h2)
                else
                  Text.rich(
                    TextSpan(
                      text: '$hello, ',
                      style: WtmType.h2,
                      children: [
                        TextSpan(
                          text: firstName,
                          style: WtmType.goldItalic(WtmType.h2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mood · daypart · weather context chips (board §3.18) — INTERACTIVE
/// (mobile QA #3): the mood chip opens the live mood slider sheet (retunes the
/// stylist immediately), the daypart chip opens the styling-context sheet, and
/// the weather chip shows the REAL local weather ([weatherControllerProvider])
/// and opens the weather sheet (use-location / choose-city / refresh, §2/§20).
class WtmStylistContextChips extends ConsumerWidget {
  const WtmStylistContextChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final zone = WtmMoodZone.of(ref.watch(wtmMoodProvider));
    final weather = ref.watch(weatherControllerProvider);
    final country = Localizations.localeOf(context).countryCode;

    final (weatherLabel, weatherOn) = switch (weather) {
      WeatherReady(:final info) => (
          l10n.wtmWeatherLabel(
            formatTemp(info.snapshot.tempC, countryCode: country),
            info.snapshot.condition,
          ),
          true,
        ),
      WeatherLoading() => (l10n.wtmWeatherLoading, false),
      WeatherNeedsLocation() => (l10n.wtmWeatherSet, false),
      WeatherUnavailable() => (l10n.wtmWeatherUnavailableChip, false),
    };

    return WtmChipRow(
      children: [
        WtmChip(
          label: l10n.wtmStylistMoodChip(wtmMoodZoneLabel(l10n, zone)),
          on: true,
          onTap: () => _showMoodSheet(context, ref),
        ),
        WtmChip(
          label: wtmDaypart(l10n),
          onTap: () => _showContextSheet(context, ref),
        ),
        WtmChip(
          label: weatherLabel,
          on: weatherOn,
          onTap: () => showWtmWeatherSheet(context, ref),
        ),
      ],
    );
  }

  /// The live mood slider in a WTM sheet — same [wtmMoodProvider] the Home
  /// slider drives, so the stylist context retunes on release.
  Future<void> _showMoodSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return showWtmSheet(
      context,
      title: l10n.wtmStylistMoodSheetTitle,
      subtitle: l10n.wtmStylistMoodSheetNote,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final mood = ref.watch(wtmMoodProvider);
            final zone = WtmMoodZone.of(mood);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WtmSlider(
                  value: mood,
                  onChanged: ref.read(wtmMoodProvider.notifier).preview,
                  onChangeEnd: ref.read(wtmMoodProvider.notifier).commit,
                  fill: false,
                  height: 4,
                  semanticLabel: l10n.wtmMoodEyebrow,
                  trackGradient: const LinearGradient(
                    colors: [
                      Color(0xFF6F86D6),
                      Color(0xFF9B7BE8),
                      Color(0xFFC77DFF),
                      Color(0xFFF3A0C8),
                    ],
                    stops: [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
                const SizedBox(height: WtmSpace.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final z in WtmMoodZone.values)
                      Text(
                        wtmMoodZoneLabel(l10n, z),
                        style: z == zone
                            ? WtmType.micro.copyWith(color: WtmColors.gold)
                            : WtmType.micro,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// What the stylist is styling around right now — daypart (device clock) plus
  /// the REAL local weather reading (or an honest "unavailable" line).
  Future<void> _showContextSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final country = Localizations.localeOf(context).countryCode;
    return showWtmSheet(
      context,
      title: l10n.wtmStylistContextTitle,
      subtitle: l10n.wtmStylistContextBody,
      children: [
        WtmRow(
          glyph: WtmGlyph.sparkle,
          title: l10n.wtmStylistContextDaypart,
          trailing: Text(wtmDaypart(l10n),
              style: WtmType.micro.copyWith(color: WtmColors.gold)),
        ),
        const SizedBox(height: 9),
        Consumer(
          builder: (context, ref, _) {
            final weather = ref.watch(weatherControllerProvider);
            final value = switch (weather) {
              WeatherReady(:final info) => l10n.wtmWeatherLabel(
                  formatTemp(info.snapshot.tempC, countryCode: country),
                  info.snapshot.condition,
                ),
              WeatherLoading() => l10n.wtmWeatherLoading,
              _ => l10n.wtmWeatherUnavailableChip,
            };
            return WtmRow(
              glyph: WtmGlyph.image,
              title: l10n.wtmStylistContextWeather,
              trailing: Text(value,
                  style: WtmType.micro.copyWith(color: WtmColors.gold)),
              onTap: () {
                Navigator.of(context).pop();
                showWtmWeatherSheet(context, ref);
              },
            );
          },
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(
          l10n.wtmStylistContextWeatherNote,
          textAlign: TextAlign.center,
          style: WtmType.micro.copyWith(height: 1.5),
        ),
      ],
    );
  }
}

/// Compact "how long ago" for the last weather fetch (e.g. "now", "5m", "2h").
String _weatherUpdatedAgo(AppLocalizations l10n, DateTime fetchedAt) {
  final d = DateTime.now().difference(fetchedAt);
  if (d.inMinutes < 1) return l10n.wtmTimeNow;
  if (d.inMinutes < 60) return l10n.wtmTimeMinutes(d.inMinutes);
  if (d.inHours < 24) return l10n.wtmTimeHours(d.inHours);
  return l10n.wtmTimeDays(d.inDays);
}

/// The local-weather sheet: the real current reading (temp · condition · feels
/// like · hi/lo · rain · location · last-updated) with honest states, plus the
/// location actions (use my location / choose a city / refresh, §2/§20).
Future<void> showWtmWeatherSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  return showWtmSheet(
    context,
    title: l10n.wtmWeatherSheetTitle,
    subtitle: l10n.wtmWeatherSheetSubtitle,
    children: const [_WeatherSheetBody()],
  );
}

class _WeatherSheetBody extends ConsumerWidget {
  const _WeatherSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final country = Localizations.localeOf(context).countryCode;
    final weather = ref.watch(weatherControllerProvider);
    final controller = ref.read(weatherControllerProvider.notifier);

    Future<void> chooseCity() async {
      final place = await _showWeatherCityPicker(context, ref);
      if (place != null) await controller.setCity(place);
    }

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: WtmSpace.s12),
        GhostButton(
          label: l10n.wtmWeatherUseLocation,
          icon: const WtmIcon(WtmGlyph.image, size: 15, color: WtmColors.text),
          onPressed: controller.useDeviceLocation,
        ),
        const SizedBox(height: 9),
        GhostButton(
          label: l10n.wtmWeatherChooseCity,
          icon: const WtmIcon(WtmGlyph.search, size: 15, color: WtmColors.text),
          onPressed: chooseCity,
        ),
      ],
    );

    switch (weather) {
      case WeatherLoading():
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: WtmSpace.s16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: WtmColors.gold),
            ),
          ),
        );
      case WeatherNeedsLocation():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.wtmWeatherNeedsLocationTitle, style: WtmType.h2.copyWith(fontSize: 16)),
            const SizedBox(height: 6),
            Text(l10n.wtmWeatherNeedsLocationBody, style: WtmType.micro),
            actions,
          ],
        );
      case WeatherUnavailable():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.wtmWeatherUnavailableTitle, style: WtmType.h2.copyWith(fontSize: 16)),
            const SizedBox(height: 6),
            Text(l10n.wtmWeatherUnavailableBody, style: WtmType.micro),
            const SizedBox(height: WtmSpace.s12),
            GradientCta(
              label: l10n.wtmWeatherRefresh,
              icon: const WtmIcon(WtmGlyph.sparkle, size: 15, color: WtmColors.ctaText),
              onPressed: controller.refresh,
            ),
            actions,
          ],
        );
      case WeatherReady(:final info):
        final snap = info.snapshot;
        String t(double c) => formatTemp(c, countryCode: country);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const WtmIcon(WtmGlyph.image, size: 18, color: WtmColors.gold),
                const SizedBox(width: WtmSpace.s10),
                Text(t(snap.tempC), style: WtmType.h1.copyWith(fontSize: 26)),
                const SizedBox(width: WtmSpace.s8),
                Expanded(
                  child: Text(snap.condition, style: WtmType.label),
                ),
              ],
            ),
            const SizedBox(height: WtmSpace.s10),
            Text(
              info.cityLabel ?? l10n.wtmWeatherCurrentLocation,
              style: WtmType.micro.copyWith(color: WtmColors.gold),
            ),
            const SizedBox(height: 4),
            if (snap.feelsLikeC != null)
              Text(l10n.wtmWeatherFeelsLike(t(snap.feelsLikeC!)), style: WtmType.micro),
            if (snap.tempMaxC != null && snap.tempMinC != null)
              Text(l10n.wtmWeatherHiLo(t(snap.tempMaxC!), t(snap.tempMinC!)),
                  style: WtmType.micro),
            if (snap.precipitationChance != null)
              Text(l10n.wtmWeatherRain(snap.precipitationChance!), style: WtmType.micro),
            const SizedBox(height: 4),
            Text(
              l10n.wtmWeatherUpdated(_weatherUpdatedAgo(l10n, info.fetchedAt)),
              style: WtmType.micro.copyWith(color: WtmColors.faint),
            ),
            const SizedBox(height: WtmSpace.s12),
            GradientCta(
              label: l10n.wtmWeatherRefresh,
              icon: const WtmIcon(WtmGlyph.sparkle, size: 15, color: WtmColors.ctaText),
              onPressed: controller.refresh,
            ),
            actions,
          ],
        );
    }
  }
}

/// City search sheet (manual-city fallback, §20). Returns the chosen [GeoPlace].
Future<GeoPlace?> _showWeatherCityPicker(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  GeoPlace? chosen;
  return showWtmSheet(
    context,
    title: l10n.wtmWeatherCityTitle,
    children: [
      _WeatherCityPicker(onPick: (place) {
        chosen = place;
        Navigator.of(context).pop();
      }),
    ],
  ).then((_) => chosen);
}

class _WeatherCityPicker extends ConsumerStatefulWidget {
  const _WeatherCityPicker({required this.onPick});

  final void Function(GeoPlace) onPick;

  @override
  ConsumerState<_WeatherCityPicker> createState() => _WeatherCityPickerState();
}

class _WeatherCityPickerState extends ConsumerState<_WeatherCityPicker> {
  final _controller = TextEditingController();
  List<GeoPlace> _results = const [];
  bool _searching = false;
  bool _error = false;
  int _query = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    final token = ++_query;
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = false;
    });
    try {
      final results =
          await ref.read(weatherControllerProvider.notifier).searchCity(query);
      if (!mounted || token != _query) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || token != _query) return;
      setState(() {
        _searching = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          style: WtmType.body,
          cursorColor: WtmColors.gold,
          textInputAction: TextInputAction.search,
          onChanged: _search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: l10n.wtmWeatherCityHint,
            hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
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
        if (_searching)
          Text(l10n.wtmWeatherCitySearching, style: WtmType.micro)
        else if (_error)
          Text(l10n.wtmWeatherCityError, style: WtmType.micro)
        else if (_controller.text.trim().length >= 2 && _results.isEmpty)
          Text(l10n.wtmWeatherCityEmpty, style: WtmType.micro)
        else
          for (final (i, place) in _results.indexed) ...[
            if (i > 0) const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.image,
              title: place.label,
              onTap: () => widget.onPick(place),
            ),
          ],
      ],
    );
  }
}
