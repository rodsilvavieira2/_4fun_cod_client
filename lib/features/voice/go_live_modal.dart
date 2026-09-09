import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/screen_share_picker.dart';
import 'package:fourfun_cod_client/core/ui/ds_tokens.dart';

/// Qualidade de transmissão do modal Go Live — só opções possíveis, cada chip
/// mapeia 1:1 para um [RtcScreenShareQuality] real (sem células desabilitadas).
enum GoLiveQuality { auto, high, medium, low }

/// Mapeamento chip → perfil de publicação (captura fixa em 1080p60; o perfil é
/// o teto de transmissão, não a resolução de captura).
RtcScreenShareQuality goLiveQualityFor(GoLiveQuality quality) =>
    switch (quality) {
      GoLiveQuality.auto => RtcScreenShareQuality.auto,
      GoLiveQuality.high => RtcScreenShareQuality.q1080p60,
      GoLiveQuality.medium => RtcScreenShareQuality.q1080p30,
      GoLiveQuality.low => RtcScreenShareQuality.q720p15,
    };

/// Chip inicial a partir do perfil pendente. Órfãos (`q1080p15`, `q360p3`,
/// acessíveis só pelo sheet) caem no chip mais próximo.
GoLiveQuality goLiveQualityFromPending(RtcScreenShareQuality pending) =>
    switch (pending) {
      RtcScreenShareQuality.auto => GoLiveQuality.auto,
      RtcScreenShareQuality.q1080p60 => GoLiveQuality.high,
      RtcScreenShareQuality.q1080p30 ||
      RtcScreenShareQuality.q1080p15 => GoLiveQuality.medium,
      RtcScreenShareQuality.q720p15 ||
      RtcScreenShareQuality.q360p3 => GoLiveQuality.low,
    };

/// Escolha confirmada no modal Go Live: tipo de fonte (+ fonte específica
/// pré-escolhida no Windows, quando houver), qualidade one-shot e se o áudio
/// de sistema vai junto (opt-out, default ligado).
class GoLiveResult {
  const GoLiveResult({
    required this.kind,
    required this.sourceId,
    required this.quality,
    required this.includeAudio,
  });

  final RtcScreenShareSourceKind kind;
  final String? sourceId;
  final GoLiveQuality quality;
  final bool includeAudio;
}

/// Modal "Go Live" na língua do modal de configurações ([AppTokens] +
/// Geist): shell `surface2` com blur macOS, raio xl, `borderSubtle` e sombra
/// [AppShadows.modalWindow]; seleção espelhada no `_SidebarItem`
/// (`surface3` + `borderSubtle`, sem preenchimento azul).
///
/// Fluxo: `Go Live` abre o seletor do tipo escolhido (Windows: thumbnails;
/// Linux: portal do sistema) e o chamador inicia com o retorno; cancelar em
/// qualquer etapa retorna null com o modal intacto. O modal nunca é fechado
/// antes do seletor, então a escolha one-shot não evapora.
Future<GoLiveResult?> showGoLiveModal(
  BuildContext context, {
  required NativeScreenShareBackend backend,
  required RtcScreenShareQuality pendingQuality,
  String? channelName,
}) {
  return showDialog<GoLiveResult>(
    context: context,
    builder: (context) => _GoLiveDialog(
      backend: backend,
      pendingQuality: pendingQuality,
      channelName: channelName,
    ),
  );
}

class _GoLiveDialog extends StatefulWidget {
  const _GoLiveDialog({
    required this.backend,
    required this.pendingQuality,
    required this.channelName,
  });

  final NativeScreenShareBackend backend;
  final RtcScreenShareQuality pendingQuality;
  final String? channelName;

  @override
  State<_GoLiveDialog> createState() => _GoLiveDialogState();
}

class _GoLiveDialogState extends State<_GoLiveDialog> {
  late RtcScreenShareSourceKind _kind = RtcScreenShareSourceKind.display;
  late GoLiveQuality _quality = goLiveQualityFromPending(widget.pendingQuality);
  RtcScreenShareSelection? _preselected;

  /// Opt-out do áudio de sistema: ligado por padrão (regra 1 da SPEC).
  bool _includeAudio = true;

