import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/karen_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class KarenNextApp extends ConsumerStatefulWidget {
  final bool useGoogleFonts;

  const KarenNextApp({super.key, this.useGoogleFonts = true});

  @override
  ConsumerState<KarenNextApp> createState() => _KarenNextAppState();
}

class _KarenNextAppState extends ConsumerState<KarenNextApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Immediately re-lock when moving to background/hidden if PIN lock is enabled.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(karenControllerProvider.notifier).lockApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(
      karenControllerProvider.select((s) => s.settings.themeMode),
    );

    return MaterialApp.router(
      title: 'کارن الکترونیک',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(useGoogleFonts: widget.useGoogleFonts),
      darkTheme: AppTheme.dark(useGoogleFonts: widget.useGoogleFonts),
      themeMode: themeMode,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [
        Locale('fa', 'IR'),
        Locale('en', 'US'),
      ],
      // material_ui exports the Material delegates, which include the
      // Cupertino and Widgets delegates as well.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}
