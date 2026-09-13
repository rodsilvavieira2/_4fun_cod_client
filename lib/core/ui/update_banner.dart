import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../updates/app_update_state.dart';
import '../updates/update_providers.dart';
import 'buttons/app_button.dart';
import 'ds_tokens.dart';
import '../theme/appearance_theme.dart';

/// Toast de update (overlay, reutilizável): aparece só em
/// [AppUpdateStatus.available] (não dispensado), `.downloading` e
/// `.readyToInstall`. Demais estados = zero layout.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  Future<void> _run(
    BuildContext context,
    AppUpdateBackend backend,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(backend.errorMessage ?? 'Falha na atualização.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final backend = ref.watch(appUpdateBackendProvider);
    final status = backend.status;

    final Widget? body = switch (status) {
      AppUpdateStatus.available when !backend.isDismissed => _AvailableBody(
        backend: backend,
        onAction: _run,
      ),
      AppUpdateStatus.downloading => _DownloadingBody(backend: backend),
      AppUpdateStatus.readyToInstall => _ReadyBody(
        backend: backend,
        onAction: _run,
      ),
      _ => null,
    };
    if (body == null) return const SizedBox.shrink();

    return SizedBox(
      width: 360,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderSubtle, width: 1),
          boxShadow: AppShadows.popover,
        ),
        child: body,
      ),
    );
  }
}

class _AvailableBody extends StatelessWidget {
  const _AvailableBody({required this.backend, required this.onAction});

  final AppUpdateBackend backend;
  final Future<void> Function(
    BuildContext context,
    AppUpdateBackend backend,
    Future<void> Function(),
  )
  onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final version = backend.latestVersion ?? 'nova';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.system_update_alt, size: 18, color: colors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nova versão disponível ($version)',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Depois',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: backend.dismiss,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Atualizar',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.accent,
              onPressed: () =>
                  onAction(context, backend, backend.downloadUpdate),
            ),
          ],
        ),
      ],
    );
  }
}

class _DownloadingBody extends StatelessWidget {
  const _DownloadingBody({required this.backend});

  final AppUpdateBackend backend;

  @override
  Widget build(BuildContext context) {
    final progress = backend.downloadProgress;
    final label = progress == null
        ? 'Baixando atualização…'
        : 'Baixando atualização… ${(progress * 100).round()}%';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: progress),
      ],
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.backend, required this.onAction});

  final AppUpdateBackend backend;
  final Future<void> Function(
    BuildContext context,
    AppUpdateBackend backend,
    Future<void> Function(),
  )
  onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Atualização pronta para instalar',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'O app será reiniciado para concluir.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Depois',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: backend.dismiss,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Reiniciar agora',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.accent,
              onPressed: () =>
                  onAction(context, backend, backend.restartToInstall),
            ),
          ],
        ),
      ],
    );
  }
}