  bool get _canUseKind => widget.backend.canUseKind(_kind);

  Future<void> _goLive() async {
    if (!_canUseKind) return;
    // Seletor do tipo escolhido abre POR CIMA do modal (stack, não replace):
    // cancelar nele volta para cá com tipo + qualidade intactos.
    final selection = await RtcScreenSharePicker.show(
      context,
      backend: widget.backend,
      initialKind: _kind,
    );
    if (!mounted || selection == null) return;
    Navigator.of(context).pop(
      GoLiveResult(
        kind: selection.kind,
        sourceId: selection.sourceId,
        quality: _quality,
        includeAudio: _includeAudio,
      ),
    );
  }

  Future<void> _chooseSource() async {
    final selection = await RtcScreenSharePicker.show(
      context,
      backend: widget.backend,
      initialKind: _kind,
    );
    if (!mounted) return;
    setState(() {
      if (selection != null) {
        _kind = selection.kind;
        _preselected = selection;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final channelName = widget.channelName;
    // Teto de 50% da largura disponível (piso 320, teto absoluto 560): sem o
    // widget Dialog, o Material expandiria para a tela toda.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = (screenWidth * 0.5).clamp(320.0, 560.0);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 20),
                decoration: BoxDecoration(
                  color: AppTokens.surface2.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppTokens.borderSubtle, width: 1),
                  boxShadow: AppShadows.modalWindow,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GoLiveHeader(
                        canGoLive: _canUseKind,
                        onCancel: () => Navigator.of(context).pop(),
                        onGoLive: _goLive,
                      ),
                      if (channelName != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Transmitindo no canal #$channelName',
                          style: textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Escolha o que você vai transmitir.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: _KindSwitch(
                          activeKind: _kind,
                          canUseWindow: widget.backend.canUseKind(
                            RtcScreenShareSourceKind.window,
                          ),
                          canUseDisplay: widget.backend.canUseKind(
                            RtcScreenShareSourceKind.display,
                          ),
                          onChanged: (kind) => setState(() {
                            _kind = kind;
                            _preselected = null;
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SourceNote(
                        backend: widget.backend,
                        kind: _kind,
                        preselected: _preselected != null,
                        onChoose: _chooseSource,
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Áudio da transmissão.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AudioToggleRow(
                        value: _includeAudio,
                        kind: _kind,
                        onChanged: (value) =>
                            setState(() => _includeAudio = value),
                      ),
                      if (_includeAudio &&
                          widget.backend.capabilities.usesSystemPicker &&
                          _kind == RtcScreenShareSourceKind.window) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Nesta plataforma o áudio compartilhado é o mix geral do sistema (não é possível isolar só esta janela).',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Escolha a qualidade da transmissão.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _QualityPanel(
                        quality: _quality,
                        onChanged: (quality) =>
                            setState(() => _quality = quality),
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

/// Header: Cancelar sutil à esquerda, título Geist centralizado, Go Live
/// (FilledButton do tema — assinatura Vercel: branco sobre dark) à direita.
class _GoLiveHeader extends StatelessWidget {
  const _GoLiveHeader({
    required this.canGoLive,
    required this.onCancel,
    required this.onGoLive,
  });

  final bool canGoLive;
  final VoidCallback onCancel;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          FilledButton(
            onPressed: onCancel,
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancelar'),
          ),
          Expanded(
            child: Text(
              'Compartilhar tela',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton(
            onPressed: canGoLive ? onGoLive : null,
            child: const Text('Go Live'),
          ),
        ],
      ),
    );
  }
}

/// Chave Tela/Janela: trilho preto embutido no `surface2`, aba ativa no
/// idioma do `_SidebarItem` (`surface3` + `borderSubtle`, texto Geist).
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({
    required this.activeKind,
    required this.canUseWindow,
    required this.canUseDisplay,
    required this.onChanged,
  });

  final RtcScreenShareSourceKind activeKind;
  final bool canUseWindow;
  final bool canUseDisplay;
  final ValueChanged<RtcScreenShareSourceKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KindTab(
              icon: Icons.web_asset_outlined,
              label: 'Janela',
              selected: activeKind == RtcScreenShareSourceKind.window,
              enabled: canUseWindow,
              onTap: () => onChanged(RtcScreenShareSourceKind.window),
            ),
            _KindTab(
              icon: Icons.desktop_windows_outlined,
              label: 'Tela',
              selected: activeKind == RtcScreenShareSourceKind.display,
              enabled: canUseDisplay,
              onTap: () => onChanged(RtcScreenShareSourceKind.display),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTab extends StatelessWidget {
  const _KindTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppTokens.textPrimary
        : (enabled ? AppTokens.textSecondary : AppTokens.textMuted);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTokens.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppTokens.borderSubtle : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha sob a chave em Geist Mono do tema: motivo do veto, aviso do portal
/// no Linux ou "Escolher fonte…" no Windows.
class _SourceNote extends StatelessWidget {
  const _SourceNote({
    required this.backend,
    required this.kind,
    required this.preselected,
    required this.onChoose,
  });

  final NativeScreenShareBackend backend;
  final RtcScreenShareSourceKind kind;
  final bool preselected;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disabledReason = backend.disabledReasonFor(kind);
    if (!backend.canUseKind(kind) && disabledReason != null) {
      return Text(
        disabledReason,
        textAlign: TextAlign.center,
        style: textTheme.bodyMedium?.copyWith(color: AppTokens.textPrimary),
      );
    }
    if (backend.capabilities.usesSystemPicker) {
      return Text(
        'A fonte será escolhida no portal do sistema ao iniciar a transmissão.',
        textAlign: TextAlign.center,
        style: textTheme.bodySmall,
      );
    }
    return Center(
      child: TextButton(
        onPressed: onChoose,
        child: Text(preselected ? 'Trocar de fonte…' : 'Escolher fonte…'),
      ),
    );
  }
}

/// Toggle "Incluir áudio do sistema" (opt-out, default ligado): o áudio vai
/// junto com o share a menos que o usuário desligue. O subtítulo espelha a
/// semântica do modo ativo.
class _AudioToggleRow extends StatelessWidget {
  const _AudioToggleRow({
    required this.value,
    required this.kind,
    required this.onChanged,
  });

  final bool value;
  final RtcScreenShareSourceKind kind;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incluir áudio do sistema',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind == RtcScreenShareSourceKind.display
                          ? 'Transmite todo o áudio do sistema.'
                          : 'Transmite o áudio da janela.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Qualidades como itens do `_SidebarItem`: selecionada `surface3` +
/// `borderSubtle` com check, demais transparentes com hover do tema.
class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.quality, required this.onChanged});

  final GoLiveQuality quality;
  final ValueChanged<GoLiveQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = GoLiveQuality.values;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _QualityRow(
            title: _qualityTitle(values[i]),
            spec: _qualitySpec(values[i]),
            selected: quality == values[i],
            onTap: () => onChanged(values[i]),
          ),
        ],
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.title,
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            // Selecionada = branca como o Go Live (assinatura Vercel
            // invertida); demais transparentes como os itens da sidebar.
            color: selected ? AppTokens.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Coluna fixa do indicador: reserva o espaço em todas as linhas
              // para a spec terminar sempre na mesma borda direita.
              SizedBox(
                width: 26,
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 18,
                        color: AppTokens.textInverse,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? AppTokens.textInverse
                        : AppTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  spec,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: textTheme.bodySmall?.copyWith(
                    color: selected
                        ? AppTokens.textInverse.withValues(alpha: 0.6)
                        : AppTokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _qualityTitle(GoLiveQuality quality) => switch (quality) {
  GoLiveQuality.auto => 'Automática',
  GoLiveQuality.high => 'Alta',
  GoLiveQuality.medium => 'Média',
  GoLiveQuality.low => 'Baixa',
};

String _qualitySpec(GoLiveQuality quality) => switch (quality) {
  GoLiveQuality.auto => 'Sem downscale · até 15fps',
  GoLiveQuality.high => '1080p · até 60fps',
  GoLiveQuality.medium => '1080p · até 30fps',
  GoLiveQuality.low => '720p · 15fps',
};
