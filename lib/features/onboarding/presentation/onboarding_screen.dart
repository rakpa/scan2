import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  static const _points = [
    (
      icon: Icons.crop_free,
      title: 'Finds the page',
      body:
          'Edges are detected live, so the guide sits on the document '
          'rather than on a fixed frame.',
    ),
    (
      icon: Icons.motion_photos_auto_outlined,
      title: 'Shoots when you are steady',
      body:
          'Hold still and Scan2 takes the shot — no blurred pages from '
          'tapping the shutter.',
    ),
    (
      icon: Icons.auto_fix_high,
      title: 'Cleans it up',
      body:
          'Pages are straightened and enhanced automatically, and stay '
          'editable afterwards.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.document_scanner,
                size: 52,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text('Scan2', style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'A document scanner that works entirely on your device.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 36),
              for (final point in _points) ...[
                _Point(icon: point.icon, title: point.title, body: point.body),
                const SizedBox(height: 22),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      ref.read(onboardingCompletedProvider.notifier).complete(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Start scanning'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
