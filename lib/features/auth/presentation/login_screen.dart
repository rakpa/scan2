import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/auth/domain/auth_controller.dart';
import 'package:scan2/features/auth/presentation/widgets/social_row.dart';
import 'package:scan2/features/onboarding/presentation/welcome_screen.dart';

/// Screen 5 — Login.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _remember = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the last account used on this device.
    _email.text = ref.read(authProvider).email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    await ref.read(authProvider.notifier).signIn(email: _email.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    context.go('/library');
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  size: 32,
                  color: Brand.blue,
                ),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/welcome'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const ScanellaAppMark(size: 88),
                      const SizedBox(height: 14),
                      const ScanellaWordmark(fontSize: 40),
                      const SizedBox(height: 4),
                      const Text(
                        'Scan. Save. Simplify.',
                        style: TextStyle(fontSize: 16, color: Brand.grey),
                      ),
                      const SizedBox(height: 34),
                      const Text(
                        'Welcome Back!',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: Brand.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Login to continue to your account',
                        style: TextStyle(fontSize: 15, color: Brand.grey),
                      ),
                      const SizedBox(height: 28),
                      BrandField(
                        hint: 'Email Address',
                        icon: Icons.mail_rounded,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        validator: AuthValidators.email,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 14),
                      BrandField(
                        hint: 'Password',
                        icon: Icons.lock_rounded,
                        controller: _password,
                        obscure: _obscure,
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Enter your password'
                            : null,
                        trailing: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 21,
                            color: Brand.greyLight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: Checkbox(
                              value: _remember,
                              activeColor: Brand.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              onChanged: (value) =>
                                  setState(() => _remember = value ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Remember me',
                            style: TextStyle(fontSize: 15, color: Brand.ink),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _message(
                              'Password reset needs an account server, '
                              'which is not connected yet.',
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontSize: 15,
                                color: Brand.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      BrandButton(
                        label: 'Login',
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 24),
                      SocialSignInRow(
                        onUnavailable: (provider) =>
                            _message('$provider sign-in is not connected yet.'),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(authProvider.notifier)
                              .continueWithoutAccount();
                          if (context.mounted) context.go('/library');
                        },
                        child: const Text(
                          'Continue without an account',
                          style: TextStyle(
                            color: Brand.grey,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      AuthFooterPrompt(
                        prompt: "Don't have an account?",
                        action: 'Sign Up',
                        onTap: () => context.go('/signup'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
