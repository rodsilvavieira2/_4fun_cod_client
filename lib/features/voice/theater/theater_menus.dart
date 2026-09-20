import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/app_icon.dart';
import '../../../core/ui/ds_tokens.dart';
import '../../../core/ui/invite_dialog.dart';
import '../../../core/ui/menus/app_menu.dart';
import '../voice_providers.dart';
import '../voice_video_tile.dart';
import 'theater_ui_provider.dart';

/// Valores do menu `⋯` global (layout + sala, sem `Sair`, sem settings).
enum TheaterMoreAction {
  layoutAuto,
  layoutGrid,
  layoutFocus,
  toggleOverlays,
  copyLink,
}

/// Itens do menu `⋯` no padrão compacto [AppMenu] do app (32px, Geist 13).
List<PopupMenuEntry<TheaterMoreAction>> theaterMoreMenuItems(
  TheaterUiState ui,
) => [
  AppMenuHeader<TheaterMoreAction>(title: 'Layout'),
  AppMenuCheckedItem<TheaterMoreAction>.labeled(
    value: TheaterMoreAction.layoutAuto,
    checked: ui.layout == TheaterLayoutMode.auto,
    label: 'Automático',
  ),
  AppMenuCheckedItem<TheaterMoreAction>.labeled(
    value: TheaterMoreAction.layoutGrid,
    checked: ui.layout == TheaterLayoutMode.grid,
    label: 'Grade',
  ),
  AppMenuCheckedItem<TheaterMoreAction>.labeled(
    value: TheaterMoreAction.layoutFocus,
    checked: ui.layout == TheaterLayoutMode.focus,
    label: 'Foco',
  ),
  const AppMenuDivider(),
  AppMenuCheckedItem<TheaterMoreAction>.labeled(
    value: TheaterMoreAction.toggleOverlays,
    checked: ui.hideOverlays,
    label: 'Ocultar overlays',
  ),
  const AppMenuDivider(),
  AppMenuItem<TheaterMoreAction>.labeled(
    value: TheaterMoreAction.copyLink,
    label: 'Copiar link da sala',
    icon: AppIcons.link,
  ),
];

/// Executa a ação do menu `⋯` (chamado pelo `onSelected` do [AppMenuButton]).
void handleTheaterMoreAction(
  BuildContext context,
  WidgetRef ref,
  ({String serverId, String channelId}) arg,
  TheaterMoreAction action,
) {
  final uiNotifier = ref.read(theaterUiControllerProvider(arg).notifier);
  switch (action) {
    case TheaterMoreAction.layoutAuto:
      uiNotifier.setLayout(TheaterLayoutMode.auto);
    case TheaterMoreAction.layoutGrid:
      uiNotifier.setLayout(TheaterLayoutMode.grid);
    case TheaterMoreAction.layoutFocus:
      uiNotifier.setLayout(TheaterLayoutMode.focus);
    case TheaterMoreAction.toggleOverlays:
      uiNotifier.toggleOverlays();
    case TheaterMoreAction.copyLink:
      showInviteDialog(context, serverId: arg.serverId);
  }
}

/// Valores do menu `⋮` por stream.
enum StreamTileAction { focus, fullscreen, watch }

/// Menu `⋮` da stream com os itens compactos [AppMenu] (32px).
Future<void> showStreamTileMenu({
  required BuildContext context,
  required WidgetRef ref,
  required ({String serverId, String channelId}) arg,
  required String streamKey,
  required String participantId,
  required VoiceVideoSource source,
  required VoidCallback onToggleFullscreen,
}) async {
  final uiNotifier = ref.read(theaterUiControllerProvider(arg).notifier);
  final voiceNotifier = ref.read(voiceControllerProvider(arg).notifier);
  final ui = ref.read(theaterUiControllerProvider(arg));
  final isFocusLayout = ui.layout == TheaterLayoutMode.focus;
  final pinned = ui.pinnedStreamIds.contains(streamKey);
  // No foco o destaque é único: o item focado mostra "Em foco"
  // (desabilitado); os demais viram o novo foco ao selecionar.
  final isFocused =
      isFocusLayout &&
      (pinned &&
          ui.pinnedStreamIds.isNotEmpty &&
          ui.pinnedStreamIds.first == streamKey);
  final colors = context.appColors;
  final spotlightSource = source == VoiceVideoSource.screen
      ? VoiceSpotlightSource.screen
      : VoiceSpotlightSource.camera;
  final local = voiceNotifier.isLocalParticipant(participantId);
  final watching =
      local || voiceNotifier.isWatching(participantId, spotlightSource);

  final selected = await showMenu<StreamTileAction>(
    context: context,
    color: colors.surface2,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: colors.borderSubtle, width: 1),
    ),
    position: const RelativeRect.fromLTRB(100, 100, 100, 100),
    items: [
      AppMenuItem<StreamTileAction>.labeled(
        value: StreamTileAction.focus,
        label: isFocusLayout
            ? (isFocused ? 'Em foco' : 'Focar transmissão')
            : (pinned ? 'Desafixar transmissão' : 'Focar transmissão'),
        icon: isFocused
            ? AppIcons.pin
            : (pinned ? AppIcons.pin : AppIcons.pinOff),
        enabled: isFocusLayout ? !isFocused : true,
      ),
      AppMenuItem<StreamTileAction>.labeled(
        value: StreamTileAction.fullscreen,
        label: 'Tela cheia',
        icon: AppIcons.fullscreen,
      ),
      if (!local)
        AppMenuItem<StreamTileAction>.labeled(
          value: StreamTileAction.watch,
          label: watching ? 'Ocultar vídeo' : 'Assistir vídeo',
          icon: watching
              ? AppIcons.viewOff
              : AppIcons.view,
        ),
    ],
  );
  switch (selected) {
    case StreamTileAction.focus:
      if (isFocusLayout) {
        uiNotifier.focusStream(streamKey);
      } else {
        uiNotifier.togglePin(streamKey);
      }
    case StreamTileAction.fullscreen:
      onToggleFullscreen();
    case StreamTileAction.watch:
      if (!local) voiceNotifier.toggleWatch(participantId, spotlightSource);
    case null:
      break;
  }
}
