import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Appearance'),
            dense: true,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => notifier.setThemeMode(s.first),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Auto-detect edges'),
            subtitle: const Text('Live edge guides and auto-capture when steady'),
            value: settings.autoDetectEdges,
            onChanged: notifier.setAutoDetectEdges,
          ),
          SwitchListTile(
            title: const Text('Enhance by default'),
            subtitle: const Text('Apply Magic filter on new pages'),
            value: settings.enhanceByDefault,
            onChanged: notifier.setEnhanceByDefault,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Scan2'),
            subtitle: const Text('Offline document scanner • v1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Scan2',
                applicationVersion: '1.0.0',
                applicationLegalese: 'Original branding. Fully offline.',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: const Text('Back to library'),
            onTap: () => context.go('/library'),
          ),
        ],
      ),
    );
  }
}
