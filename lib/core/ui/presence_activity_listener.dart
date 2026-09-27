import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../websocket/socket_service.dart';

class PresenceActivityListener extends ConsumerStatefulWidget {
  const PresenceActivityListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PresenceActivityListener> createState() =>
      _PresenceActivityListenerState();
}

class _PresenceActivityListenerState
    extends ConsumerState<PresenceActivityListener> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) ref.read(socketServiceProvider).signalActivity();
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onHover: (_) => ref.read(socketServiceProvider).signalActivity(),
    child: Listener(
      onPointerDown: (_) => ref.read(socketServiceProvider).signalActivity(),
      child: widget.child,
    ),
  );
}
