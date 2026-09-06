import '../../shared/models/message.dart';

/// Regras de agrupamento estilo Discord para a lista de mensagens.
///
/// A lista interna é sempre oldest-first (índice 0 = mais antiga).
/// `previous` é a mensagem cronologicamente ANTERIOR (mais antiga) a
/// `current`, ou `null` quando `current` é a mais antiga da lista.
abstract final class ChatGrouping {
  /// Janela de tempo para manter mensagens do mesmo autor no mesmo grupo.
  static const groupWindow = Duration(minutes: 7);

  /// `true` quando [current] abre um novo grupo visual.
  static bool shouldStartNewGroup({
    required ChatMessage current,
    required ChatMessage? previous,
  }) {
    if (previous == null) return true;
    if (previous.id == current.id) return false;
    if (previous.author.id != current.author.id) return true;
    // Ordem temporal inconsistente (ex.: realtime fora de ordem ou
    // paginação sobreposta): quebra o grupo em vez de agrupar errado.
    if (current.createdAt.isBefore(previous.createdAt)) return true;
    if (!_isSameLocalDay(previous.createdAt, current.createdAt)) return true;
    return current.createdAt.difference(previous.createdAt) > groupWindow;
  }

  /// `true` quando [current] é a primeira mensagem do seu dia local
  /// (separador de data deve ser renderizado acima dela).
  static bool shouldShowDayDivider({
    required ChatMessage current,
    required ChatMessage? previous,
  }) {
    if (previous == null) return true;
    if (previous.id == current.id) return false;
    return !_isSameLocalDay(previous.createdAt, current.createdAt);
  }

  /// Ordenação determinística oldest-first; desempate por id para rajadas
  /// com o mesmo `createdAt` (o sort do Dart não é estável).
  static int compare(ChatMessage a, ChatMessage b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  static bool _isSameLocalDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }
}
