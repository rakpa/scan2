import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader('Scanning'),
          SwitchListTile(
            secondary: const Icon(Icons.motion_photos_auto_outlined),
            title: const Text('Auto-capture'),
            subtitle: const Text(
              'Take the shot automatically once the page is in frame '
              'and the phone is steady.',
            ),
            value: settings.autoCapture,
            onChanged: notifier.setAutoCapture,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Shutter sound'),
            value: settings.shutterSound,
            onChanged: notifier.setShutterSound,
          ),
          const Divider(height: 32),

          _SectionHeader('Enhancement'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Applied to new scans. You can change it per page afterwards.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final filter in ScanFilter.values)
                  ChoiceChip(
                    label: Text(ImageProcessor.labelFor(filter)),
                    selected: settings.defaultFilter == filter,
                    showCheckmark: false,
                    onSelected: (_) => notifier.setDefaultFilter(filter),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),

          _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  notifier.setThemeMode(selection.first),
            ),
          ),
          const Divider(height: 32),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Scan2'),
            subtitle: const Text('Offline document scanner'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Scan2',
              applicationVersion: '1.0.1',
              applicationLegalese:
                  'Scans stay on your device. Nothing is uploaded.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
