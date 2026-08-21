import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/camera/presentation/camera_screen.dart';
import 'package:scan2/features/camera/presentation/native_scan_screen.dart';
import 'package:scan2/features/crop/domain/crop_args.dart';
import 'package:scan2/features/crop/presentation/crop_screen.dart';
import 'package:scan2/features/scan/domain/scan_result_args.dart';
import 'package:scan2/features/scan/presentation/document_saved_screen.dart';
import 'package:scan2/features/scan/presentation/scan_result_screen.dart';
import 'package:scan2/features/library/presentation/document_detail_screen.dart';
import 'package:scan2/features/library/domain/library_launch.dart';
import 'package:scan2/features/home/presentation/home_shell.dart';
import 'package:scan2/features/auth/domain/auth_controller.dart';
import 'package:scan2/features/auth/presentation/create_account_screen.dart';
import 'package:scan2/features/auth/presentation/login_screen.dart';
import 'package:scan2/features/onboarding/presentation/onboarding_screen.dart';
import 'package:scan2/features/onboarding/presentation/welcome_screen.dart';
import 'package:scan2/features/settings/presentation/settings_screen.dart';
import 'package:scan2/features/shared/providers/onboarding_provider.dart';
import 'package:scan2/features/shared/providers/settings_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/welcome',
    redirect: (context, state) {
      // Read rather than watch: rebuilding the router mid-navigation would
      // drop the current route stack.
      final seenIntro = ref.read(onboardingCompletedProvider);
      final signedIn = ref.read(authProvider).signedIn;
      final location = state.matchedLocation;

      const intro = {'/welcome', '/onboarding'};
      const auth = {'/signup', '/login'};

      // First run: welcome, then the three intro pages.
      if (!seenIntro) {
        return intro.contains(location) ? null : '/welcome';
      }
      // Intro done but no account chosen yet: sign up or log in.
      if (!signedIn) {
        if (location == '/welcome') return null;
        return auth.contains(location) ? null : '/signup';
      }
      // Cold start still plays the white splash, then WelcomeScreen
      // continues into the library.
      if (location == '/welcome') return null;
      // Signed in (or continuing without an account): the intro and auth
      // screens are behind us.
      if (intro.contains(location) || auth.contains(location)) {
        return '/library';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const CreateAccountScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/library',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is LibraryLaunch) {
            return HomeShell(
              initialTab: extra.tab,
              highlightDocumentId: extra.highlightDocumentId,
            );
          }
          return const HomeShell();
        },
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
          // camera is opt-in from Settings. Screen 9 briefly always opened
          // CameraScreen, which skipped VisionKit / ML Kit auto-edge.
          final inApp = ref.read(settingsProvider).useInAppCamera;
          return inApp ? const CameraScreen() : const NativeScanScreen();
        },
      ),
      GoRoute(
        path: '/system-scan',
        builder: (context, state) => const NativeScanScreen(),
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
        path: '/scan-result',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is ScanResultArgs) return ScanResultScreen(args: extra);
          return const _RouteError(message: 'Nothing to review');
        },
      ),
      GoRoute(
        path: '/saved/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null) return const _RouteError(message: 'Bad document');
          return DocumentSavedScreen(documentId: id);
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

  // Re-evaluate the gate whenever the intro finishes or the account changes.
  ref.listen<bool>(onboardingCompletedProvider, (_, __) => router.refresh());
  ref.listen<AuthState>(authProvider, (_, __) => router.refresh());
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
