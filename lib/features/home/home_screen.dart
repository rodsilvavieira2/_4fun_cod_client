import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/settings_modal.dart';
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
                  ServerRail(
                    width: compact
                        ? AppLayout.compactServerRailWidth
                        : AppLayout.serverRailWidth,
                    compact: compact,
                  ),
                  if (!compact) ...[
                    const VerticalDivider(width: 1),
                    const SizedBox(
                      width: AppLayout.navigationWidth,
                      child: _HomeNavigation(),
                    ),
                  ],
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
              ),
            ),
            child: const Row(
              children: [
                _BrandMark(size: 28),
                SizedBox(width: 10),
                Text(
                  '4fun_cod',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 8),
            child: Text(
              'COMUNIDADES',
              style: TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppTokens.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Escolha um servidor no rail ou veja todos no painel principal.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12.5,
                height: 1.45,
                color: AppTokens.textMuted,
              ),
            ),
          ),
          const Spacer(),
          UserPanel(onOpenSettings: () => showSettingsModal(context)),
        ],
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppTokens.activeOverlay
                : (_hovered ? AppTokens.hoverOverlay : Colors.transparent),
            borderRadius: AppRadius.brSm,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: highlighted
                    ? AppTokens.textPrimary
                    : AppTokens.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: highlighted
                        ? AppTokens.textPrimary
                        : AppTokens.textSecondary,
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BrandMark(size: 64),
              const SizedBox(height: 22),
              Text(
                'Crie seu primeiro servidor',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Reúna sua galera em canais de texto, voz, câmera e compartilhamento de tela.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppTokens.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              AppButton(
                label: 'Criar ou entrar',
                icon: Icons.add,
                size: AppButtonSize.lg,
                onPressed: () => showServerEntryDialog(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerOverview extends StatelessWidget {
  const _ServerOverview({required this.servers});

  final List<Server> servers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 3
            : (constraints.maxWidth >= 720 ? 2 : 1);
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 3.5 : 2.5,
          ),
          itemCount: servers.length,
          itemBuilder: (context, index) => _ServerCard(server: servers[index]),
        );
      },
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({required this.server});

  final Server server;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hovered ? AppTokens.surface2 : AppTokens.surface1,
            borderRadius: AppRadius.brLg,
            border: Border.all(
              color: _hovered
                  ? AppTokens.borderStrong
                  : AppTokens.borderHairline,
            ),
          ),
          child: Row(
            children: [
              _ServerAvatar(server: server),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${server.channels.length} ${server.channels.length == 1 ? 'canal' : 'canais'}',
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12.5,
                        color: AppTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: _hovered ? Offset.zero : const Offset(-0.2, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1 : 0.55,
                  child: const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: AppTokens.textSecondary,
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

class _ServerAvatar extends StatelessWidget {
  const _ServerAvatar({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppTokens.surface3,
        borderRadius: AppRadius.brLg,
      ),
      child: server.iconUrl == null
          ? Text(
              server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
              ),
            )
          : Image.network(
              server.iconUrl!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.groups_2_outlined,
                color: AppTokens.textSecondary,
              ),
            ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTokens.textPrimary,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.forum_rounded,
        size: size * 0.55,
        color: AppTokens.textInverse,
      ),
    );
  }
}
