import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/auth/domain/auth_controller.dart';
import 'package:scan2/features/auth/presentation/widgets/auth_nav_bar.dart';
import 'package:scan2/features/auth/presentation/widgets/social_row.dart';
import 'package:scan2/features/onboarding/presentation/welcome_screen.dart';

/// Screen 4 — Create Account.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreed = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_agreed) {
      _message('Please accept the Terms of Use to continue.');
      return;
    }

    setState(() => _busy = true);
    await ref
        .read(authProvider.notifier)
        .signUp(name: _name.text.trim(), email: _email.text.trim());
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
            const AuthNavBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const ScanellaAppMark(size: 76),
                      const SizedBox(height: 12),
                      const ScanellaWordmark(),
                      const SizedBox(height: 4),
                      const Text(
                        'Scan. Save. Simplify.',
                        style: BrandType.subtitle,
                      ),
                      const SizedBox(height: 22),
                      const Text('Create Account', style: BrandType.display),
                      const SizedBox(height: 8),
                      const Text(
                        'Join Scanella to scan, save and access\n'
                        'your documents anywhere.',
                        textAlign: TextAlign.center,
                        style: BrandType.subtitle,
                      ),
                      const SizedBox(height: 24),
                      BrandField(
                        hint: 'Full Name',
                        icon: Icons.person_rounded,
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        validator: AuthValidators.name,
                        autofillHints: const [AutofillHints.name],
                      ),
                      const SizedBox(height: 14),
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
                        obscure: _obscurePassword,
                        validator: AuthValidators.password,
                        trailing: _EyeToggle(
                          obscured: _obscurePassword,
                          onTap: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      BrandField(
                        hint: 'Confirm Password',
                        icon: Icons.lock_rounded,
                        controller: _confirm,
                        obscure: _obscureConfirm,
                        validator: (value) => value == _password.text
                            ? null
                            : 'Passwords do not match',
                        trailing: _EyeToggle(
                          obscured: _obscureConfirm,
                          onTap: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _TermsRow(
                        value: _agreed,
                        onChanged: (value) =>
                            setState(() => _agreed = value ?? false),
                      ),
                      const SizedBox(height: 20),
                      BrandButton(
                        label: 'Create Account',
                        showArrow: false,
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 22),
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
                        child: Text(
                          'Continue without an account',
                          style: BrandType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      AuthFooterPrompt(
                        prompt: 'Already have an account?',
                        action: 'Login',
                        onTap: () => context.go('/login'),
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

class _EyeToggle extends StatelessWidget {
  const _EyeToggle({required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 21,
        color: Brand.greyLight,
      ),
    );
  }
}

class _TermsRow extends StatelessWidget {
  const _TermsRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Brand.blue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: const TextSpan(
              style: BrandType.caption,
              children: [
                TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Terms of Use',
                  style: TextStyle(
                    color: Brand.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(
                    color: Brand.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
