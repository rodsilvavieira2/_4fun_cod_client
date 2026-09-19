import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modo da sala (ADR 0003): `defaultMode` é a UI atual preservada; `theater`
/// é o takeover de janela toda. Entrada sempre em `defaultMode` (V1 sem
/// persistência) — o takeover ativo implica theater, o estado existe para
/// testabilidade e transições explícitas.
enum TheaterViewMode { defaultMode, theater }

/// Layout do Media Stage (grill rodada 4-f): `auto` decide pelo app
/// (reusa `calculateVoiceGridGeometry`), `grid` força tamanhos iguais,
/// `focus` exibe as pinnadas em destaque (1..N lado a lado).
enum TheaterLayoutMode { auto, grid, focus }

/// Estado puro-chrome do Theater (sem LiveKit/track/áudio).
///
/// - `pinnedStreamIds`: chaves `<participantId>:<camera|screen>` na ordem de
///   pin (ordem visual). Conjunto vazio = `auto`. Isolado do spotlight do
///   default (modos nunca interferem entre si).
/// - `showParticipants`/`hideOverlays`/`chatOpen`: toggles do menu `⋯` e
///   da control bar (`💬`).
class TheaterUiState {
  const TheaterUiState({
    this.viewMode = TheaterViewMode.defaultMode,
    this.layout = TheaterLayoutMode.auto,
    this.pinnedStreamIds = const [],
    this.showParticipants = true,
    this.hideOverlays = false,
    this.chatOpen = false,
    this.controlsVisible = true,
  });

  final TheaterViewMode viewMode;
  final TheaterLayoutMode layout;
  final List<String> pinnedStreamIds;
  final bool showParticipants;
  final bool hideOverlays;
  final bool chatOpen;
  final bool controlsVisible;

  bool get hasPins => pinnedStreamIds.isNotEmpty;

  /// Layout efetivo: pin sem `focus` explícito ainda exibe destaque.
  TheaterLayoutMode get effectiveLayout {
    if (layout == TheaterLayoutMode.focus) return TheaterLayoutMode.focus;
    if (hasPins) return TheaterLayoutMode.focus;
    return layout;
  }

  TheaterUiState copyWith({
    TheaterViewMode? viewMode,
    TheaterLayoutMode? layout,
    List<String>? pinnedStreamIds,
    bool? showParticipants,
    bool? hideOverlays,
    bool? chatOpen,
    bool? controlsVisible,
  }) {
    return TheaterUiState(
      viewMode: viewMode ?? this.viewMode,
      layout: layout ?? this.layout,
      pinnedStreamIds: pinnedStreamIds ?? this.pinnedStreamIds,
      showParticipants: showParticipants ?? this.showParticipants,
      hideOverlays: hideOverlays ?? this.hideOverlays,
      chatOpen: chatOpen ?? this.chatOpen,
      controlsVisible: controlsVisible ?? this.controlsVisible,
    );
  }
}

/// Controller puro de UI por canal (`autoDispose`: trocar de canal descarta
/// e a entrada recomeça em default/auto/vazio, conforme decisão do grill).
class TheaterUiController
    extends
        AutoDisposeFamilyNotifier<
          TheaterUiState,
          ({String serverId, String channelId})
        > {
  @override
  TheaterUiState build(({String serverId, String channelId}) arg) {
    return const TheaterUiState();
  }

  void enterTheater() {
    state = state.copyWith(viewMode: TheaterViewMode.theater);
  }

  void exitTheater() {
    state = state.copyWith(viewMode: TheaterViewMode.defaultMode);
  }

  void setLayout(TheaterLayoutMode layout) {
    state = state.copyWith(layout: layout);
  }

  /// Pinnar/desafixar alterna presença mantendo ordem de pin (ordem visual).
  /// Uso genérico; o stage em modo `focus` usa [focusStream] (foco único).
  void togglePin(String streamKey) {
    final pins = List<String>.of(state.pinnedStreamIds);
    if (pins.contains(streamKey)) {
      pins.remove(streamKey);
    } else {
      pins.add(streamKey);
    }
    state = state.copyWith(pinnedStreamIds: List.unmodifiable(pins));
  }

  /// Foco único do modo `focus`: a stream vira O destaque; clicar no rail
  /// troca o foco sem nunca deixá-lo vazio. Sem emissão quando já é o foco.
  void focusStream(String streamKey) {
    if (state.pinnedStreamIds.length == 1 &&
        state.pinnedStreamIds.first == streamKey) {
      return;
    }
    state = state.copyWith(pinnedStreamIds: List.unmodifiable([streamKey]));
  }

  void clearPins() {
    if (state.pinnedStreamIds.isEmpty) return;
    state = state.copyWith(pinnedStreamIds: const []);
  }

  /// Remove pins cujas streams terminaram; vazio volta ao `auto` efetivo.
  void prunePins(Set<String> validKeys) {
    final pins = state.pinnedStreamIds
        .where(validKeys.contains)
        .toList(growable: false);
    if (pins.length == state.pinnedStreamIds.length) return;
    state = state.copyWith(pinnedStreamIds: pins);
  }

  void toggleChat() => state = state.copyWith(chatOpen: !state.chatOpen);

  void toggleParticipants() =>
      state = state.copyWith(showParticipants: !state.showParticipants);

  void toggleOverlays() =>
      state = state.copyWith(hideOverlays: !state.hideOverlays);

  void setControlsVisible(bool visible) {
    if (state.controlsVisible == visible) return;
    state = state.copyWith(controlsVisible: visible);
  }
}

final theaterUiControllerProvider = NotifierProvider.autoDispose
    .family<
      TheaterUiController,
      TheaterUiState,
      ({String serverId, String channelId})
    >(TheaterUiController.new);
