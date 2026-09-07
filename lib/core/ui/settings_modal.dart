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

/// Modal de configurações estilo janela macOS (660x460 com backdrop blur e alto contraste).
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
    return SettingsModalEscClose(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 680,
            maxHeight: 460,
            minWidth: 320,
            minHeight: 320,
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
                        width: 190,
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
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  letterSpacing: -0.2,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: switch (section) {
              SettingsSection.account => AccountSection(
                onCloseSettings: onClose,
              ),
              SettingsSection.appearance => const AppearanceSection(),
              SettingsSection.voiceVideo => const VoiceVideoSection(),
              SettingsSection.notifications => const NotificationsSection(),
              SettingsSection.updates => const UpdatesSection(),
              SettingsSection.signOut => const SizedBox.shrink(),
            },
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
