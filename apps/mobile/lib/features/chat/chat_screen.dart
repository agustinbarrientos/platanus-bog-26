import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../data/api/api_client.dart';
import '../../data/models/biomarcador.dart';
import '../../data/models/chat.dart';
import '../../data/models/simulacion.dart';
import '../../data/repositories/chat_repository.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';
import 'voz_controller.dart';

/// Conversación en memoria para la sesión: salir y volver a la pantalla no la
/// pierde. Los mensajes `pendiente` son locales (turno en vuelo + burbuja
/// "escribiendo"); lo que va al backend es lo que no está pendiente.
class ChatHistoryNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => const [];

  /// Historial confirmado por el backend (sin turnos en vuelo).
  List<ChatMessage> get confirmado => state.where((m) => !m.pendiente).toList(growable: false);

  /// Agrega el turno del usuario de forma optimista, llama al agente (con el
  /// último resultado compacto y el `enfoque`, si lo hay) y reemplaza la
  /// lista con el `history` que devuelve. Si falla, deja la conversación como
  /// estaba y relanza para que la pantalla lo cuente.
  Future<ChatRespuesta> enviar(String texto, {String? enfoque}) async {
    final base = confirmado;
    state = [
      ...base,
      ChatMessage(role: 'user', content: texto, pendiente: true),
      const ChatMessage(role: 'assistant', content: '', pendiente: true),
    ];
    try {
      final r = await ref.read(chatRepositoryProvider).enviar(
        texto,
        base,
        resultado: ref.read(ultimoResultadoProvider),
        enfoque: enfoque,
        perfilConocimiento: ref.read(onboardingProvider).perfilConocimiento,
      );
      final nuevo = r.history.isNotEmpty
          ? r.history
          : [...base, ChatMessage(role: 'user', content: texto), ChatMessage(role: 'assistant', content: r.reply)];
      state = _conFuentes(nuevo, base, r.fuentes);
      return r;
    } catch (_) {
      state = base;
      rethrow;
    }
  }

  /// El backend devuelve el historial plano (`role` + `content`): conservo
  /// las fuentes que ya tenían los turnos anteriores y le pego las de esta
  /// respuesta al último mensaje del agente.
  static List<ChatMessage> _conFuentes(List<ChatMessage> nuevo, List<ChatMessage> previo, List<ChatFuente> fuentes) {
    return [
      for (var i = 0; i < nuevo.length; i++)
        if (i < previo.length && previo[i].role == nuevo[i].role && previo[i].content == nuevo[i].content && previo[i].fuentes.isNotEmpty)
          nuevo[i].copyWith(fuentes: previo[i].fuentes)
        else if (i == nuevo.length - 1 && !nuevo[i].esUsuario)
          nuevo[i].copyWith(fuentes: fuentes)
        else
          nuevo[i],
    ];
  }

  void reiniciar() => state = const [];
}

final chatHistoryProvider = NotifierProvider<ChatHistoryNotifier, List<ChatMessage>>(ChatHistoryNotifier.new);

