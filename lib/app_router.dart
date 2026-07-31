import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/camera/presentation/camera_screen.dart';
import 'package:scan2/features/library/presentation/library_screen.dart';
import 'package:scan2/features/library/presentation/document_detail_screen.dart';
import 'package:scan2/features/crop/presentation/crop_screen.dart';
import 'package:scan2/features/settings/presentation/settings_screen.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingCompleted = ref.watch(onboardingCompletedProvider);

  return GoRouter(
    initialLocation: onboardingCompleted ? '/library' : '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/library',
        builder: (context, state) => const LibraryScreen(),
        routes: [
          GoRoute(
            path: 'document/:id',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return DocumentDetailScreen(documentId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/camera',
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: '/crop',
        builder: (context, state) {
          final extra = state.extra;
          final imagePath = extra is String ? extra : null;
          final pageId = extra is int ? extra : null;
          return CropScreen(pageId: pageId, imagePath: imagePath);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome to Scan2', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Smart offline document scanner'),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                ref.read(onboardingCompletedProvider.notifier).complete();
                context.go('/library');
              },
              child: const Text('Get Started'),
            ),
          ],
        ),
      ),
    );
  }
}