import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/app_router.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Scanning is a portrait, two-handed activity; letting the shell rotate
  // mid-capture only fights the user.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const Scan2Root());
}

class Scan2Root extends StatelessWidget {
  const Scan2Root({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: Scan2App());
  }
}

class Scan2App extends ConsumerWidget {
  const Scan2App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Scan2',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(settingsProvider.select((s) => s.themeMode)),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
