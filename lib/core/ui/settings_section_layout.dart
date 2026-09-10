import 'package:flutter/material.dart';

import 'ds_tokens.dart';

class SettingsStack extends StatelessWidget {
  const SettingsStack({super.key, required this.children, this.maxWidth = 700});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _withSpacing(children, 10),
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    this.trailing,
    required this.children,
  });

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || trailing != null;
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) rows.add(const Divider(height: 1));
      rows.add(children[index]);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppTokens.borderHairline, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasHeader) ...[
              Container(
                height: 34,
                padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                alignment: Alignment.center,
                color: AppTokens.surfaceBase.withValues(alpha: 0.34),
                child: Row(
                  children: [
                    if (title case final groupTitle?)
                      Expanded(
                        child: Text(
                          groupTitle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.textSecondary,
                            letterSpacing: 0,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    ?trailing,
                  ],
                ),
              ),
              if (children.isNotEmpty) const Divider(height: 1),
            ],
            ...rows,
          ],
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.minHeight = 50,
    this.destructive = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final double minHeight;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTrailing = trailing != null && constraints.maxWidth < 520;
        final titleBlock = _SettingsRowText(
          title: title,
          subtitle: subtitle,
          subtitleColor: subtitleColor,
          destructive: destructive,
        );

        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, stackTrailing ? 9 : 8, 12, 8),
            child: stackTrailing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (icon != null) ...[
                            _SettingsRowIcon(
                              icon: icon!,
                              destructive: destructive,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(child: titleBlock),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: trailing!),
                    ],
                  )
                : Row(
                    children: [
                      if (icon != null) ...[
                        _SettingsRowIcon(icon: icon!, destructive: destructive),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: titleBlock),
                      if (trailing != null) ...[
                        const SizedBox(width: 16),
                        trailing!,
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

enum SettingsNoticeTone { neutral, success, warning, danger }

class SettingsNotice extends StatelessWidget {
  const SettingsNotice({
    super.key,
    required this.message,
    this.tone = SettingsNoticeTone.neutral,
    this.icon,
  });

  final String message;
  final SettingsNoticeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, border) = switch (tone) {
      SettingsNoticeTone.neutral => (
        AppTokens.textSecondary,
        AppTokens.surface1,
        AppTokens.borderHairline,
      ),
      SettingsNoticeTone.success => (
        AppTokens.accentGreen,
        const Color(0x1446A758),
        const Color(0x3346A758),
      ),
      SettingsNoticeTone.warning => (
        AppTokens.accentAmber,
        const Color(0x14F5A623),
        const Color(0x33F5A623),
      ),
      SettingsNoticeTone.danger => (
        AppTokens.accentPurple,
        const Color(0x148B5CF6),
        const Color(0x338B5CF6),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _noticeIcon(tone), size: 14, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12.5,
                height: 1.35,
                color: foreground,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsValueText extends StatelessWidget {
  const SettingsValueText(
    this.value, {
    super.key,
    this.color = AppTokens.textPrimary,
    this.monospace = false,
  });

  final String value;
  final Color color;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontFamily: monospace ? 'Geist Mono' : 'Geist',
        fontSize: monospace ? 11.5 : 13,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0,
      ),
    );
  }
}

class _SettingsRowIcon extends StatelessWidget {
  const _SettingsRowIcon({required this.icon, required this.destructive});

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppTokens.accentPurple
        : AppTokens.textSecondary;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppTokens.borderHairline, width: 1),
      ),
      child: Icon(icon, size: 15, color: color),
    );
  }
}

class _SettingsRowText extends StatelessWidget {
  const _SettingsRowText({
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.destructive,
  });

  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: destructive ? AppTokens.accentPurple : AppTokens.textPrimary,
            letterSpacing: 0,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              height: 1.25,
              color: subtitleColor ?? AppTokens.textMuted,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

List<Widget> _withSpacing(List<Widget> children, double gap) {
  final spaced = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) spaced.add(SizedBox(height: gap));
    spaced.add(children[index]);
  }
  return spaced;
}

IconData _noticeIcon(SettingsNoticeTone tone) {
  return switch (tone) {
    SettingsNoticeTone.neutral => Icons.info_outline,
    SettingsNoticeTone.success => Icons.check_circle_outline,
    SettingsNoticeTone.warning => Icons.warning_amber_outlined,
    SettingsNoticeTone.danger => Icons.error_outline,
  };
}