/// "Pregúntale a Moirai": chat con la mascota, que responde con los datos
/// que el usuario ya me contó y con lo que vi en su última simulación
/// (agente del backend con recuperación por fragmentos). Se puede abrir
/// "sobre algo" ([enfoque], p. ej. `escenario:0` desde el detalle de una
/// palanca) y con una [preguntaInicial] que se envía sola al entrar.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.enfoque, this.preguntaInicial, this.enPestana = false});
  final String? enfoque;
  final String? preguntaInicial;

  /// `true` cuando vive como pestaña del shell (bottom nav): sin botón de
  /// volver. El historial es el mismo que el del chat a pantalla completa.
  final bool enPestana;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  bool _enviando = false;
  String? _aviso;
  String? _ultimoTexto;
  MascotMood _mood = MascotMood.idle;
  Timer? _moodTimer;

  /// Sobre qué se abrió el chat (va en cada turno hasta que el usuario lo quite).
  String? _enfoque;

  @override
  void initState() {
    super.initState();
    _enfoque = widget.enfoque;
    final q = widget.preguntaInicial?.trim();
    if (q != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enviar(q));
    }
  }

  @override
  void dispose() {
    // Salir de la pantalla calla a Moirai: nada peor que una voz que sigue
    // hablando de tu salud desde otra pantalla.
    ref.read(vozProvider.notifier).detener();
    _moodTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _irAlFinal() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(0, duration: Motion.slow, curve: Motion.out);
    });
  }

  void _setMood(MascotMood m, {Duration? volverA}) {
    _moodTimer?.cancel();
    if (!mounted) return;
    setState(() => _mood = m);
    if (volverA != null) {
      _moodTimer = Timer(volverA, () {
        if (mounted) setState(() => _mood = MascotMood.idle);
      });
    }
  }

  Future<void> _enviar(String texto) async {
    final t = texto.trim();
    if (t.isEmpty || _enviando) return;
    setState(() {
      _enviando = true;
      _aviso = null;
      _ultimoTexto = t;
    });
    _input.clear();
    _setMood(MascotMood.working);
    _irAlFinal();
    try {
      final r = await ref.read(chatHistoryProvider.notifier).enviar(t, enfoque: _enfoque);
      _setMood(MascotMood.happy, volverA: const Duration(milliseconds: 1800));
      // "Leer en voz alta" solo lee lo que llega nuevo; las respuestas
      // anteriores se leen tocando su altavoz.
      if (ref.read(lecturaEnVozAltaProvider)) unawaited(ref.read(vozProvider.notifier).hablar(r.reply));
    } on ApiException catch (e) {
      _setMood(MascotMood.gentle, volverA: const Duration(milliseconds: 2400));
      if (mounted) setState(() => _aviso = e.message);
    } catch (_) {
      _setMood(MascotMood.gentle, volverA: const Duration(milliseconds: 2400));
      if (mounted) setState(() => _aviso = 'No alcancé a responderte. ¿Tienes internet? Inténtalo de nuevo en un momento.');
    } finally {
      if (mounted) setState(() => _enviando = false);
      _irAlFinal();
    }
  }

  /// Micrófono: un toque graba, otro corta. Toque-y-corte en vez de
  /// mantener presionado — es más accesible y no castiga un dedo que se
  /// resbala a mitad de una pregunta larga.
  Future<void> _alternarMicrofono() async {
    final voz = ref.read(vozProvider.notifier);
    if (ref.read(vozProvider).grabando) {
      _setMood(MascotMood.working);
      final pregunta = await voz.detenerYTranscribir();
      if (!mounted) return;
      if (pregunta == null) {
        _setMood(MascotMood.gentle, volverA: const Duration(milliseconds: 2000));
        return;
      }
      await _enviar(pregunta);
      return;
    }
    if (await voz.grabar()) {
      _focus.unfocus();
      _setMood(MascotMood.working);
    } else if (mounted) {
      _setMood(MascotMood.gentle, volverA: const Duration(milliseconds: 2000));
    }
  }

  void _nuevaConversacion() {
    ref.read(chatHistoryProvider.notifier).reiniciar();
    setState(() {
      _aviso = null;
      _ultimoTexto = null;
    });
    _setMood(MascotMood.idle);
  }

  @override
  Widget build(BuildContext context) {
    final mensajes = ref.watch(chatHistoryProvider);
    final resultado = ref.watch(ultimoResultadoProvider);
    final vacio = mensajes.isEmpty && !_enviando;
    final t = Theme.of(context).textTheme;

    final voz = ref.watch(vozProvider);
    final leerEnVozAlta = ref.watch(lecturaEnVozAltaProvider);
    // Mientras suena la voz, la mascota está viva: es lo que hace que se
    // sienta un personaje hablando y no un audio pegado encima del chat.
    final mood = voz.leyendo ? MascotMood.happy : (voz.grabando ? MascotMood.working : _mood);

    return Scaffold(
      backgroundColor: MoiraiColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.enPestana,
        leading: widget.enPestana
            ? null
            : BackButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(Routes.future);
                  }
                },
              ),
        titleSpacing: widget.enPestana ? Sp.gutter : 0,
        title: Row(
          children: [
            MoiraiMascot(size: 36, halo: false, mood: mood),
            const SizedBox(width: Sp.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pregúntame', style: t.titleLarge),
                  Text(
                    voz.grabando
                        ? 'Te estoy escuchando…'
                        : voz.transcribiendo
                            ? 'Entendiendo lo que dijiste…'
                            : voz.leyendo
                                ? 'Leyéndote la respuesta'
                                : resultado == null
                                    ? 'Solo sé lo que me has contado de ti.'
                                    : 'Respondo con tus datos y tu última simulación.',
                    style: t.bodySmall!.copyWith(color: MoiraiColors.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: leerEnVozAlta ? 'No leer en voz alta' : 'Leer las respuestas en voz alta',
            isSelected: leerEnVozAlta,
            icon: Icon(leerEnVozAlta ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: leerEnVozAlta ? MoiraiColors.blueInk : MoiraiColors.ink3),
            onPressed: () {
              if (leerEnVozAlta) ref.read(vozProvider.notifier).detener();
              ref.read(lecturaEnVozAltaProvider.notifier).alternar();
            },
          ),
          IconButton(
            tooltip: 'Nueva conversación',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: mensajes.isEmpty || _enviando ? null : _nuevaConversacion,
          ),
          const SizedBox(width: Sp.x2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: vacio
                  ? _EstadoVacio(onPregunta: _enviar)
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x4, Sp.gutter, Sp.x4),
                      itemCount: mensajes.length,
                      itemBuilder: (context, i) {
                        final idx = mensajes.length - 1 - i;
                        final m = mensajes[idx];
                        final previo = idx > 0 ? mensajes[idx - 1] : null;
                        final primeroDeRacha = m.esUsuario ? false : (previo == null || previo.esUsuario);
                        final seguido = previo != null && previo.esUsuario == m.esUsuario;
                        return Padding(
                          key: ValueKey('$idx-${m.role}-${m.pendiente}'),
                          padding: EdgeInsets.only(top: seguido ? Sp.x2 : Sp.x4),
                          child: _Burbuja(mensaje: m, conAvatar: primeroDeRacha),
                        );
                      },
                    ),
            ),
            if (vacio && resultado != null) _PistasDeContexto(preguntas: ChatRepository.sugerenciasCon(resultado), onTap: _enviar),
            if (_enfoque != null)
              _ChipEnfoque(
                etiqueta: _etiquetaEnfoque(_enfoque!, resultado),
                onQuitar: () => setState(() => _enfoque = null),
              ),
            if (_aviso != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.x3),
                child: MoNotice(
                  text: _aviso!,
                  tone: MoTone.watch,
                  icon: Icons.wifi_tethering_off_rounded,
                  action: TextButton(
                    onPressed: _enviando || _ultimoTexto == null ? null : () => _enviar(_ultimoTexto!),
                    child: const Text('Reintentar'),
                  ),
                ).animate().fadeIn(duration: Motion.base).slideY(begin: .1, end: 0, curve: Motion.out, duration: Motion.base),
              ),
            if (voz.aviso != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.x3),
                child: MoNotice(
                  text: voz.aviso!,
                  tone: MoTone.watch,
                  icon: Icons.mic_off_rounded,
                  action: TextButton(
                    onPressed: ref.read(vozProvider.notifier).limpiarAviso,
                    child: const Text('Entendido'),
                  ),
                ).animate().fadeIn(duration: Motion.base).slideY(begin: .1, end: 0, curve: Motion.out, duration: Motion.base),
              ),
            _Composer(
              controller: _input,
              focusNode: _focus,
              enviando: _enviando,
              grabando: voz.grabando,
              transcribiendo: voz.transcribiendo,
              onSend: _enviar,
              onMicrofono: _alternarMicrofono,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Estado vacío ───────────────────────────────────────────────────────────

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.onPregunta});
  final ValueChanged<String> onPregunta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x4, Sp.gutter, Sp.x5),
      children: [
        const MoNotice(
          text: 'Estimación, no diagnóstico. Para decisiones clínicas, habla con un profesional.',
          icon: Icons.health_and_safety_outlined,
        ).stagger(0),
        const SizedBox(height: Sp.x8),
        const Center(child: MoiraiMascot(size: 96)).stagger(1),
        const SizedBox(height: Sp.x4),
        // Quién es: la medusa que sabe devolver su reloj. Una línea, una vez.
        Text(
          'Moirai · medusa Turritopsis dohrnii',
          textAlign: TextAlign.center,
          style: t.labelMedium!.copyWith(color: MoiraiColors.ink3, letterSpacing: .4),
        ).stagger(2),
        const SizedBox(height: Sp.x4),
        Text(
          'Pregúntame lo que quieras sobre tus datos',
          textAlign: TextAlign.center,
          style: t.headlineSmall,
        ).stagger(3),
        const SizedBox(height: Sp.x3),
        Text(
          'Respondo con lo que tengo guardado de ti —perfil, exámenes, edad biológica— y con lo que vi en tu última simulación: tus palancas, tu rango, el porqué. Debajo de cada respuesta te digo qué leí.',
          textAlign: TextAlign.center,
          style: t.bodyMedium!.copyWith(color: MoiraiColors.ink2),
        ).stagger(4),
        const SizedBox(height: Sp.x7),
        Wrap(
          spacing: Sp.x3,
          runSpacing: Sp.x3,
          alignment: WrapAlignment.center,
          children: [
            for (final (i, s) in ChatRepository.sugerencias.indexed)
              MoChoice(
                label: s,
                selected: false,
                icon: Icons.chat_bubble_outline_rounded,
                onTap: () => onPregunta(s),
              ).stagger(5 + i),
          ],
        ),
      ],
    );
  }
}

