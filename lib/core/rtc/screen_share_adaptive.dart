import 'rtc_service.dart';

/// Amostra de rede para o controlador adaptativo do screen share.
///
/// Todos os campos são opcionais: dimensões indisponíveis são ignoradas na
/// decisão (o controlador decide só com o que tem — nunca derruba o share
/// por falta de telemetria).
class ScreenShareNetworkSample {
  const ScreenShareNetworkSample({
    this.rttMs,
    this.lossFraction,
    this.limitationReason,
  });

  /// RTT do par ICE em milissegundos (reaproveitado do poll de latência).
  final int? rttMs;

  /// Fração de perda de pacotes `0.0..1.0` (extraída dos stats do sender).
  final double? lossFraction;

  /// `qualityLimitationReason` do `outbound-rtp` (`bandwidth`/`cpu`/null).
  /// Valores `none`/vazio são normalizados para null no controlador.
  final String? limitationReason;
}

/// Controlador adaptativo do screen share (spec
/// `spec-qualidade-adaptativa-objetivo-2026-09-13.md`, V1).
///
/// - `target` (objetivo): escolha do usuário — teto, só muda por ação dele
///   ([setTarget]) ou [reset].
/// - `effective` (efetiva): `<= target`, decidida por [propose]/[commit]
///   a partir de amostras de rede. Transitória.
/// - Regra: desce rápido (2 amostras ruins), sobe devagar (6 boas), nunca
///   passa do objetivo, com cooldown anti-flapping após cada troca.
///
/// Escada (ordem de bitrate, perfil existente mais próximo do 540p da spec
/// é o `q360p3` — nenhum perfil novo foi criado na V1):
/// `q360p3` < `q720p15` < `q1080p15` < `q1080p30` < `q1080p60`.
/// `auto` tem o mesmo encoding do `q1080p15` e ocupa a mesma posição na
/// escada (objetivo máximo com adaptação total dentro do próprio teto).
class ScreenShareAdaptiveController {
  ScreenShareAdaptiveController({
    required RtcScreenShareQuality target,
    this.badStreakToDowngrade = 2,
    this.goodStreakToUpgrade = 6,
    this.cooldownSamples = 2,
  }) : _target = target,
       _effective = target;

  /// Limiares da spec (visíveis para teste/documentação).
  static const double badLossFraction = 0.05;
  static const int badRttMs = 300;
  static const double goodLossFraction = 0.02;
  static const int goodRttMs = 200;

  /// Escada de adaptação, do menor para o maior bitrate.
  static const List<RtcScreenShareQuality> ladder = [
    RtcScreenShareQuality.q360p3,
    RtcScreenShareQuality.q720p15,
    RtcScreenShareQuality.q1080p15,
    RtcScreenShareQuality.q1080p30,
    RtcScreenShareQuality.q1080p60,
  ];

  final int badStreakToDowngrade;
  final int goodStreakToUpgrade;
  final int cooldownSamples;

  RtcScreenShareQuality _target;
  RtcScreenShareQuality _effective;
  int _badStreak = 0;
  int _goodStreak = 0;
  int _cooldownLeft = 0;

  /// Objetivo escolhido pelo usuário (teto).
  RtcScreenShareQuality get target => _target;

  /// Qualidade efetiva atual (`<= target`).
  RtcScreenShareQuality get effective => _effective;

  /// Índice de [quality] na [ladder] (`auto` = posição do `q1080p15`).
  static int ladderIndex(RtcScreenShareQuality quality) {
    if (quality == RtcScreenShareQuality.auto) {
      return ladder.indexOf(RtcScreenShareQuality.q1080p15);
    }
    return ladder.indexOf(quality);
  }

  static int _ceilingIndex(RtcScreenShareQuality target) => ladderIndex(target);

  /// Troca de objetivo por ação do usuário: a efetiva assume o teto na
  /// hora (decisão explícita, sem rampa) e as sequências zeram.
  void setTarget(RtcScreenShareQuality target) {
    _target = target;
    _effective = target;
    _badStreak = 0;
    _goodStreak = 0;
    _cooldownLeft = 0;
  }

  /// Volta a efetiva ao objetivo sem trocar o teto (fim de share,
  /// reconexão). Zera sequências e cooldown.
  void reset() {
    _effective = _target;
    _badStreak = 0;
    _goodStreak = 0;
    _cooldownLeft = 0;
  }

  static String? _normalizeLimitation(String? reason) {
    final normalized = reason?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'none') {
      return null;
    }
    return normalized;
  }

  static bool _isBad(ScreenShareNetworkSample sample) {
    final limitation = _normalizeLimitation(sample.limitationReason);
    if (limitation == 'bandwidth') return true;
    final loss = sample.lossFraction;
    if (loss != null && loss > badLossFraction) return true;
    final rtt = sample.rttMs;
    if (rtt != null && rtt > badRttMs) return true;
    return false;
  }

  /// Amostra boa exige folga (histerese): `cpu-limited` é neutro (nem bom
  /// nem ruim — subir ali pioraria o gargalo do encoder).
  static bool _isGood(ScreenShareNetworkSample sample) {
    final limitation = _normalizeLimitation(sample.limitationReason);
    if (limitation != null) return false;
    final loss = sample.lossFraction;
    if (loss != null && loss > goodLossFraction) return false;
    final rtt = sample.rttMs;
    if (rtt != null && rtt >= goodRttMs) return false;
    return true;
  }

  RtcScreenShareQuality? _stepDown(RtcScreenShareQuality from) {
    final index = ladderIndex(from) - 1;
    if (index < 0) return null;
    return ladder[index];
  }

  RtcScreenShareQuality? _stepUp(
    RtcScreenShareQuality from,
    RtcScreenShareQuality target,
  ) {
    final ceiling = _ceilingIndex(target);
    final next = ladderIndex(from) + 1;
    if (next > ceiling) return null;
    if (target == RtcScreenShareQuality.auto && next == ceiling) {
      return RtcScreenShareQuality.auto;
    }
    return ladder[next];
  }

  /// Avalia [sample] e propõe a nova efetiva quando há troca de degrau.
  ///
  /// Não altera [effective] — o chamador aplica no sender e confirma com
  /// [commit]. Falha de aplicação é assim barata: nada foi mutado e a
  /// próxima amostra tenta de novo.
  RtcScreenShareQuality? propose(ScreenShareNetworkSample sample) {
    if (_cooldownLeft > 0) {
      _cooldownLeft--;
      _badStreak = 0;
      _goodStreak = 0;
      return null;
    }
    if (_isBad(sample)) {
      _badStreak++;
      _goodStreak = 0;
      if (_badStreak >= badStreakToDowngrade) {
        return _stepDown(_effective);
      }
      return null;
    }
    if (_isGood(sample)) {
      _goodStreak++;
      _badStreak = 0;
      if (_goodStreak >= goodStreakToUpgrade) {
        return _stepUp(_effective, _target);
      }
      return null;
    }
    // Amostra neutra (zona de histerese): quebra ambas as sequências.
    _badStreak = 0;
    _goodStreak = 0;
    return null;
  }

  /// Confirma a troca proposta por [propose] (pós-`setParameters` ok).
  /// Ativa o cooldown e zera as sequências.
  void commit(RtcScreenShareQuality quality) {
    _effective = quality;
    _badStreak = 0;
    _goodStreak = 0;
    _cooldownLeft = cooldownSamples;
  }
}
