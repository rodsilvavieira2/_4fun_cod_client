import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Coluna esquerda estilo macOS / Discord refinado (wireframe v4):
/// servidores → divisor → criar servidor.
/// TODO(dms): botão de DMs oculto até concluir a funcionalidade (rota /dms
/// mantida, sem entrada visível no rail).
class ServerRail extends ConsumerWidget {
  const ServerRail({
    super.key,
    this.selectedServerId,
    // Mantido para reativação das DMs sem quebrar DmShellScreen.
    this.dmActive = false,
    this.width = AppLayout.serverRailWidth,
    this.compact = false,
  });

  final String? selectedServerId;
  final bool dmActive;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppTokens.surfaceBase,
        border: Border(
          right: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: servers.when(
        loading: () => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (error, _) => Center(
          child: IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Tentar novamente',
            onPressed: () => ref.invalidate(serversProvider),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _HomeRailItem(
              selected: selectedServerId == null && !dmActive,
              compact: compact,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(height: 1, color: AppTokens.borderHairline),
            ),
            for (final server in list)
              _ServerRailItem(
                server: server,
                selected: server.id == selectedServerId,
                compact: compact,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(height: 1, color: AppTokens.borderHairline),
            ),
            _AddServerRailItem(compact: compact),
          ],
        ),
      ),
    );
  }
}

/// Atalho fixo para a home (`/`): logo circular do 4FunCode no mesmo
/// padrão dos botões de servidor (44px, circular → arredondado no
/// hover/seleção, pill branca à esquerda).
class _HomeRailItem extends StatefulWidget {
  const _HomeRailItem({required this.selected, this.compact = false});

  final bool selected;
  final bool compact;

  @override
  State<_HomeRailItem> createState() => _HomeRailItemState();
}

class _HomeRailItemState extends State<_HomeRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final compact = widget.compact;
    final itemSize = compact ? 36.0 : 44.0;
    final radius = compact ? 10.0 : 14.0;
    final active = selected || _hovered;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: 'Início',
          child: InkWell(
            borderRadius: BorderRadius.circular(radius + 4),
            mouseCursor: SystemMouseCursors.click,
            onTap: () => context.go('/'),
            child: SizedBox(
              height: itemSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Pill branca Vercel à esquerda
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        width: selected ? 3.5 : (_hovered ? 3.5 : 0),
                        height: selected ? 28 : (_hovered ? 14 : 0),
                        decoration: const BoxDecoration(
                          color: AppTokens.textPrimary,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: itemSize,
                    height: itemSize,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTokens.textPrimary
                          : (_hovered
                                ? AppTokens.surface3
                                : AppTokens.surface1),
                      borderRadius: BorderRadius.circular(
                        active ? radius : AppRadius.full,
                      ),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : (_hovered
                                  ? AppTokens.borderSubtle
                                  : AppTokens.borderHairline),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AppLogo(
                      size: itemSize,
                      // Circular em repouso; acompanha o morph do container
                      // no hover/seleção, como os ícones de servidor.
                      radiusFactor: active ? radius / itemSize : 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerRailItem extends StatefulWidget {
  const _ServerRailItem({
    required this.server,
    required this.selected,
    this.compact = false,
  });

  final Server server;
  final bool selected;
  final bool compact;

  @override
  State<_ServerRailItem> createState() => _ServerRailItemState();
}

class _ServerRailItemState extends State<_ServerRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final selected = widget.selected;
    final compact = widget.compact;
    final itemSize = compact ? 36.0 : 44.0;
    final radius = compact ? 10.0 : 14.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: server.name,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius + 4),
            mouseCursor: SystemMouseCursors.click,
            onTap: () => context.go('/servers/${server.id}'),
            child: SizedBox(
              height: itemSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Pill branca Vercel à esquerda
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        width: selected ? 3.5 : (_hovered ? 3.5 : 0),
                        height: selected ? 28 : (_hovered ? 14 : 0),
                        decoration: BoxDecoration(
                          color: AppTokens.textPrimary,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: itemSize,
                    height: itemSize,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTokens.textPrimary
                          : (_hovered
                                ? AppTokens.surface3
                                : AppTokens.surface1),
                      borderRadius: BorderRadius.circular(
                        selected || _hovered ? radius : AppRadius.full,
                      ),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : (_hovered
                                  ? AppTokens.borderSubtle
                                  : AppTokens.borderHairline),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: server.iconUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(
                              selected || _hovered ? radius : AppRadius.full,
                            ),
                            child: Image.network(
                              server.iconUrl!,
                              width: itemSize,
                              height: itemSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _initial(server, selected),
                            ),
                          )
                        : _initial(server, selected),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _initial(Server server, bool selected) {
    return Text(
      server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
      style: TextStyle(
        fontFamily: 'Geist',
        color: selected ? AppTokens.textInverse : AppTokens.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }
}

class _AddServerRailItem extends StatefulWidget {
  const _AddServerRailItem({this.compact = false});

  final bool compact;

  @override
  State<_AddServerRailItem> createState() => _AddServerRailItemState();
}

class _AddServerRailItemState extends State<_AddServerRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final itemSize = compact ? 36.0 : 44.0;
    final radius = compact ? 10.0 : 14.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: 'Criar servidor',
          child: InkWell(
            borderRadius: BorderRadius.circular(radius + 4),
            mouseCursor: SystemMouseCursors.click,
            onTap: () => showServerEntryDialog(context),
            child: SizedBox(
              height: itemSize,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  width: itemSize,
                  height: itemSize,
                  decoration: BoxDecoration(
                    color: _hovered
                        ? AppTokens.accentVercel
                        : AppTokens.surface1,
                    borderRadius: BorderRadius.circular(
                      _hovered ? radius : AppRadius.full,
                    ),
                    border: Border.all(
                      color: _hovered
                          ? Colors.transparent
                          : AppTokens.borderHairline,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: compact ? 16 : 20,
                    color: _hovered ? Colors.white : AppTokens.textSecondary,
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
