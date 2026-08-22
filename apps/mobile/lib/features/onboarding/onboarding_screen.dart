import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/api/api_client.dart';
import '../../data/models/me.dart';
import '../../data/models/onboarding.dart';
import '../../data/models/simulacion.dart';
import '../../widgets/fan_chart.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';
import 'onboarding_widgets.dart';
import 'pasos_basicos.dart';
import 'pasos_extras.dart';
import 'pasos_habitos.dart';

/// A2 · Onboarding. Un dato por pantalla; el abanico de la esquina se va
/// cerrando con cada respuesta. Lo básico (nombre, nacimiento, sexo, medidas,
/// sangre) va a `/me`; el resto vive en `onboardingProvider` (local, se
/// persiste en cada cambio) hasta que exista `PUT /me/perfil`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Paso {
  identidad,
  cuerpo,
  origen,
  objetivos,
  familia,
  sueno,
  ejercicio,
  alcohol,
  alimentacion,
  suplementos,
  wearables,
  foto,
  genetica,
  resumen,
}

/// Resultado de mandar lo pendiente a `/me`.
enum _Sync { ok, campos, despertando }

const _avisoDespertando = 'El servidor está despertando. Guardo tus respuestas aquí y las reintento en el siguiente paso.';

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pasos = _Paso.values;

  /// Pasos con datos (el resumen no cuenta).
  static const _datos = 13;

  final _page = PageController();
  int _i = 0;
  bool _avanzando = false;
  bool _prefillHecho = false;

  // Paso a/b: viven aquí porque van al backend y se validan al avanzar.
  final _nombre = TextEditingController();
  final _estatura = TextEditingController();
  final _peso = TextEditingController();
  DateTime? _nacimiento;
  SexAtBirth? _sexo;
  String? _sangre;

  Map<String, String> _errores = const {};
  String? _aviso;

  /// Campos que faltan por confirmar en `/me` (se reintentan en cada paso).
  final _pendiente = <String, dynamic>{};

  /// Último valor que el backend aceptó por campo (para no reenviar igual).
  final _confirmado = <String, dynamic>{};
  Future<void> _cola = Future.value();

  @override
  void initState() {
    super.initState();
    final meta = ref.read(authRepositoryProvider).user?.userMetadata;
    final n = meta?['full_name'];
    if (n is String && n.trim().isNotEmpty) _nombre.text = n.trim();
    _despertar();
  }

  @override
  void dispose() {
    _page.dispose();
    _nombre.dispose();
    _estatura.dispose();
    _peso.dispose();
    super.dispose();
  }

  /// Despierta el backend (Render tarda 30–50 s en frío) sin bloquear nada,
  /// y rellena lo que ya exista en `/me`.
  Future<void> _despertar() async {
    try {
      final me = await ref.read(meProvider.future);
      if (mounted) _prefill(me);
    } catch (_) {
      // Se reintenta solo con el primer PATCH.
    }
  }

  void _prefill(Me me) {
    if (_prefillHecho) return;
    _prefillHecho = true;
    final p = me.profile;
    setState(() {
      if (_nombre.text.isEmpty && (p.fullName ?? '').isNotEmpty) _nombre.text = p.fullName!;
      _nacimiento ??= p.dateOfBirth;
      _sexo ??= p.sexAtBirth;
      if (_estatura.text.isEmpty && p.heightCm != null) _estatura.text = Fmt.entero(p.heightCm!);
      if (_peso.text.isEmpty && p.weightKg != null) _peso.text = Fmt.corto(p.weightKg!);
      _sangre ??= p.bloodType;
    });
    if (p.fullName != null) _confirmado['full_name'] = p.fullName;
    if (p.dateOfBirth != null) _confirmado['date_of_birth'] = _iso(p.dateOfBirth!);
    if (p.sexAtBirth != null) _confirmado['sex_at_birth'] = p.sexAtBirth!.api;
    if (p.heightCm != null) _confirmado['height_cm'] = p.heightCm;
    if (p.weightKg != null) _confirmado['weight_kg'] = p.weightKg;
    if (p.bloodType != null) _confirmado['blood_type'] = p.bloodType;
  }

  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  int _edad(Me? me) => Profile(dateOfBirth: _nacimiento).edad ?? me?.profile.edad ?? 40;

  // ── Sincronización con /me ─────────────────────────────────────────────
  void _encolar(Map<String, dynamic> campos) {
    campos.forEach((k, v) {
      if (_confirmado[k] != v) _pendiente[k] = v;
    });
  }

  /// Manda lo pendiente (en serie, nunca dos PATCH a la vez). Los efectos
  /// (errores por campo, avisos) se aplican aquí mismo cuando llega la
  /// respuesta, aunque el usuario ya haya avanzado.
  Future<_Sync> _enviar() {
    if (_pendiente.isEmpty) return Future.value(_Sync.ok);
    final envio = Map<String, dynamic>.from(_pendiente);
    final f = _cola.then((_) => _patch(envio));
    _cola = f.then((_) {});
    return f;
  }

  Future<_Sync> _patch(Map<String, dynamic> envio) async {
    try {
      await ref.read(profileRepositoryProvider).patchMe(envio);
      ref.invalidate(meProvider);
      _confirmado.addAll(envio);
      envio.forEach((k, v) {
        if (_pendiente[k] == v) _pendiente.remove(k);
      });
      if (mounted) setState(() => _aviso = null);
      return _Sync.ok;
    } on ApiException catch (e) {
      if (!mounted) return _Sync.despertando;
      if (e.statusCode == 422 || e.statusCode == 400) {
        // Lo que el backend rechazó se saca de la cola: hay que corregirlo.
        _pendiente.removeWhere((k, _) => envio.containsKey(k));
        setState(() {
          _errores = {..._errores, ...e.fields};
          _aviso = e.fields.isEmpty ? e.message : 'Hay un dato que no me cuadra: ${e.message}';
        });
        return _Sync.campos;
      }
      setState(() => _aviso = e.statusCode == 401 ? e.message : _avisoDespertando);
      return _Sync.despertando;
    } catch (_) {
      if (mounted) setState(() => _aviso = _avisoDespertando);
      return _Sync.despertando;
    }
  }

  void _reintentar() {
    setState(() => _aviso = 'Reintentando…');
    _enviar();
  }

  // ── Validación local de a/b ────────────────────────────────────────────
  Set<String> _camposDe(_Paso p) => switch (p) {
        _Paso.identidad => const {'full_name', 'date_of_birth', 'sex_at_birth'},
        _Paso.cuerpo => const {'height_cm', 'weight_kg', 'blood_type'},
        _ => const {},
      };

  bool _validarIdentidad() {
    final err = <String, String>{};
    if (_nacimiento == null) err['date_of_birth'] = 'Necesito tu fecha de nacimiento para calcular tu edad.';
    if (_sexo == null) err['sex_at_birth'] = 'Elige una opción; me sirve para las curvas de referencia.';
    if (_nombre.text.trim().length > 120) err['full_name'] = 'Con un nombre más corto me basta.';
    setState(() => _errores = err);
    if (err.isNotEmpty) return false;
    _encolar({
      if (_nombre.text.trim().isNotEmpty) 'full_name': _nombre.text.trim(),
      'date_of_birth': _iso(_nacimiento!),
      'sex_at_birth': _sexo!.api,
    });
    return true;
  }

  bool _validarCuerpo() {
    final err = <String, String>{};
    final h = _num(_estatura.text);
    final w = _num(_peso.text);
    if (h == null || h < 100 || h > 250) err['height_cm'] = 'Necesito una estatura entre 100 y 250 cm.';
    if (w == null || w < 25 || w > 350) err['weight_kg'] = 'Necesito un peso entre 25 y 350 kg.';
    setState(() => _errores = err);
    if (err.isNotEmpty) return false;
    _encolar({'height_cm': h, 'weight_kg': w, if (_sangre != null) 'blood_type': _sangre});
    return true;
  }

  // ── Navegación ─────────────────────────────────────────────────────────
  bool _valido(_Paso p, OnboardingData ob) => switch (p) {
        _Paso.origen => ob.nacionalidad != null && ob.paisResidencia != null && ob.ancestria != null,
        _Paso.objetivos => ob.objetivos.isNotEmpty,
        _Paso.familia => ob.historialFamiliar.isNotEmpty,
        _Paso.sueno => ob.suenoCalidad != null,
        _Paso.ejercicio => ob.ejercicio != null,
        _Paso.alcohol => ob.alcoholFrecuencia != null && ob.tabaco != null,
        _Paso.alimentacion => ob.alimentacion != null && ob.estres != null,
        _ => true,
      };

  void _ir(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _i = i);
    _page.animateToPage(i, duration: Motion.slow, curve: Motion.out);
  }

  Future<void> _siguiente() async {
    if (_avanzando) return;
    final paso = _pasos[_i];
    FocusScope.of(context).unfocus();
    if (paso == _Paso.identidad && !_validarIdentidad()) return;
    if (paso == _Paso.cuerpo && !_validarCuerpo()) return;

    if (_pendiente.isNotEmpty) {
      setState(() => _avanzando = true);
      // Espero hasta 10 s; si el servidor sigue despertando, sigo y reintento.
      final r = await Future.any([
        _enviar(),
        Future.delayed(const Duration(seconds: 10), () => _Sync.despertando),
      ]);
      if (!mounted) return;
      setState(() => _avanzando = false);
      if (r == _Sync.campos && _errores.keys.any(_camposDe(paso).contains)) return;
      if (r == _Sync.despertando && _aviso == null) setState(() => _aviso = _avisoDespertando);
    }
    if (_i < _pasos.length - 1) _ir(_i + 1);
  }

  Future<void> _terminar() async {
    if (_pendiente.isNotEmpty) unawaited(_enviar());
    final notifier = ref.read(onboardingProvider.notifier);
    // Primero el estado (el router se entera en el mismo tick), luego la ruta:
    // así no hay parada intermedia en /futuro.
    final guardado = notifier.update((d) => d.copyWith(completo: true));
    if (mounted) context.go(Routes.examsUpload);
    await guardado;
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ob = ref.watch(onboardingProvider);
    final me = ref.watch(meProvider).asData?.value;
    final edad = _edad(me);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, edad),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [for (final p in _pasos) _pagina(p, ob, me)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int edad) {
    final t = Theme.of(context).textTheme;
    final enResumen = _i >= _datos;
    final progreso = (_i / _datos).clamp(0.0, 1.0);
    final teclado = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x3, Sp.gutter, Sp.x2),
      child: Column(
        children: [
          Row(
            children: [
              MoiraiMascot(size: 44, mood: enResumen ? MascotMood.happy : MascotMood.idle),
              const SizedBox(width: Sp.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: Motion.base,
                      child: Text(
                        enResumen ? 'Con esto ya puedo empezar.' : 'Voy en el dato ${Fmt.entero(_i + 1)} de ${Fmt.entero(_datos)}',
                        key: ValueKey(enResumen ? -1 : _i),
                        style: t.titleSmall,
                      ),
                    ),
                    const SizedBox(height: Sp.x3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Rad.pill),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: progreso),
                        duration: Motion.reveal,
                        curve: Motion.out,
                        builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.out,
            alignment: Alignment.topCenter,
            child: teclado
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: Sp.x4),
                    child: _AbanicoCard(edad0: edad, progreso: progreso),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pagina(_Paso p, OnboardingData ob, Me? me) {
    final (titulo, sub) = _textos(p);
    return MoScreen(
      key: ValueKey(p),
      safeTop: false,
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x4, Sp.gutter, 150),
      bottom: _nav(p, ob),
      children: [
        PasoTitulo(titulo: titulo, subtitulo: sub),
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x5),
          MoNotice(
            tone: MoTone.watch,
            icon: Icons.cloud_sync_outlined,
            text: _aviso!,
            action: _pendiente.isEmpty
                ? null
                : TextButton(onPressed: _avanzando ? null : _reintentar, child: const Text('Reintentar')),
          ),
        ],
        const SizedBox(height: Sp.x7),
        ..._cuerpo(p, me),
      ],
    );
  }

  Widget _nav(_Paso p, OnboardingData ob) {
    final resumen = p == _Paso.resumen;
    final label = switch (p) {
      _Paso.resumen => 'Listo, sigamos',
      _Paso.wearables => ob.wearableConectado ? 'Siguiente' : 'Lo hago después',
      _Paso.foto => ob.fotoPath != null ? 'Siguiente' : 'Lo hago después',
      _Paso.genetica => ob.geneticaPath != null ? 'Siguiente' : 'Lo hago después',
      _ => 'Siguiente',
    };
    return Row(
      children: [
        if (_i > 0) ...[
          _BotonAtras(onPressed: _avanzando ? null : () => _ir(_i - 1)),
          const SizedBox(width: Sp.x4),
        ],
        Expanded(
          child: MoPrimaryButton(
            label: label,
            loading: _avanzando,
            good: resumen,
            icon: resumen ? Icons.arrow_forward_rounded : null,
            onPressed: _valido(p, ob) ? (resumen ? _terminar : _siguiente) : null,
          ),
        ),
      ],
    );
  }

  (String, String) _textos(_Paso p) => switch (p) {
        _Paso.identidad => ('Cuéntame lo básico', 'Con tu edad y tu sexo al nacer ya puedo calibrar las primeras curvas.'),
        _Paso.cuerpo => ('Tu cuerpo, en dos números', 'Estatura y peso aproximados. No tienen que ser exactos.'),
        _Paso.origen => ('¿De dónde eres?', 'Me ayuda a elegir la población de referencia que más se parece a ti.'),
        _Paso.objetivos => ('¿Qué te gustaría ganar?', 'Elige todo lo que aplique. Lo uso para ordenar lo que te muestro.'),
        _Paso.familia => ('Tu familia', '¿Alguien cercano ha tenido alguna de estas condiciones?'),
        _Paso.sueno => ('¿Cuánto duermes?', 'Un promedio de una semana normal está bien.'),
        _Paso.ejercicio => ('¿Cuánto te mueves?', 'Cuenta caminatas largas, deporte, gimnasio… lo que te haga sudar.'),
        _Paso.alcohol => ('Alcohol y tabaco', 'Sin juicios. Mientras más honesto, más angosto el abanico.'),
        _Paso.alimentacion => ('Comida y estrés', 'Así, a grandes rasgos. No necesito un diario.'),
        _Paso.suplementos => ('¿Tomas algo a diario?', 'Suplementos o vitaminas. Si nada, sigue sin problema.'),
        _Paso.wearables => (
            '¿Usas reloj o pulsera?',
            'Leo sueño, pasos y ejercicio desde Health Connect (Android) o Salud (iOS); cualquier reloj que sincronice ahí me sirve.',
          ),
        _Paso.foto => ('Una foto tuya', 'Opcional. Por ahora solo la guardo para tu perfil.'),
        _Paso.genetica => ('¿Tienes una prueba genética?', 'Si tienes una prueba genética en PDF, guárdala aquí. Más adelante la analizo contigo.'),
        _Paso.resumen => ('Con esto ya puedo empezar', 'Esto es lo que me contaste. Lo siguiente son tus exámenes, si los tienes.'),
      };

  void _limpiarError(String campo) {
    if (!_errores.containsKey(campo)) return;
    setState(() => _errores = {..._errores}..remove(campo));
  }

  List<Widget> _cuerpo(_Paso p, Me? me) => switch (p) {
        _Paso.identidad => [
            PasoIdentidad(
              nombre: _nombre,
              nacimiento: _nacimiento,
              sexo: _sexo,
              errores: _errores,
              onNacimiento: (d) => setState(() {
                _nacimiento = d;
                _errores = {..._errores}..remove('date_of_birth');
              }),
              onSexo: (s) => setState(() {
                _sexo = s;
                _errores = {..._errores}..remove('sex_at_birth');
              }),
              onEditado: _limpiarError,
            ),
          ],
        _Paso.cuerpo => [
            PasoCuerpo(
              estatura: _estatura,
              peso: _peso,
              sangre: _sangre,
              errores: _errores,
              onSangre: (b) => setState(() {
                _sangre = _sangre == b ? null : b;
                _errores = {..._errores}..remove('blood_type');
              }),
              onEditado: _limpiarError,
            ),
          ],
        _Paso.origen => const [PasoOrigen()],
        _Paso.objetivos => const [PasoObjetivos()],
        _Paso.familia => const [PasoFamilia()],
        _Paso.sueno => const [PasoSueno()],
        _Paso.ejercicio => const [PasoEjercicio()],
        _Paso.alcohol => const [PasoAlcohol()],
        _Paso.alimentacion => const [PasoAlimentacion()],
        _Paso.suplementos => const [PasoSuplementos()],
        _Paso.wearables => const [PasoWearables()],
        _Paso.foto => const [PasoFoto()],
        _Paso.genetica => const [PasoGenetica()],
        _Paso.resumen => [
            PasoResumen(
              basico: (
                nombre: _nombre.text.trim().isEmpty ? me?.profile.fullName : _nombre.text.trim(),
                edad: Profile(dateOfBirth: _nacimiento).edad ?? me?.profile.edad,
                sexo: (_sexo ?? me?.profile.sexAtBirth)?.label,
                estatura: _num(_estatura.text) ?? me?.profile.heightCm,
                peso: _num(_peso.text) ?? me?.profile.weightKg,
                sangre: _sangre ?? me?.profile.bloodType,
              ),
            ),
          ],
      };
}

