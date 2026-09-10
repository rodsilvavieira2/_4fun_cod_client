import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../updates/app_update_state.dart';
import '../../updates/update_config.dart';
import '../../updates/update_providers.dart';
import '../settings_section_layout.dart';
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
        SettingsStack(
          children: [
            SettingsGroup(
              title: 'Status',
              children: [
                SettingsRow(
                  icon: Icons.inventory_2_outlined,
                  title: 'Versão instalada',
                  trailing: SizedBox(
                    width: 150,
                    child: SettingsValueText(
                      backend.currentVersion ?? '…',
                      monospace: true,
                    ),
                  ),
                ),
                SettingsRow(
                  icon: Icons.cloud_download_outlined,
                  title: 'Última disponível',
                  trailing: SizedBox(
                    width: 150,
                    child: SettingsValueText(
                      backend.latestVersion ?? '—',
                      monospace: true,
                    ),
                  ),
                ),
                SettingsRow(
                  icon: Icons.info_outline,
                  title: 'Estado',
                  trailing: AppBadge(
                    label: _statusLabel(status, backend),
                    variant: _statusVariant(status),
                  ),
                ),
              ],
            ),
            if (status == AppUpdateStatus.failed &&
                backend.errorMessage != null)
              SettingsNotice(
                message: backend.errorMessage!,
                tone: SettingsNoticeTone.danger,
              ),
            if (status == AppUpdateStatus.upToDate && backend.manualUpToDate)
              const SettingsNotice(
                message: 'Você já está na última versão.',
                tone: SettingsNoticeTone.success,
              ),
            SettingsGroup(
              title: 'Ações',
              children: [
                if (backend.isSupported)
                  SettingsRow(
                    icon: Icons.sync_outlined,
                    title: 'Verificar atualizações',
                    trailing: AppButton(
                      label: 'Verificar',
                      icon: Icons.refresh,
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.secondary,
                      onPressed: status == AppUpdateStatus.checking
                          ? null
                          : () => _run(context, backend, () async {
                              await backend.checkForUpdates();
                            }),
                    ),
                  ),
                if (backend.isSupported &&
                    status == AppUpdateStatus.available &&
                    !backend.isDismissed)
                  SettingsRow(
                    icon: Icons.download_outlined,
                    title: 'Atualização disponível',
                    trailing: AppButton(
                      label: 'Baixar',
                      icon: Icons.download_outlined,
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.accent,
                      onPressed: () =>
                          _run(context, backend, backend.downloadUpdate),
                    ),
                  ),
                if (backend.isSupported &&
                    status == AppUpdateStatus.readyToInstall)
                  SettingsRow(
                    icon: Icons.restart_alt,
                    title: 'Instalação pronta',
                    trailing: AppButton(
                      label: 'Reiniciar',
                      icon: Icons.restart_alt,
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.accent,
                      onPressed: () =>
                          _run(context, backend, backend.restartToInstall),
                    ),
                  ),
                SettingsRow(
                  icon: Icons.link_outlined,
                  title: 'Link de download',
                  trailing: AppButton(
                    label: 'Copiar',
                    icon: Icons.copy,
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
                ),
              ],
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

  static AppBadgeVariant _statusVariant(AppUpdateStatus status) {
    return switch (status) {
      AppUpdateStatus.upToDate => AppBadgeVariant.success,
      AppUpdateStatus.available ||
      AppUpdateStatus.downloading ||
      AppUpdateStatus.readyToInstall => AppBadgeVariant.accent,
      AppUpdateStatus.failed => AppBadgeVariant.danger,
      AppUpdateStatus.unconfigured => AppBadgeVariant.warning,
      AppUpdateStatus.idle ||
      AppUpdateStatus.checking => AppBadgeVariant.neutral,
    };
  }
}
