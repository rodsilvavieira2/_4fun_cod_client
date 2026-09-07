/// Inicializa as integrações de janela e bandeja nas plataformas desktop.
///
/// Web e plataformas fora do escopo usam esta implementação no-op.
Future<void> initializeDesktopLifecycle() async {}

/// Traz a janela principal para frente (no-op fora do desktop).
Future<void> restoreDesktopWindow() async {}
