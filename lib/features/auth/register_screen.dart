import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/ui/ui.dart';
import '../../core/ui/web_input.dart';

/// Tela de cadastro estilo Vercel / macOS.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static final _usernameRegex = RegExp(r'^[a-z0-9_]{3,20}$');

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).register(
            name: _nameController.text.trim(),
            username: _usernameController.text.trim().toLowerCase(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
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
              constraints: const BoxConstraints(maxWidth: 400),
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
                        'Criar conta',
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
                        'Junte-se ao 4fun_cod',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppTextField(
                        controller: _nameController,
                        label: 'NOME COMPLETO',
                        hintText: 'Seu nome',
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Informe seu nome.' : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _usernameController,
                        label: 'USERNAME',
                        hintText: 'usuario123',
                        validator: (value) {
                          final username = value?.trim().toLowerCase() ?? '';
                          if (!_usernameRegex.hasMatch(username)) {
                            return '3-20 caracteres: a-z, 0-9 e _';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _emailController,
                        label: 'E-MAIL',
                        hintText: 'seu@email.com',
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: webAutofillHints(const [AutofillHints.email]),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Informe seu e-mail.';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                            return 'E-mail inválido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _passwordController,
                        label: 'SENHA',
                        hintText: 'Mínimo 8 caracteres',
                        obscureText: true,
                        autofillHints: webAutofillHints(const [AutofillHints.newPassword]),
                        validator: (value) =>
                            (value == null || value.length < 8) ? 'Mínimo 8 caracteres.' : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _confirmPasswordController,
                        label: 'CONFIRMAR SENHA',
                        hintText: 'Repita a senha',
                        obscureText: true,
                        validator: (value) => value != _passwordController.text
                            ? 'As senhas não coincidem.'
                            : null,
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
                        label: 'Cadastrar',
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.lg,
                        expanded: true,
                        loading: _submitting,
                        onPressed: _submitting ? null : _submit,
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'Já tenho uma conta — entrar',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.md,
                        expanded: true,
                        onPressed: _submitting ? null : () => context.go('/login'),
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
}
