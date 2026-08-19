import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/camera/presentation/camera_screen.dart';
import 'package:scan2/features/camera/presentation/native_scan_screen.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/crop/presentation/crop_screen.dart';
import 'package:scan2/features/library/presentation/document_detail_screen.dart';
import 'package:scan2/features/home/presentation/home_shell.dart';
import 'package:scan2/features/onboarding/presentation/onboarding_screen.dart';
import 'package:scan2/features/settings/presentation/settings_screen.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/library',
    redirect: (context, state) {
      // Read rather than watch: rebuilding the router mid-navigation would
      // drop the current route stack.
      final completed = ref.read(onboardingCompletedProvider);
      final onOnboarding = state.matchedLocation == '/onboarding';
      if (!completed && !onOnboarding) return '/onboarding';
      if (completed && onOnboarding) return '/library';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/library',
        builder: (context, state) => const HomeShell(),
        routes: [
          GoRoute(
            path: 'document/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const _RouteError(message: 'Bad document');
              return DocumentDetailScreen(documentId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/camera',
        builder: (context, state) {
          // The platform scanner is the default capture path; the in-app
          // camera is opt-in from Settings.
          final inApp = ref.read(settingsProvider).useInAppCamera;
          return inApp ? const CameraScreen() : const NativeScanScreen();
        },
      ),
      GoRoute(
        path: '/crop',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is CropArgs) return CropScreen.fromArgs(extra);
          if (extra is String) return CropScreen(imagePath: extra);
          return const _RouteError(message: 'Nothing to edit');
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        _RouteError(message: 'Page not found: ${state.uri}'),
  );

  // Re-evaluate the onboarding redirect when it completes.
  ref.listen<bool>(onboardingCompletedProvider, (_, __) {
    router.refresh();
  });
  ref.onDispose(router.dispose);
  return router;
});

class _RouteError extends StatelessWidget {
  const _RouteError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go('/library'),
                child: const Text('Back to library'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