// ─── Pistas con el último resultado ─────────────────────────────────────────

class _PistasDeContexto extends StatelessWidget {
  const _PistasDeContexto({required this.preguntas, required this.onTap});
  final List<String> preguntas;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.gutter, vertical: Sp.x2),
        itemCount: preguntas.length,
        separatorBuilder: (_, _) => const SizedBox(width: Sp.x3),
        itemBuilder: (context, i) {
          final p = preguntas[i];
          return Material(
            color: MoiraiColors.actionSoft,
            shape: StadiumBorder(side: BorderSide(color: MoiraiColors.action.withValues(alpha: .25))),
            child: InkWell(
              onTap: () => onTap(p),
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 15, color: MoiraiColors.blueInk),
                    const SizedBox(width: 6),
                    Text(p, style: t.labelLarge!.copyWith(color: MoiraiColors.blueInk, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ).stagger(i, base: const Duration(milliseconds: 80));
        },
      ),
    );
  }
}

// ─── Burbujas ───────────────────────────────────────────────────────────────

class _Burbuja extends ConsumerWidget {
  const _Burbuja({required this.mensaje, required this.conAvatar});
  final ChatMessage mensaje;
  final bool conAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esUsuario = mensaje.esUsuario;
    final escribiendo = !esUsuario && mensaje.pendiente;
    final maxAncho = MediaQuery.sizeOf(context).width * .78;
    final t = Theme.of(context).textTheme;

