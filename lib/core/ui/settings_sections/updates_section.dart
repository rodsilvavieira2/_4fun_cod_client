import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../updates/app_update_state.dart';
import '../../updates/update_config.dart';
import '../../updates/update_providers.dart';
import '../ui.dart';

/// Seção Atualizações do modal: versão instalada, estado do feed e ações
/// manuais (verificar / baixar / reiniciar). Visível só no desktop
/// (a sidebar omite na web).
class UpdatesSection extends ConsumerWidget {
  const UpdatesSection({super.key});

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
    final backend = ref.watch(appUpdateBackendProvider);
    final status = backend.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('ATUALIZAÇÕES'),
        _Row(label: 'Versão instalada', value: backend.currentVersion ?? '…'),
        _Row(label: 'Última disponível', value: backend.latestVersion ?? '—'),
        _Row(label: 'Estado', value: _statusLabel(status, backend)),
        if (status == AppUpdateStatus.failed && backend.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              backend.errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.accentDanger),
            ),
          ),
        if (status == AppUpdateStatus.upToDate && backend.manualUpToDate)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Você já está na última versão.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTokens.accentGreen),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (backend.isSupported) ...[
              AppButton(
                label: 'Verificar atualizações',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.secondary,
                onPressed: status == AppUpdateStatus.checking
                    ? null
                    : () => _run(context, backend, () async {
                        await backend.checkForUpdates();
                      }),
              ),
              if (status == AppUpdateStatus.available && !backend.isDismissed)
                AppButton(
                  label: 'Baixar',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.accent,
                  onPressed: () =>
                      _run(context, backend, backend.downloadUpdate),
                ),
              if (status == AppUpdateStatus.readyToInstall)
                AppButton(
                  label: 'Reiniciar para instalar',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.accent,
                  onPressed: () =>
                      _run(context, backend, backend.restartToInstall),
                ),
            ],
            AppButton(
              label: 'Copiar link de download',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: updateReleasesPageUrl),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copiado.')),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  static String _statusLabel(AppUpdateStatus status, AppUpdateBackend backend) {
    return switch (status) {
      AppUpdateStatus.idle => '—',
      AppUpdateStatus.checking => 'Verificando…',
      AppUpdateStatus.available =>
        backend.isDismissed ? 'Disponível (adiada)' : 'Disponível',
      AppUpdateStatus.downloading =>
        backend.downloadProgress == null
            ? 'Baixando…'
            : 'Baixando… ${(backend.downloadProgress! * 100).round()}%',
      AppUpdateStatus.readyToInstall => 'Pronta para instalar',
      AppUpdateStatus.upToDate => 'Em dia',
      AppUpdateStatus.failed => 'Falhou',
      AppUpdateStatus.unconfigured => 'Não configurado',
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
