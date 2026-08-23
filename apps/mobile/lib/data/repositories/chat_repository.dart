import '../../core/env.dart';
import '../../core/format.dart';
import '../api/api_client.dart';
import '../mock/mock_engine.dart';
import '../models/chat.dart';
import '../models/simulacion.dart';

/// `POST /me/health-context/chat`: Moirai responde apoyada en fragmentos
/// recuperados (RAG léxico en el backend) de tus datos guardados, de la
/// simulación que le mando compacta (`resultado`, ver
/// `SimulacionResultado.toChatJson`) y de una base de conocimiento del motor.
/// Stateless: se le devuelve el `history` que él entrega. Máximo 4.000
/// caracteres por mensaje y 40 turnos de historial. `enfoque` le dice desde
/// dónde se abrió el chat (`escenario:<i>`, `porque`, `incertidumbre`,
/// `biomarcador:<nombre>`, `medir`, `poblacion`) para sesgar la recuperación.
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  static const maxHistory = 40;
  static const maxMessage = 4000;

  /// `perfilConocimiento` (`general | curioso | profesional`, del onboarding)
  /// le dice al agente qué tanto vocabulario puede dar por sabido; va en
  /// cada turno para que el registro sea el correcto aunque el sync del
  /// onboarding no haya llegado al backend.
  Future<ChatRespuesta> enviar(
    String message,
    List<ChatMessage> history, {
    SimulacionResultado? resultado,
    String? enfoque,
    String? perfilConocimiento,
  }) async {
    final msg = message.trim();
    final hist = history.where((m) => !m.pendiente).toList();
    final recortado = hist.length > maxHistory ? hist.sublist(hist.length - maxHistory) : hist;
    if (Env.useMockEngine) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final (reply, fuentes) = _mock(msg, resultado, enfoque);
      return ChatRespuesta(
        reply: reply,
        history: [...recortado, ChatMessage(role: 'user', content: msg), ChatMessage(role: 'assistant', content: reply)],
        fuentes: fuentes,
      );
    }
    final j = (await _api.post(
      '/me/health-context/chat',
      body: {
        'message': msg.length > maxMessage ? msg.substring(0, maxMessage) : msg,
        'history': recortado.map((m) => m.toJson()).toList(),
        if (resultado != null) 'resultado': resultado.toChatJson(),
        if (enfoque != null && enfoque.trim().isNotEmpty) 'enfoque': enfoque.trim(),
        'perfil_conocimiento': ?perfilConocimiento,
      },
      timeout: const Duration(seconds: 120),
    ) as Map)
        .cast<String, dynamic>();
    return ChatRespuesta.fromJson(j);
  }

  /// Preguntas sugeridas para arrancar la conversación sin resultado aún.
  static const sugerencias = <String>[
    '¿Qué significa mi edad biológica frente a mi edad?',
    '¿Cuál de mis datos pesa más en el resultado?',
    '¿Qué examen me conviene hacerme primero?',
    '¿Qué cambio pequeño me ayudaría más?',
    '¿Quién eres?',
  ];

  /// Sugerencias cuando ya hay un resultado: apuntan a lo que está en pantalla.
  static List<String> sugerenciasCon(SimulacionResultado r) {
    final c = r.baseline;
    return [
      if (r.escenarios.isNotEmpty) '¿Por qué ${r.mejorDecision.etiqueta.toLowerCase()} es mi primera palanca?',
      if (c.p10.isNotEmpty && c.p90.isNotEmpty) '¿Qué significa mi rango de ${Fmt.decimal(c.p10.last)} a ${Fmt.decimal(c.p90.last)}?',
      if (r.shap.isNotEmpty) '¿Por qué ${MockEngine.nombreVariable(r.shap.first.variable)} pesa tanto?',
      '¿Qué examen me conviene hacerme primero?',
      '¿Cómo estoy frente a personas de mi edad?',
    ];
  }

  // ── Modo demo sin red ────────────────────────────────────────────────────

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n');

  static bool _tiene(String m, List<String> claves) => claves.any(m.contains);

  /// Mini-RAG local: elige una plantilla según palabras clave y la rellena
  /// con el resultado. Es la misma idea que el backend (recuperar solo lo
  /// relevante), en pequeño, para que la demo sin red se sienta viva.
  static (String, List<ChatFuente>) _mock(String msg, SimulacionResultado? r, String? enfoque) {
    const demo = 'Estoy en modo demo sin conexión, así que respondo con lo que tengo en el dispositivo.';
    if (r == null) {
      return ('$demo Todavía no tengo una simulación tuya: córrela desde Futuro y después te cuento qué palanca te gana más años y por qué.', const []);
    }
    final m = _norm(msg);
    ChatFuente f(String id, String titulo, String grupo) => ChatFuente(id: id, titulo: titulo, grupo: grupo);

    Escenario? enfocado;
    if (enfoque != null && enfoque.startsWith('escenario:')) {
      final i = int.tryParse(enfoque.split(':').last) ?? -1;
      if (i >= 0 && i < r.escenarios.length) enfocado = r.escenarios[i];
    }

    String palanca(Escenario e, int rank) {
      final rango = e.rango.length >= 2 ? ' (${Fmt.rangoDelta(e.rango[0], e.rango[1])})' : '';
      return '${e.etiqueta} es tu palanca #$rank: ${Fmt.delta(e.aniosGanados)} años a 10 años$rango, esfuerzo ${e.esfuerzo} de 10, '
          'y el ${Fmt.pct(e.pctMejoran)} de tus futuros mejoran con ella. Las ordené por años ganados por unidad de esfuerzo. Estimación, no diagnóstico.';
    }

    if (enfocado != null && (m.length < 40 || _tiene(m, ['esta', 'esto', 'palanca']))) {
      final i = r.escenarios.indexOf(enfocado);
      return ('$demo ${palanca(enfocado, i + 1)}', [f('sim:escenario:$i', 'Palanca #${i + 1}: ${enfocado.etiqueta}', 'resultado')]);
    }
    if (_tiene(m, ['quien eres', 'que eres', 'medusa', 'quien es moirai', 'como te llamas'])) {
      return (
        'Soy Moirai, una medusa Turritopsis dohrnii: el único animal que, cuando se estresa o envejece, devuelve su reloj celular a un estado juvenil en vez de morir. '
        'Yo no puedo hacer eso contigo —nadie puede—, pero sí simulo miles de versiones de tu futuro y te muestro cuál de tus hábitos lo mueve más. No tejo tu destino: te enseño a hilarlo.',
        const [],
      );
    }
    if (_tiene(m, ['rango', 'banda', 'segur', 'incertid', 'ancho', 'confia'])) {
      return (
        '$demo ${r.incertidumbre} La banda P10–P90 es lo que todavía no sé de ti: el 80 % de tus futuros simulados cae dentro. Medir lo que hoy imputo la angosta.',
        [f('sim:incertidumbre', 'Qué tan seguro estoy de este resultado', 'resultado'), f('kb:banda', 'Cómo leer el rango (banda P10–P90)', 'conocimiento')],
      );
    }
    if (_tiene(m, ['medir', 'examen', 'prueba', 'falta', 'laborator'])) {
      final inferidos = r.biomarcadoresUsados.where((b) => b.inferido).map((b) => b.nombre).toList();
      final texto = inferidos.isEmpty
          ? 'Tengo tus 9 biomarcadores de PhenoAge medidos: la banda ya es la más angosta que puedo darte.'
          : 'Hoy imputo ${inferidos.length} de 9 biomarcadores (${inferidos.join(', ')}). Medirlos no cambia tu salud: cambia lo que yo sé de ti, y por eso angosta el rango.';
      return ('$demo $texto', [f('faltantes', 'Lo que me falta de ti', 'usuario'), f('kb:que_medir', 'Qué conviene medir primero', 'conocimiento')]);
    }
    if (_tiene(m, ['porque', 'por que', 'pesa', 'influ', 'causa'])) {
      final top = r.shap.take(3).map((d) => '${MockEngine.nombreVariable(d.variable)} ${Fmt.delta(d.contribucion)} años').join(', ');
      return (
        '$demo ${r.porque} ${top.isEmpty ? '' : 'Lo que más pesa hoy: $top (aproximación tipo SHAP sobre tu estado de hoy).'}',
        [f('sim:porque', 'Por qué: qué pesa en tu edad biológica de hoy', 'resultado')],
      );
    }
    if (_tiene(m, ['percentil', 'promedio', 'gente', 'personas', 'poblacion'])) {
      return ('$demo Estás en el percentil ${r.percentilPoblacional} de edad biológica frente a personas de tu edad y sexo (referencia NHANES). ${r.mensajePoblacional}', [f('sim:poblacion', 'Frente a personas como tú', 'resultado')]);
    }
    if (_tiene(m, ['palanca', 'hacer', 'cambi', 'mejor', 'recomiend', 'empez', 'habito'])) {
      if (r.escenarios.isEmpty) return ('$demo No encontré una palanca que mueva tu futuro lo suficiente: lo que ya haces es la razón de este resultado.', [f('sim:resumen', 'Tu última simulación, en resumen', 'resultado')]);
      return ('$demo ${palanca(r.mejorDecision, 1)} ${r.porque}', [f('sim:mejor_decision', 'Tu mejor palanca', 'resultado')]);
    }
    final c = r.baseline;
    final proy = c.mediana.isNotEmpty ? ' Si sigues igual, en 10 años estaría en ${Fmt.decimal(c.final_)} (${Fmt.rango(c.p10.last, c.p90.last)}).' : '';
    return (
      '$demo Hoy tu edad biológica es ${Fmt.decimal(r.edadBiologicaHoy)} frente a tus ${r.edadCronologica} años.$proy Puedo contarte de tus palancas, tu rango, el porqué y qué medir.',
      [f('phenoage', 'Tu edad biológica hoy (PhenoAge)', 'usuario'), f('sim:resumen', 'Tu última simulación, en resumen', 'resultado')],
    );
  }
}