    final radio = esUsuario
        ? const BorderRadius.only(
            topLeft: Radius.circular(Rad.lg),
            topRight: Radius.circular(Rad.lg),
            bottomLeft: Radius.circular(Rad.lg),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(Rad.lg),
            topRight: Radius.circular(Rad.lg),
            bottomRight: Radius.circular(Rad.lg),
            bottomLeft: Radius.circular(6),
          );

    final burbuja = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxAncho),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: esUsuario ? MoiraiColors.action : MoiraiColors.surface,
          borderRadius: radio,
          border: esUsuario ? null : Border.all(color: MoiraiColors.line),
          boxShadow: esUsuario
              ? [BoxShadow(color: MoiraiColors.action.withValues(alpha: .22), blurRadius: 12, offset: const Offset(0, 4))]
              : [BoxShadow(color: MoiraiColors.ink.withValues(alpha: .04), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: escribiendo ? 14 : 12),
          child: escribiendo
              ? const _PuntosEscribiendo()
              : esUsuario
                  ? Text(mensaje.content, style: t.bodyLarge!.copyWith(color: Colors.white, height: 1.4))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TextoConNegritas(mensaje.content, style: t.bodyLarge!.copyWith(color: MoiraiColors.ink, height: 1.45)),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BotonAltavoz(texto: mensaje.content),
                            const SizedBox(width: Sp.x2),
                            if (mensaje.fuentes.isNotEmpty)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: _FuentesLinea(fuentes: mensaje.fuentes),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );

    final fila = Row(
      mainAxisAlignment: esUsuario ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!esUsuario) ...[
          SizedBox(
            width: 30,
            height: 30,
            child: conAvatar ? MoiraiMascot(size: 30, halo: false, mood: escribiendo ? MascotMood.working : MascotMood.idle) : null,
          ),
          const SizedBox(width: Sp.x3),
        ],
        Flexible(child: burbuja),
      ],
    );

    return fila
        .animate()
        .fadeIn(duration: Motion.slow, curve: Motion.out)
        .slideY(begin: .12, end: 0, duration: Motion.slow, curve: Motion.out)
        .slideX(begin: esUsuario ? .04 : -.04, end: 0, duration: Motion.slow, curve: Motion.out);
  }
}

