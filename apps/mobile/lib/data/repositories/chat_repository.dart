import '../../core/env.dart';
import '../api/api_client.dart';
import '../models/chat.dart';

/// `POST /me/health-context/chat`: un agente (claude-haiku-4-5) que solo ve
/// los datos guardados del usuario (+ su PhenoAge si alcanza). Máximo 4.000
/// caracteres por mensaje y 40 turnos de historial.
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  static const maxHistory = 40;
  static const maxMessage = 4000;

  Future<ChatRespuesta> enviar(String message, List<ChatMessage> history) async {
    final msg = message.trim();
    final hist = history.where((m) => !m.pendiente).toList();
    final recortado = hist.length > maxHistory ? hist.sublist(hist.length - maxHistory) : hist;
    if (Env.useMockEngine) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final reply = 'Estoy en modo demo sin conexión, así que no puedo leer tus datos ahora mismo. '
          'Cuando el backend esté disponible respondo con tu perfil y tu edad biológica a la mano.';
      return ChatRespuesta(reply: reply, history: [...recortado, ChatMessage(role: 'user', content: msg), ChatMessage(role: 'assistant', content: reply)]);
    }
    final j = (await _api.post(
      '/me/health-context/chat',
      body: {'message': msg.length > maxMessage ? msg.substring(0, maxMessage) : msg, 'history': recortado.map((m) => m.toJson()).toList()},
      timeout: const Duration(seconds: 120),
    ) as Map)
        .cast<String, dynamic>();
    return ChatRespuesta.fromJson(j);
  }

  /// Preguntas sugeridas para arrancar la conversación.
  static const sugerencias = <String>[
    '¿Qué significa mi edad biológica frente a mi edad?',
    '¿Cuál de mis datos pesa más en el resultado?',
    '¿Qué examen me conviene hacerme primero?',
    '¿Qué cambio pequeño me ayudaría más?',
  ];
}
