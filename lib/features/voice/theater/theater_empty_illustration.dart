import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/appearance_theme.dart';

/// Asset undraw do empty state do Modo Teatro (trabalhador remoto com telas).
const theaterEmptyIllustrationAsset = 'assets/svgs/undraw_remote-worker.svg';

/// Primário do undraw (`#6C63FF`): pinta as áreas grandes da ilustração
/// (roupa da personagem, almofada/cadeira) e é a ÚNICA cor recolorida com o
/// tema. Pele (`#ED9DA0`), escuros, cinzas e brancos são preservados para
/// manter o desenho fiel ao original.
const String undrawPrimaryHex = '#6c63ff';

/// Recolore o primário undraw com o [accentHex] (`#RRGGBB`, com ou sem `#`).
/// Pura e testável: não toca em nenhuma outra cor do SVG.
@visibleForTesting
String recolorUndrawSvg(String rawSvg, String accentHex) {
  final normalized = accentHex.startsWith('#') ? accentHex : '#$accentHex';
  return rawSvg.replaceAll(
    RegExp(RegExp.escape(undrawPrimaryHex), caseSensitive: false),
    normalized,
  );
}

/// Ilustração do empty state do Modo Teatro: o undraw acima com o primário
/// trocado pelo `accent` do tema atual (qualquer preset ou cor custom).
/// O SVG cru é carregado uma vez por valor de accent e memoizado — troca de
/// tema recarrega, rebuilds normais reutilizam o `Future`.
class TheaterEmptyIllustration extends ConsumerStatefulWidget {
  const TheaterEmptyIllustration({super.key, this.height = 148});

  /// Altura da ilustração (largura segue o aspect 800:564 do asset).
  final double height;

  @override
  ConsumerState<TheaterEmptyIllustration> createState() =>
      _TheaterEmptyIllustrationState();
}

class _TheaterEmptyIllustrationState
    extends ConsumerState<TheaterEmptyIllustration> {
  String? _accentHex;
  Future<String>? _svgFuture;

  static Future<String> _load(String accentHex) async {
    final raw = await rootBundle.loadString(theaterEmptyIllustrationAsset);
    return recolorUndrawSvg(raw, accentHex);
  }

  @override
  Widget build(BuildContext context) {
    final accentHex = colorToHex(context.appColors.accent);
    if (_svgFuture == null || _accentHex != accentHex) {
      _accentHex = accentHex;
      _svgFuture = _load(accentHex);
    }
    return FutureBuilder<String>(
      future: _svgFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          // Reserva o espaço durante o load: sem flash de layout quando o
          // SVG chega (e sem spinner — é decorativo, não conteúdo).
          return SizedBox(height: widget.height);
        }
        return SvgPicture.string(
          data,
          height: widget.height,
          // Decorativa: o título abaixo já descreve o estado para leitores.
          excludeFromSemantics: true,
        );
      },
    );
  }
}