/// Altavoz de una respuesta: la lee en voz de Moirai, o la calla si ya la
/// estaba leyendo. Discreto a propósito — la respuesta escrita sigue siendo
/// la principal; la voz es una ayuda, no el canal.
///
/// Cuando el audio viene del teléfono (sin voz configurada, sin créditos, o
/// modo demo sin red) el ícono lo dice. Es la misma regla que el resto del
/// producto: nunca hacer pasar una aproximación por lo real.
class _BotonAltavoz extends ConsumerWidget {
  const _BotonAltavoz({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voz = ref.watch(vozProvider);
    final activo = voz.hablando == texto;
    final preparando = activo && voz.preparando;
    final local = activo && voz.fuente == VozFuente.dispositivo;

    return Semantics(
      button: true,
      label: activo ? 'Dejar de leer en voz alta' : 'Leer esta respuesta en voz alta',
      child: SizedBox(
        width: 34,
        height: 34,
        child: Material(
          color: activo ? MoiraiColors.blueSoft : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => ref.read(vozProvider.notifier).alternar(texto),
            child: Center(
              child: preparando
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: MoiraiColors.blue),
                    )
                  : Icon(
                      activo
                          ? Icons.stop_rounded
                          : local
                              ? Icons.phonelink_ring_rounded
                              : Icons.volume_up_rounded,
                      size: 18,
                      color: activo ? MoiraiColors.blueInk : MoiraiColors.ink3,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Esto es lo que leí": los fragmentos en los que se apoyó la respuesta,
/// como una línea discreta bajo el texto. Tus datos y tu simulación primero;
/// lo de "cómo funciona el motor" al final.
class _FuentesLinea extends StatelessWidget {
  const _FuentesLinea({required this.fuentes});
  final List<ChatFuente> fuentes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final orden = [...fuentes.where((f) => f.esDeMisDatos || f.esDelResultado), ...fuentes.where((f) => !f.esDeMisDatos && !f.esDelResultado)];
    final titulos = <String>[];
    for (final f in orden) {
      if (!titulos.contains(f.titulo)) titulos.add(f.titulo);
    }
    final visibles = titulos.take(3).toList();
    final extra = titulos.length - visibles.length;
    final texto = 'Leí: ${visibles.join(' · ')}${extra > 0 ? ' · +$extra más' : ''}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.menu_book_outlined, size: 13, color: MoiraiColors.ink3),
        ),
        const SizedBox(width: 5),
        Flexible(child: Text(texto, style: t.labelSmall!.copyWith(color: MoiraiColors.ink3, letterSpacing: 0, height: 1.3))),
      ],
    );
  }
}

/// Sobre qué se abrió el chat (p. ej. una palanca). Se puede quitar.
class _ChipEnfoque extends StatelessWidget {
  const _ChipEnfoque({required this.etiqueta, required this.onQuitar});
  final String etiqueta;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x2, Sp.gutter, Sp.x2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: MoiraiColors.blueSoft,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.center_focus_strong_rounded, size: 15, color: MoiraiColors.blueInk),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Hablando de: $etiqueta',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelMedium!.copyWith(color: MoiraiColors.blueInk, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: onQuitar,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  iconSize: 16,
                  icon: const Icon(Icons.close_rounded, color: MoiraiColors.blueInk),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: Motion.base);
  }
}

/// Etiqueta legible de un `enfoque` (misma gramática que usa el backend).
String _etiquetaEnfoque(String enfoque, SimulacionResultado? r) {
  final partes = enfoque.split(':');
  switch (partes.first) {
    case 'escenario':
      final i = partes.length > 1 ? int.tryParse(partes[1]) : null;
      if (r != null && i != null && i >= 0 && i < r.escenarios.length) return r.escenarios[i].etiqueta;
      return 'esta palanca';
    case 'biomarcador':
      return partes.length > 1 ? (BiomarcadorDef.byId(partes[1])?.nombre ?? partes[1]) : 'este dato';
    case 'porque':
      return 'el porqué';
    case 'incertidumbre':
    case 'banda':
      return 'tu rango';
    case 'medir':
      return 'qué medir';
    case 'poblacion':
      return 'tu percentil';
    default:
      return enfoque.replaceAll('_', ' ');
  }
}

