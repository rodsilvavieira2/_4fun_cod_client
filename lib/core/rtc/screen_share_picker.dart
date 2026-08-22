import 'package:flutter/material.dart';

// ÚNICO arquivo novo de core/rtc autorizado a importar `livekit_client`
// (além de livekit_rtc_service.dart e rtc_video_view.dart — invariante de
// arquitetura do 4fun_cod). A UI em features/ enxerga apenas este widget e o
// contrato RtcService.
import 'package:livekit_client/livekit_client.dart'
    show ScreenSelectDialog;

/// Seletor de fonte de compartilhamento de tela (Fase 6) — wrapper PT-BR
/// do `ScreenSelectDialog.show` do SDK (widgets/screen_select_dialog.dart:130).
///
/// RISCO: a API é marcada `@experimental` na 2.11.0 (linha 129) e pode
/// mudar em releases futuros; o risco fica ISOLADO aqui — features/ importa
/// apenas este arquivo, nunca o `ScreenSelectDialog` diretamente.
class RtcScreenSharePicker {
  const RtcScreenSharePicker._();

  /// Mostra o picker (telas + janelas, com thumbnails) e devolve o id da
  /// fonte selecionada — para passar a [RtcService.startScreenShare] — ou
  /// null quando o usuário cancela. Desktop (Linux/Windows) apenas.
  static Future<String?> show(
    BuildContext context, {
    String titleText = 'Escolha o que compartilhar',
    String screenTabText = 'Tela inteira',
    String windowTabText = 'Janela',
    String cancelText = 'Cancelar',
    String shareText = 'Compartilhar',
  }) {
    // Consumir o ScreenSelectDialog.show (@experimental na 2.11.0) é o
    // PROPÓSITO deste wrapper — o risco fica isolado aqui (doc da classe).
    // ignore: experimental_member_use
    return ScreenSelectDialog.show(
      context,
      titleText: titleText,
      screenTabText: screenTabText,
      windowTabText: windowTabText,
      cancelText: cancelText,
      shareText: shareText,
    );
  }
}
