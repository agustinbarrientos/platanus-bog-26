import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/api/api_client.dart';
import '../../data/models/chat.dart';
import '../../data/repositories/chat_repository.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// Conversación en memoria para la sesión: salir y volver a la pantalla no la
/// pierde. Los mensajes `pendiente` son locales (turno en vuelo + burbuja
/// "escribiendo"); lo que va al backend es lo que no está pendiente.
class ChatHistoryNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => const [];

  /// Historial confirmado por el backend (sin turnos en vuelo).
  List<ChatMessage> get confirmado => state.where((m) => !m.pendiente).toList(growable: false);

  /// Agrega el turno del usuario de forma optimista, llama al agente y
  /// reemplaza la lista con el `history` que devuelve. Si falla, deja la
  /// conversación como estaba y relanza para que la pantalla lo cuente.
  Future<ChatRespuesta> enviar(String texto) async {
    final base = confirmado;
    state = [
      ...base,
      ChatMessage(role: 'user', content: texto, pendiente: true),
      const ChatMessage(role: 'assistant', content: '', pendiente: true),
    ];
    try {
      final r = await ref.read(chatRepositoryProvider).enviar(texto, base);
      state = r.history.isNotEmpty
          ? r.history
          : [...base, ChatMessage(role: 'user', content: texto), ChatMessage(role: 'assistant', content: r.reply)];
      return r;
    } catch (_) {
      state = base;
      rethrow;
    }
  }

  void reiniciar() => state = const [];
}

final chatHistoryProvider = NotifierProvider<ChatHistoryNotifier, List<ChatMessage>>(ChatHistoryNotifier.new);

/// "Pregúntale a Moirai": chat con la mascota, que responde solo con los
/// datos que el usuario ya me contó (agente del backend).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

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

  @override
  void dispose() {
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
      await ref.read(chatHistoryProvider.notifier).enviar(t);
      _setMood(MascotMood.happy, volverA: const Duration(milliseconds: 1800));
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

    return Scaffold(
      backgroundColor: MoiraiColors.bg,
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.future);
            }
          },
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            MoiraiMascot(size: 36, mood: _mood),
            const SizedBox(width: Sp.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pregúntame', style: t.titleLarge),
                  Text(
                    'Solo sé lo que me has contado de ti.',
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
            if (vacio && resultado != null)
              _PistasDeContexto(
                preguntas: [
                  '¿Por qué mi edad biológica es ${Fmt.decimal(resultado.edadBiologicaHoy)}?',
                  '¿Qué pasa si ${resultado.mejorDecision.etiqueta.toLowerCase()}?',
                  '¿Qué tan ancho es mi rango y por qué?',
                ],
                onTap: _enviar,
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
            _Composer(
              controller: _input,
              focusNode: _focus,
              enviando: _enviando,
              onSend: _enviar,
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
        const SizedBox(height: Sp.x5),
        Text(
          'Pregúntame lo que quieras sobre tus datos',
          textAlign: TextAlign.center,
          style: t.headlineSmall,
        ).stagger(2),
        const SizedBox(height: Sp.x3),
        Text(
          'Respondo con lo que tengo guardado de ti: tu perfil, tus exámenes y tu edad biológica si ya la calculé.',
          textAlign: TextAlign.center,
          style: t.bodyMedium!.copyWith(color: MoiraiColors.ink2),
        ).stagger(3),
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
              ).stagger(4 + i),
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

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje, required this.conAvatar});
  final ChatMessage mensaje;
  final bool conAvatar;

  @override
  Widget build(BuildContext context) {
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
                  : _TextoConNegritas(mensaje.content, style: t.bodyLarge!.copyWith(color: MoiraiColors.ink, height: 1.45)),
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
            child: conAvatar ? MoiraiMascot(size: 30, mood: escribiendo ? MascotMood.working : MascotMood.idle) : null,
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
  const _Composer({required this.controller, required this.focusNode, required this.enviando, required this.onSend});
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enviando;
  final ValueChanged<String> onSend;

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
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                maxLength: ChatRepository.maxMessage,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                onSubmitted: enviando ? null : onSend,
                decoration: InputDecoration(
                  hintText: 'Escríbeme una pregunta',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.line, width: 1.5)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rad.card), borderSide: const BorderSide(color: MoiraiColors.blue, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: Sp.x3),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final activo = !enviando && controller.text.trim().isNotEmpty;
                return SizedBox(
                  width: 50,
                  height: 50,
                  child: IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: activo ? () => onSend(controller.text) : null,
                    style: IconButton.styleFrom(
                      backgroundColor: MoiraiColors.action,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: MoiraiColors.surface2,
                      disabledForegroundColor: MoiraiColors.ink3,
                    ),
                    icon: enviando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: MoiraiColors.ink3))
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
