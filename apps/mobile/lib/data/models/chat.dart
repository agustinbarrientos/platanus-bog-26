/// Mensajes del agente (`POST /me/health-context/chat`, claude-haiku-4-5).
/// El backend es stateless: se le devuelve el `history` que él mismo entregó.
class ChatMessage {
  const ChatMessage({required this.role, required this.content, this.pendiente = false});

  /// user | assistant
  final String role;
  final String content;

  /// Solo local: el mensaje está en vuelo (no viene del backend).
  final bool pendiente;

  bool get esUsuario => role == 'user';

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(role: '${j['role']}', content: '${j['content']}');
}

class ChatRespuesta {
  const ChatRespuesta({required this.reply, required this.history});
  final String reply;
  final List<ChatMessage> history;

  factory ChatRespuesta.fromJson(Map<String, dynamic> j) => ChatRespuesta(
    reply: '${j['reply'] ?? ''}',
    history: ((j['history'] as List?) ?? const []).map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>())).toList(),
  );
}
