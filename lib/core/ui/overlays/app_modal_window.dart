import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ds_tokens.dart';

/// Exibe um modal tipo janela macOS com backdrop blur e animação suave
Future<T?> showMacModalWindow<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  double maxWidth = 560,
  double? maxHeight,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Fechar modal',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return _MacModalWindowHost(
        title: title,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        child: child,
      );
    },
  );
}

class _MacModalWindowHost extends StatelessWidget {
  const _MacModalWindowHost({
    required this.child,
    this.title,
    this.maxWidth = 560,
    this.maxHeight,
  });

  final Widget child;
  final String? title;
  final double maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight ?? MediaQuery.of(context).size.height * 0.85,
              minWidth: 320,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (title != null) ...[
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppTokens.borderHairline),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  title!,
                                  style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTokens.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  tooltip: 'Fechar (ESC)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Flexible(child: child),
                      ],
                    ),
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
