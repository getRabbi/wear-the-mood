import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push/push_messaging.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

/// Root application widget. Drives theme, localization, and routing, and (when
/// [enablePush]) starts FCM push registration after the first frame. Push is off
/// by default so widget tests never touch Firebase.
class FashionOsApp extends ConsumerStatefulWidget {
  const FashionOsApp({super.key, this.enablePush = false});

  final bool enablePush;

  @override
  ConsumerState<FashionOsApp> createState() => _FashionOsAppState();
}

class _FashionOsAppState extends ConsumerState<FashionOsApp> {
  @override
  void initState() {
    super.initState();
    if (widget.enablePush) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(pushMessagingProvider).start();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
