import 'rtc_service.dart';

/// Remove aliases do dispositivo padrão expostos pelo WebRTC nativo.
///
/// A UI já fornece a opção única "Padrão do sistema". Entradas como
/// "default: Fifine Microphone Pro" apontam para o mesmo mecanismo do SO e
/// não representam outro hardware selecionável.
List<RtcAudioDevice> normalizeAudioDevices(Iterable<RtcAudioDevice> devices) {
  return [
    for (final device in devices)
      if (!_isSystemDefaultAlias(device.label)) device,
  ];
}

bool _isSystemDefaultAlias(String label) =>
    label.trimLeft().toLowerCase().startsWith('default:');
