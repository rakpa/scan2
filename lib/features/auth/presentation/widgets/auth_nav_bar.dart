import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/auth/domain/auth_controller.dart';

/// Back on the left, Skip on the right — used by sign-in and create-account.
class AuthNavBar extends ConsumerWidget {
  const AuthNavBar({super.key});

  Future<void> _skip(BuildContext context, WidgetRef ref) async {
    await ref.read(authProvider.notifier).continueWithoutAccount();
    if (context.mounted) context.go('/library');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left_rounded,
              size: 32,
              color: Brand.blue,
            ),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/welcome'),
          ),
          const Spacer(),
          TextButton(
            key: const Key('auth-skip'),
            onPressed: () => _skip(context, ref),
              child: const Text('Skip', style: BrandType.link),
          ),
        ],
      ),
    );
  }
}
