import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Coluna esquerda estilo Discord (wireframe v3 §4.1): item de Mensagens
/// diretas no topo → divider → servidores (squircle 16→24 no hover) →
/// divider → botão de criar.
class ServerRail extends ConsumerWidget {
  const ServerRail({
    super.key,
    this.selectedServerId,
    this.dmActive = false,
    this.width = 72,
    this.compact = false,
  });

  /// Servidor em destaque (usado no shell); nulo na home.
  final String? selectedServerId;

  /// Item de DM em estado ativo (usado pela visão DM — SPEC 3).
  final bool dmActive;

  /// Largura da coluna: 72 desktop / 56 mobile (<800, wireframe §7).
  final double width;

  /// Escala mobile (<800): itens 40x40 (SPEC 2 tarefa 8).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Container(
      width: width,
      color: AppThemeColors.rail,
      child: servers.when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (error, _) => Center(
          child: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tentar novamente',
            onPressed: () => ref.invalidate(serversProvider),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _DmRailItem(active: dmActive, compact: compact),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1),
            ),
            for (final server in list) _ServerRailItem(
              server: server,
              selected: server.id == selectedServerId,
              compact: compact,
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1),
            ),
            Center(
              child: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Criar servidor',
                onPressed: () => context.push('/create-server'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Item de Mensagens diretas: balão SVG + pill branca esquerda
/// (idle 8 / hover 20 / ativo 40), ativo = bg accent.
class _DmRailItem extends StatefulWidget {
  const _DmRailItem({required this.active, this.compact = false});

  final bool active;

  /// Escala mobile (<800): item 40x40 (SPEC 2 tarefa 8).
  final bool compact;

  @override
  State<_DmRailItem> createState() => _DmRailItemState();
}

class _DmRailItemState extends State<_DmRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final compact = widget.compact;
    final itemSize = compact ? 40.0 : 44.0;
    final radius = compact ? 10.0 : 12.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: 'Mensagens diretas',
          child: InkWell(
            borderRadius: BorderRadius.circular(radius + 4),
            onTap: () => context.push('/dms'),
            child: SizedBox(
              height: itemSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Pill branca à esquerda (wireframe: 0 idle → 16 hover
                  // → 32 ativo; left -14 absoluto, opacidade 0/0.5/1).
                  Positioned(
                    left: -14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: active ? 1 : (_hovered ? 0.5 : 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: 4,
                          height: active ? 32 : (_hovered ? 16 : 0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: compact ? 32 : 40,
                    height: compact ? 32 : 40,
                    decoration: BoxDecoration(
                      color: active
                          ? AppThemeColors.authorColors.first
                          : AppThemeColors.card,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      active ? Icons.chat : Icons.chat_outlined,
                      size: compact ? 16 : 20,
                      color: active
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
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

  /// Escala mobile (<800): item 40x40 (SPEC 2 tarefa 8).
  final bool compact;

  @override
  State<_ServerRailItem> createState() => _ServerRailItemState();
}

class _ServerRailItemState extends State<_ServerRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final server = widget.server;
    final selected = widget.selected;
    final compact = widget.compact;
    final itemSize = compact ? 40.0 : 44.0;
    final radius = compact ? 10.0 : 12.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: server.name,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius + 4),
            onTap: () => context.go('/servers/${server.id}'),
            child: SizedBox(
              height: itemSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Pill branca à esquerda (wireframe: 0 idle → 16 hover
                  // → 32 ativo; left -14 absoluto, opacidade 0/0.5/1).
                  Positioned(
                    left: -14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: selected ? 1 : (_hovered ? 0.5 : 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: 4,
                          height: selected ? 32 : (_hovered ? 16 : 0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Squircle: radius 12 sempre, 16 no hover/ativo.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: compact ? 36 : 44,
                    height: compact ? 36 : 44,
                    margin: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? colorScheme.primary : AppThemeColors.card,
                      borderRadius: BorderRadius.circular(
                        selected || _hovered ? radius + 4 : radius,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: server.iconUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(
                              selected || _hovered ? radius + 4 : radius,
                            ),
                            child: Image.network(
                              server.iconUrl!,
                              width: compact ? 36 : 44,
                              height: compact ? 36 : 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _initial(server, colorScheme, selected),
                            ),
                          )
                        : _initial(server, colorScheme, selected),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _initial(Server server, ColorScheme colorScheme, bool selected) {
    return Text(
      server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
      style: TextStyle(
        color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