/// Botón redondo "Atrás" (54 px) que acompaña al primario.
class _BotonAtras extends StatelessWidget {
  const _BotonAtras({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(54, 54),
          fixedSize: const Size(54, 54),
          padding: EdgeInsets.zero,
          backgroundColor: MoiraiColors.surface,
        ),
        child: const Icon(Icons.arrow_back_rounded, size: 22),
      ),
    );
  }
}

/// "Tus futuros posibles": un abanico chico cuya banda se angosta con cada
/// dato respondido (las líneas fantasma quedan anchas, como referencia).
class _AbanicoCard extends StatelessWidget {
  const _AbanicoCard({required this.edad0, required this.progreso});
  final int edad0;
  final double progreso;

  static const _anios = 11;

  static Curva _curva(int edad0, double p) {
    // Ancho P10–P90 al año 10: de ~10 años (sin datos) a ~2,5 (con todo).
    final anchoFinal = 10.0 - 7.5 * Curves.easeOut.transform(p);
    final anios = List<int>.generate(_anios, (i) => i);
    final mediana = [for (final i in anios) edad0 + i * 1.0 + i * i * .015];
    final p10 = <double>[];
    final p90 = <double>[];
    for (final i in anios) {
      final f = i / (_anios - 1);
      final spread = anchoFinal * f + .3 * f;
      p10.add(mediana[i] - spread * .5);
      p90.add(mediana[i] + spread * .5);
    }
    return Curva(anios: anios, mediana: mediana, p10: p10, p90: p90);
  }

  static List<List<double>> _fantasmas(int edad0) {
    const n = 6;
    return [
      for (var k = 0; k < n; k++)
        [
          for (var i = 0; i < _anios; i++)
            edad0 + i * 1.0 + i * i * .015 + (k / (n - 1) * 2 - 1) * (i / (_anios - 1)) * 5.5,
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return MoCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MoOverline('Tus futuros posibles'),
                const SizedBox(height: 4),
                Text('Se van cerrando con cada dato.', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: Sp.x3),
          SizedBox(
            width: 118,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progreso),
              duration: Motion.draw,
              curve: Motion.soft,
              builder: (_, p, _) => FanChart(
                edad0: edad0,
                curva: _curva(edad0, p),
                trayectorias: _fantasmas(edad0),
                height: 64,
                mostrarEjes: false,
                identidad: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
