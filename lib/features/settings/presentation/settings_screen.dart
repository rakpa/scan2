import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// True when shown as a tab inside the shell, which supplies its own
  /// scaffold and bottom bar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: embedded ? Colors.transparent : null,
      appBar: embedded ? null : AppBar(title: const Text('Settings')),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, embedded ? 140 : 32),
          children: [
            if (embedded)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text('Settings', style: BrandType.headline),
              ),

            const _SectionLabel('Scanning'),
            _Group(
              children: [
                _SwitchRow(
                  icon: Icons.document_scanner_outlined,
                  title: 'Use the in-app camera',
                  subtitle:
                      'Off uses the system scanner, which finds edges '
                      'best. On adds a live overlay and batch strip.',
                  value: settings.useInAppCamera,
                  onChanged: notifier.setUseInAppCamera,
                ),
                _SwitchRow(
                  icon: Icons.motion_photos_auto_outlined,
                  title: 'Auto-capture',
                  subtitle: 'Shoots once the page is steady.',
                  value: settings.autoCapture,
                  // Only meaningful for the in-app camera.
                  onChanged: settings.useInAppCamera
                      ? notifier.setAutoCapture
                      : null,
                ),
                _SwitchRow(
                  icon: Icons.volume_up_outlined,
                  title: 'Shutter sound',
                  value: settings.shutterSound,
                  onChanged: settings.useInAppCamera
                      ? notifier.setShutterSound
                      : null,
                  last: true,
                ),
              ],
            ),

            const _SectionLabel('Default enhancement'),
            _Group(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    'Applied to new scans. Change it per page any time.',
                    style: BrandType.caption,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in ScanFilter.values)
                        ChoiceChip(
                          label: Text(ImageProcessor.labelFor(filter)),
                          selected: settings.defaultFilter == filter,
                          onSelected: (_) => notifier.setDefaultFilter(filter),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const _SectionLabel('Appearance'),
            _Group(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined, size: 17),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined, size: 17),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) =>
                        notifier.setThemeMode(selection.first),
                  ),
                ),
              ],
            ),

            const _SectionLabel('About'),
            _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('Everything stays on your device'),
                  subtitle: const Text('No accounts, no uploads.'),
                  dense: true,
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About Scan2'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Scan2',
                    applicationVersion: '1.0.2',
                    applicationLegalese:
                        'Scans stay on your device. Nothing is uploaded.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet section label. Loud coloured headings make a settings list look
/// like a form; these should recede and let the groups do the structuring.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
      child: Text(label, style: BrandType.caption),
    );
  }
}

/// Rows grouped into one rounded surface, the shape people expect settings to
/// take on a phone.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.outline),
      ),
      child: Column(children: children),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final text = subtitle;

    return Column(
      children: [
        SwitchListTile(
          value: value,
          onChanged: onChanged,
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          secondary: Icon(
            icon,
            size: 22,
            color: enabled ? Brand.blue : Brand.greyLight,
          ),
          title: Text(title, style: BrandType.title),
          subtitle: text == null
              ? null
              : Text(
                  text,
                  style: BrandType.caption,
                ),
        ),
        if (!last) const Divider(indent: 56, endIndent: 12),
      ],
    );
  }
}
