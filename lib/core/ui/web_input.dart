import 'package:flutter/foundation.dart';

/// Autofill hints com guarda de plataforma.
///
/// No web, o Chrome (principalmente mobile) pode TRAVAR o campo de texto após
/// interação com autofill/gerenciador de senhas — bug conhecido do Flutter web
/// (flutter#185327, #174999; workaround documentado: remover autofillHints).
/// Fora do web (desktop/mobile nativo) o autofill continua habilitado.
List<String>? webAutofillHints(Iterable<String> hints) =>
    kIsWeb ? null : List<String>.unmodifiable(hints);
