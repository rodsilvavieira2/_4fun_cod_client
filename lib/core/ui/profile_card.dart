import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/profile.dart';
import '../theme/appearance_theme.dart';
import 'app_file_image.dart';

Color? profileHexColor(String? value) {
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return null;
  }
  return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
}

/// Cartão único para perfil público e preview; as camadas usam o mesmo modelo.
class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    this.catalog = const [],
    this.fonts = const [],
    this.avatarBytes,
    this.bannerBytes,
    this.compact = false,
    this.replayToken = 0,
  });

  final ProfileData profile;
  final List<CosmeticItem> catalog;
  final List<ProfileFont> fonts;
  final Uint8List? avatarBytes;
  final Uint8List? bannerBytes;
  final bool compact;
  final int replayToken;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static final Map<String, DateTime> _lastEffect = {};
  late final AnimationController _effect = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playEffect();
      _syncAmbient();
    });
  }

  @override
  void didUpdateWidget(covariant ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.profileEffectId != widget.profile.profileEffectId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playEffect());
    }
    if (oldWidget.replayToken != widget.replayToken) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _playEffect(force: true),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAmbient());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAmbient();
    } else {
      _ambient.stop();
    }
  }

  void _syncAmbient() {
    if (!mounted) return;
    final enabled =
        !MediaQuery.of(context).disableAnimations &&
        ([
              widget.profile.avatarDecorationId,
              widget.profile.nameplateId,
              widget.profile.profileFrameId,
            ].any((id) => _item(id)?.visual['animated'] == true) ||
            [
              'neon',
              'pop',
              'gummy',
            ].contains(widget.profile.style?['effectId']));
    if (enabled && !_ambient.isAnimating) {
      _ambient.repeat();
    } else if (!enabled) {
      _ambient.stop();
    }
  }

  void _playEffect({bool force = false}) {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    final id = widget.profile.profileEffectId;
    if (id == null) return;
    final key = '${widget.profile.userId}:$id';
    final now = DateTime.now();
    if (!force &&
        now.difference(
              _lastEffect[key] ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastEffect[key] = now;
    _effect.forward(from: 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _effect.dispose();
    _ambient.dispose();
    super.dispose();
  }

  CosmeticItem? _item(String? id) {
    if (id == null) return null;
    for (final item in widget.catalog) {
      if (item.id == id) return item;
    }
    return null;
  }

  Color? _itemColor(String? id) =>
      profileHexColor(_item(id)?.visual['color'] as String?);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final profile = widget.profile;
    final theme = profile.theme;
    final primary =
        profileHexColor(theme?['primary'] as String?) ?? colors.surface2;
    final accent =
        profileHexColor(theme?['accent'] as String?) ?? colors.accent;
    final contentColor = _readable(primary, colors.textPrimary);
    final frame = _itemColor(profile.profileFrameId);
    final decoration = _itemColor(profile.avatarDecorationId);
    final nameplate = _itemColor(profile.nameplateId);
    final style = profile.style;
    final styleColors =
        (style?['colors'] as List?)
            ?.whereType<String>()
            .map(profileHexColor)
            .whereType<Color>()
            .toList() ??
        [];
    final nameColor = _readable(
      primary,
      styleColors.isNotEmpty ? styleColors.first : contentColor,
    );
    final styleEffect = style?['effectId'] as String? ?? 'solid';
    final fontId = style?['fontId'] as String? ?? 'geist';
    final font =
        widget.fonts.where((entry) => entry.id == fontId).firstOrNull?.family ??
        (fontId == 'geist-mono' ? 'Geist Mono' : 'Geist');
    final avatarSize = widget.compact ? 48.0 : 72.0;
    final headerHeight = widget.compact ? 72.0 : 112.0;
    return AnimatedBuilder(
      animation: Listenable.merge([_effect, _ambient]),
      builder: (context, child) {
        final progress = _effect.value;
        final glow = math.sin(progress * math.pi).clamp(0.0, 1.0);
        final pulse = (math.sin(_ambient.value * math.pi * 2) + 1) / 2;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: frame == null
                  ? colors.borderSubtle
                  : Color.lerp(
                      frame,
                      Colors.white,
                      _item(profile.profileFrameId)?.visual['animated'] == true
                          ? pulse * .35
                          : 0,
                    )!,
              width: frame == null ? 1 : 3,
            ),
            boxShadow: glow > 0
                ? [
                    BoxShadow(
                      color: (_itemColor(profile.profileEffectId) ?? accent)
                          .withValues(alpha: glow * 0.45),
                      blurRadius: 34 * glow,
                      spreadRadius: 4 * glow,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: AnimatedBuilder(
        animation: _ambient,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: headerHeight,
              width: double.infinity,
              child: _media(
                bytes: widget.bannerBytes,
                path: profile.bannerUrl,
                crop: profile.bannerCrop,
                height: headerHeight,
                fallback: _HeaderFill(primary: primary, accent: accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: Offset(0, -avatarSize * 0.34),
                    child: Container(
                      width: avatarSize + 9,
                      height: avatarSize + 9,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary,
                        border: Border.all(
                          color: decoration == null
                              ? accent
                              : Color.lerp(
                                  decoration,
                                  Colors.white,
                                  _item(
                                            profile.avatarDecorationId,
                                          )?.visual['animated'] ==
                                          true
                                      ? (math.sin(
                                                  _ambient.value * math.pi * 2,
                                                ) +
                                                1) *
                                            .20
                                      : 0,
                                )!,
                          width: decoration == null ? 2 : 4,
                        ),
                      ),
                      child: ClipOval(
                        child: _media(
                          bytes: widget.avatarBytes,
                          path: profile.avatarUrl,
                          crop: profile.avatarCrop,
                          height: avatarSize,
                          fallback: ColoredBox(
                            color: accent.withValues(alpha: .25),
                            child: Center(
                              child: Text(
                                profile.name.isEmpty
                                    ? '?'
                                    : profile.name.characters.first
                                          .toUpperCase(),
                                style: TextStyle(
                                  color: contentColor,
                                  fontSize: avatarSize * .40,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -avatarSize * .24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                nameplate?.withValues(
                                  alpha:
                                      _item(
                                            profile.nameplateId,
                                          )?.visual['animated'] ==
                                          true
                                      ? .14 + _ambient.value * .18
                                      : .23,
                                ) ??
                                Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: nameplate != null
                                ? Border.all(
                                    color: nameplate.withValues(alpha: .65),
                                  )
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: _styledName(
                              profile.name,
                              font,
                              nameColor,
                              styleColors,
                              styleEffect,
                              widget.compact,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${profile.username}',
                          style: TextStyle(
                            color: contentColor.withValues(alpha: .75),
                            fontSize: 12,
                          ),
                        ),
                        if (profile.bio.isNotEmpty && !widget.compact) ...[
                          const SizedBox(height: 12),
                          Text.rich(
                            TextSpan(
                              children: _bioSpans(profile.bio, contentColor),
                            ),
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: contentColor,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _readable(Color background, Color wanted) {
    final l1 = background.computeLuminance();
    final l2 = wanted.computeLuminance();
    final ratio = (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
    if (ratio >= 4.5) return wanted;
    return l1 > .179 ? Colors.black : Colors.white;
  }

  List<InlineSpan> _bioSpans(String source, Color color) {
    final pattern = RegExp(
      r'\[([^\]]+)\]\((https?://[^)]*)\)|\*\*([^*]+)\*\*|__([^_]+)__|\*([^*]+)\*',
    );
    final spans = <InlineSpan>[];
    var position = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > position) {
        spans.add(TextSpan(text: source.substring(position, match.start)));
      }
      final url = match[2];
      if (url != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InkWell(
              onTap: () => launchUrl(Uri.parse(url)),
              child: Text(
                match[1] ?? '',
                style: TextStyle(
                  color: color,
                  decoration: TextDecoration.underline,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      } else if (match[3] != null) {
        spans.add(
          TextSpan(
            text: match[3],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else if (match[4] != null) {
        spans.add(
          TextSpan(
            text: match[4],
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: match[5],
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      position = match.end;
    }
    if (position < source.length) {
      spans.add(TextSpan(text: source.substring(position)));
    }
    return spans;
  }

  Widget _styledName(
    String value,
    String font,
    Color color,
    List<Color> colors,
    String effect,
    bool compact,
  ) {
    final pulse = (math.sin(_ambient.value * math.pi * 2) + 1) / 2;
    final shadows = switch (effect) {
      'neon' => [
        Shadow(
          color: color.withValues(alpha: .6 + pulse * .4),
          blurRadius: 8 + pulse * 14,
        ),
        Shadow(color: color, blurRadius: 16 + pulse * 16),
      ],
      'toon' => [
        const Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
      ],
      'pop' => [
        Shadow(
          color: color.withValues(alpha: .6),
          offset: Offset(2, 2 + pulse * 2),
          blurRadius: 0,
        ),
      ],
      'gummy' => [
        Shadow(
          color: color.withValues(alpha: .5 + pulse * .3),
          offset: const Offset(0, 3),
          blurRadius: 7 + pulse * 5,
        ),
      ],
      _ => <Shadow>[],
    };
    final text = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: font,
        fontFamilyFallback: const ['Geist'],
        fontSize: compact ? 17 : 22,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: effect == 'toon' ? .5 : 0,
        shadows: shadows,
      ),
    );
    if (effect == 'gradient' || effect == 'prism') {
      final gradientColors = effect == 'prism'
          ? (colors.length >= 3
                ? colors.take(3).toList()
                : [
                    const Color(0xFF73CEFF),
                    const Color(0xFFE292E4),
                    const Color(0xFFFFCE80),
                  ])
          : [
              color,
              colors.length > 1
                  ? colors[1]
                  : Color.lerp(color, Colors.white, .55)!,
            ];
      return ShaderMask(
        shaderCallback: (bounds) =>
            LinearGradient(colors: gradientColors).createShader(bounds),
        child: text,
      );
    }
    return text;
  }

  Widget _media({
    required Uint8List? bytes,
    required String? path,
    required Map<String, dynamic>? crop,
    required double height,
    required Widget fallback,
  }) {
    if (bytes == null && path == null) return fallback;
    final widthFraction = (crop?['width'] as num?)?.toDouble() ?? 1;
    final x = (crop?['x'] as num?)?.toDouble() ?? 0;
    final y = (crop?['y'] as num?)?.toDouble() ?? 0;
    final heightFraction = (crop?['height'] as num?)?.toDouble() ?? 1;
    final alignment = Alignment(
      (x + widthFraction / 2) * 2 - 1,
      (y + heightFraction / 2) * 2 - 1,
    );
    final zoom = 1 / widthFraction.clamp(.33, 1);
    return ClipRect(
      child: Transform.scale(
        scale: zoom,
        alignment: alignment,
        child: bytes != null
            ? Image.memory(
                bytes,
                width: double.infinity,
                height: height,
                fit: BoxFit.cover,
                alignment: alignment,
              )
            : AppFileImage(
                path: path,
                width: double.infinity,
                height: height,
                fit: BoxFit.cover,
                alignment: alignment,
                fallback: fallback,
              ),
      ),
    );
  }
}

class _HeaderFill extends StatelessWidget {
  const _HeaderFill({required this.primary, required this.accent});
  final Color primary;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent.withValues(alpha: .55), primary, primary],
      ),
    ),
  );
}
