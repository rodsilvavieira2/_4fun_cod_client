import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings_modal_sidebar.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/notifications_section.dart';
import 'settings_sections/updates_section.dart';
import 'settings_sections/voice_video_section.dart';
import 'ui.dart';

/// Modal de configurações estilo janela macOS (90% da tela, backdrop blur e
/// alto contraste).
Future<void> showSettingsModal(
  BuildContext context, {
  SettingsSection initialSection = SettingsSection.account,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar configurações',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SettingsModal(initialSection: initialSection);
    },
  );
}

class _SettingsModal extends StatefulWidget {
  const _SettingsModal({required this.initialSection});

  final SettingsSection initialSection;

  @override
  State<_SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<_SettingsModal> {
  late SettingsSection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = math.min(920.0, math.max(320.0, screenSize.width - 32));
    final maxHeight = math.min(680.0, math.max(320.0, screenSize.height - 32));
    return SettingsModalEscClose(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            minWidth: math.min(620.0, maxWidth),
            minHeight: math.min(420.0, maxHeight),
          ),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTokens.surface2.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: AppTokens.borderSubtle, width: 1),
                    boxShadow: AppShadows.modalWindow,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 202,
                        child: SettingsModalSidebar(
                          section: _section,
                          onSectionChanged: (section) =>
                              setState(() => _section = section),
                          onClose: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Expanded(
                        child: _SettingsBody(
                          section: _section,
                          onClose: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
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

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.section, required this.onClose});

  final SettingsSection section;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              AppIconButton(
                icon: Icons.close,
                tooltip: 'Fechar (ESC)',
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: switch (section) {
                SettingsSection.account => AccountSection(
                  onCloseSettings: onClose,
                ),
                SettingsSection.voiceVideo => const VoiceVideoSection(),
                SettingsSection.notifications => const NotificationsSection(),
                SettingsSection.appearance => const AppearanceSection(),
                SettingsSection.updates => const UpdatesSection(),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsModalEscClose extends StatelessWidget {
  const SettingsModalEscClose({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
