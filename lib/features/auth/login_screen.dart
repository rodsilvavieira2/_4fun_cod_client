import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/ui/ui.dart';
import '../../core/ui/web_input.dart';

/// Tela de login estilo Vercel / macOS (e-mail/senha → sessão no backend).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? get _redirectTarget {
    final raw = GoRouterState.of(context).uri.queryParameters['redirect'];
    if (raw == null || !raw.startsWith('/') || raw.startsWith('//')) {
      return null;
    }
    return raw;
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      final redirect = _redirectTarget;
      if (mounted && redirect != null) {
        context.go(redirect);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AppCard(
                padding: const EdgeInsets.all(32),
                backgroundColor: AppTokens.surface1,
                borderColor: AppTokens.borderStrong,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTokens.textPrimary,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.terminal,
                            color: AppTokens.textInverse,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '4fun_cod',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: AppTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Entre na sua conta para continuar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppTextField(
                        controller: _emailController,
                        label: 'E-mail',
                        hintText: 'seu@email.com',
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: webAutofillHints(const [AutofillHints.email]),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _passwordController,
                        label: 'Senha',
                        hintText: '••••••••',
                        obscureText: true,
                        autofillHints: webAutofillHints(const [AutofillHints.password]),
                        validator: (value) =>
                            (value == null || value.isEmpty) ? 'Informe sua senha.' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12.5,
                            color: AppTokens.accentPurple,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      AppButton(
                        label: 'Entrar',
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.lg,
                        expanded: true,
                        loading: _submitting,
                        onPressed: _submitting ? null : _submit,
                      ),
                      const SizedBox(height: 14),
                      AppButton(
                        label: 'Criar conta',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.md,
                        expanded: true,
                        onPressed: _submitting ? null : () => context.go('/register'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Informe seu e-mail.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'E-mail inválido.';
    }
    return null;
  }
}
