import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/settings_modal.dart';
import '../../core/ui/settings_section_layout.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import '../servers/server_rail.dart';
import '../servers/servers_providers.dart';
import '../servers/user_panel.dart';

/// Hub inicial com a mesma anatomia do restante do produto: servidores no
/// rail, navegação contextual ao lado e conteúdo principal.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);

    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < AppLayout.compactBreakpoint;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact)
                    ServerRail(
                      width: AppLayout.compactServerRailWidth,
                      compact: compact,
                    )
                  else
                    // Bloco de navegação (rail + lista) como base do overlay:
                    // o UserPanel flutua sobre os dois, mesmo padrão do servidor.
                    SizedBox(
                      width:
                          AppLayout.serverRailWidth +
                          1 +
                          AppLayout.navigationWidth,
                      child: Stack(
                        children: [
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ServerRail(width: AppLayout.serverRailWidth),
                              VerticalDivider(width: 1),
                              SizedBox(
                                width: AppLayout.navigationWidth,
                                child: _HomeNavigation(),
                              ),
                            ],
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: UserPanel(
                              floating: true,
                              onOpenSettings: () => showSettingsModal(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _HomeContent(servers: servers)),
                ],
              );
            },
          ),
          // Toast de update (só renderiza em available/downloading/ready).
          const Positioned(right: 16, bottom: 16, child: UpdateBanner()),
        ],
      ),
    );
  }
}

class _HomeNavigation extends StatelessWidget {
  const _HomeNavigation();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppLayout.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
              ),
            ),
            child: const Row(
              children: [
                AppLogo(size: 24),
                SizedBox(width: 10),
                Text(
                  '4FunCode',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const _HomeNavGroupLabel('Principal'),
          const _HomeNavItem(
            icon: Icons.people_alt_outlined,
            label: 'Início',
            selected: true,
          ),
          _HomeNavItem(
            icon: Icons.add_circle_outline,
            label: 'Criar ou entrar',
            onTap: () => showServerEntryDialog(context),
          ),
          const Spacer(),
          // Reserva sob o card flutuante (mesmo valor do servidor sem voz):
          // o conteúdo nunca fica escondido atrás do overlay.
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

class _HomeNavGroupLabel extends StatelessWidget {
  const _HomeNavGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Geist Mono',
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppTokens.textMuted,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _HomeNavItem extends StatefulWidget {
  const _HomeNavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_HomeNavItem> createState() => _HomeNavItemState();
}

class _HomeNavItemState extends State<_HomeNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _hovered;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppTokens.surface2
                : (_hovered ? AppTokens.hoverOverlay : Colors.transparent),
            borderRadius: AppRadius.brSm,
            border: Border.all(
              color: widget.selected
                  ? AppTokens.borderSubtle
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 2,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? AppTokens.accentVercel
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(width: 7),
              Icon(
                widget.icon,
                size: 14.5,
                color: highlighted
                    ? AppTokens.textPrimary
                    : AppTokens.textSecondary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: highlighted
                        ? AppTokens.textPrimary
                        : AppTokens.textSecondary,
                    letterSpacing: 0,
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

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.servers});

  final AsyncValue<List<Server>> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: AppTokens.background,
      child: Column(
        children: [
          Container(
            height: AppLayout.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xCC000000),
              border: Border(
                bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people_alt_outlined,
                  size: 18,
                  color: AppTokens.textSecondary,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Início',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.add,
                  tooltip: 'Criar ou entrar em um servidor',
                  onPressed: () => showServerEntryDialog(context),
                ),
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.account_circle,
                  tooltip: 'Perfil e configurações',
                  onPressed: () => showSettingsModal(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: servers.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) =>
                  _HomeError(onRetry: () => ref.invalidate(serversProvider)),
              data: (list) => list.isEmpty
                  ? const _EmptyHome()
                  : _ServerOverview(servers: list),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Não foi possível carregar seus servidores.',
            style: TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Tentar novamente',
            variant: AppButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: SettingsStack(
        maxWidth: 640,
        children: [
          SettingsGroup(
            title: 'Comunidades',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    const AppLogo(size: 32),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crie seu primeiro servidor',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.textPrimary,
                              letterSpacing: 0,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Canais de texto, voz, câmera e tela.',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 12,
                              height: 1.25,
                              color: AppTokens.textMuted,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    AppButton(
                      label: 'Criar ou entrar',
                      icon: Icons.add,
                      size: AppButtonSize.sm,
                      onPressed: () => showServerEntryDialog(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServerOverview extends StatelessWidget {
  const _ServerOverview({required this.servers});

  final List<Server> servers;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: SettingsStack(
        maxWidth: 640,
        children: [
          SettingsGroup(
            title: 'Comunidades',
            trailing: AppButton(
              label: 'Criar ou entrar',
              icon: Icons.add,
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: () => showServerEntryDialog(context),
            ),
            children: [
              for (final server in servers) _ServerRow(server: server),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatefulWidget {
  const _ServerRow({required this.server});

  final Server server;

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.go('/servers/${server.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          color: _hovered ? AppTokens.hoverOverlay : Colors.transparent,
          child: Row(
            children: [
              _ServerAvatar(server: server, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.textPrimary,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${server.channels.length} ${server.channels.length == 1 ? 'canal' : 'canais'}',
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12,
                        color: AppTokens.textMuted,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hovered ? 1 : 0.55,
                child: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerAvatar extends StatelessWidget {
  const _ServerAvatar({required this.server, this.size = 32});

  final Server server;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppTokens.surface3,
        borderRadius: AppRadius.brSm,
      ),
      child: AppFileImage(
        path: server.iconUrl,
        width: size,
        height: size,
        fallback: Text(
          server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: size <= 32 ? 13 : 17,
            fontWeight: FontWeight.w700,
            color: AppTokens.textPrimary,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