/// Texto plano con soporte mínimo de **negritas** (se parte por `**`).
class _TextoConNegritas extends StatelessWidget {
  const _TextoConNegritas(this.texto, {required this.style});
  final String texto;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final partes = texto.split('**');
    if (partes.length < 3) return Text(texto, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (i, p) in partes.indexed)
            if (p.isNotEmpty) TextSpan(text: p, style: i.isOdd ? style.copyWith(fontWeight: FontWeight.w800) : null),
        ],
      ),
    );
  }
}

/// Tres puntos que respiran en cascada mientras el agente responde.
class _PuntosEscribiendo extends StatelessWidget {
  const _PuntosEscribiendo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: MoiraiColors.blue, shape: BoxShape.circle),
          )
              .animate(onPlay: (c) => c.repeat(), delay: Duration(milliseconds: 160 * i))
              .fade(begin: .35, end: 1, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut)
              .scaleXY(begin: .7, end: 1, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut)
              .then()
              .fade(begin: 1, end: .35, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut)
              .scaleXY(begin: 1, end: .7, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut)
              .then(delay: const Duration(milliseconds: 200)),
        ],
      ],
    );
  }
}

// ─── Composer ───────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enviando,
    required this.grabando,
    required this.transcribiendo,
    required this.onSend,
    required this.onMicrofono,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enviando;
  final bool grabando;
  final bool transcribiendo;
  final ValueChanged<String> onSend;
  final VoidCallback onMicrofono;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MoiraiColors.bg,
        border: Border(top: BorderSide(color: MoiraiColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x3, Sp.x4, Sp.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: grabando
                  ? const _Escuchando()
                  : TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !transcribiendo,
                      maxLength: ChatRepository.maxMessage,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      onSubmitted: enviando ? null : onSend,
                      decoration: InputDecoration(
                        hintText: transcribiendo ? 'Entendiendo lo que dijiste…' : 'Escríbeme o tócame el micrófono',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5)),
                        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.blue, width: 2)),
                      ),
                    ),
            ),
            const SizedBox(width: Sp.x3),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                // Un solo botón: micrófono cuando no hay nada escrito, flecha
                // cuando sí. Es el gesto que la gente ya conoce, y deja el
                // área táctil de 50 px en vez de partirla en dos botones.
                final hayTexto = controller.text.trim().isNotEmpty;
                final esMicro = !hayTexto && !enviando;
                final ocupado = enviando || transcribiendo;

                return SizedBox(
                  width: 50,
                  height: 50,
                  child: IconButton.filled(
                    tooltip: grabando
                        ? 'Terminé de hablar'
                        : esMicro
                            ? 'Hazme una pregunta hablando'
                            : 'Enviar',
                    onPressed: ocupado ? null : (esMicro || grabando ? onMicrofono : () => onSend(controller.text)),
                    style: IconButton.styleFrom(
                      backgroundColor: grabando ? MoiraiColors.blueInk : MoiraiColors.action,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: MoiraiColors.surface2,
                      disabledForegroundColor: MoiraiColors.ink3,
                    ),
                    icon: ocupado
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: MoiraiColors.ink3))
                        : grabando
                            ? const Icon(Icons.stop_rounded, size: 24)
                            : esMicro
                                ? const Icon(Icons.mic_rounded, size: 24)
                                : const Icon(Icons.arrow_upward_rounded, size: 24),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Reemplaza al campo de texto mientras Moirai escucha. Barras que respiran
/// —no un nivel de audio real: fingir un medidor sería mentir sobre lo que
/// estoy midiendo— y una sola línea que dice qué hacer para terminar.
class _Escuchando extends StatelessWidget {
  const _Escuchando();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: MoiraiColors.blueSoft,
        borderRadius: BorderRadius.circular(Rad.card),
        border: Border.all(color: MoiraiColors.blue, width: 1.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(color: MoiraiColors.blue, borderRadius: BorderRadius.circular(2)),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true), delay: Duration(milliseconds: 130 * i))
                .scaleY(begin: .4, end: 1.35, duration: const Duration(milliseconds: 520), curve: Curves.easeInOut),
          ],
          const SizedBox(width: Sp.x3),
          Expanded(
            child: Text(
              'Te escucho. Toca para terminar.',
              style: t.bodyMedium!.copyWith(color: MoiraiColors.blueInk, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
