/// Mensajes del agente (`POST /me/health-context/chat`).
/// El backend es stateless: se le devuelve el `history` que él mismo entregó
/// (solo `role` + `content`; las `fuentes` son decoración local).
class ChatMessage {
  const ChatMessage({required this.role, required this.content, this.pendiente = false, this.fuentes = const []});

  /// user | assistant
  final String role;
  final String content;

  /// Solo local: el mensaje está en vuelo (no viene del backend).
  final bool pendiente;

  /// Solo en respuestas del agente: los fragmentos en los que se apoyó
  /// ("esto es lo que leí"). No se mandan de vuelta al backend.
  final List<ChatFuente> fuentes;

  bool get esUsuario => role == 'user';

  ChatMessage copyWith({List<ChatFuente>? fuentes}) => ChatMessage(role: role, content: content, pendiente: pendiente, fuentes: fuentes ?? this.fuentes);

  /// Lo único que acepta el backend en `history` (`extra="forbid"`).
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(role: '${j['role']}', content: '${j['content']}');
}

/// Un fragmento que el agente usó para responder: `id` estable del backend
/// (`bio:glucosa`, `sim:mejor_decision`, `kb:banda`…), título legible y grupo
/// (`usuario` = tus datos, `resultado` = tu simulación, `conocimiento` = cómo
/// funciona el motor).
class ChatFuente {
  const ChatFuente({required this.id, required this.titulo, required this.grupo});
  final String id;
  final String titulo;
  final String grupo;

  bool get esDeMisDatos => grupo == 'usuario';
  bool get esDelResultado => grupo == 'resultado';

  factory ChatFuente.fromJson(Map<String, dynamic> j) => ChatFuente(id: '${j['id']}', titulo: '${j['titulo'] ?? j['id']}', grupo: '${j['grupo'] ?? ''}');
}

class ChatRespuesta {
  const ChatRespuesta({required this.reply, required this.history, this.fuentes = const []});
  final String reply;
  final List<ChatMessage> history;
  final List<ChatFuente> fuentes;

  factory ChatRespuesta.fromJson(Map<String, dynamic> j) => ChatRespuesta(
    reply: '${j['reply'] ?? ''}',
    history: ((j['history'] as List?) ?? const []).map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>())).toList(),
    fuentes: ((j['fuentes'] as List?) ?? const []).map((e) => ChatFuente.fromJson((e as Map).cast<String, dynamic>())).toList(),
  );
}
