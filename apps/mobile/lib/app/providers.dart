import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/api/api_client.dart';
import '../data/models/biomarcador.dart';
import '../data/models/me.dart';
import '../data/models/onboarding.dart';
import '../data/models/simulacion.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/demo_data.dart';
import '../data/repositories/exams_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/simulation_repository.dart';
import '../data/repositories/wearables_repository.dart';

// ── Infraestructura ──────────────────────────────────────────────────────
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError('override en main'));
final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);
final apiClientProvider = Provider<ApiClient>((_) => ApiClient());

final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(supabaseProvider)));
final profileRepositoryProvider = Provider((ref) => ProfileRepository(ref.watch(apiClientProvider), ref.watch(sharedPrefsProvider)));
final examsRepositoryProvider = Provider((ref) => ExamsRepository(ref.watch(apiClientProvider)));
final simulationRepositoryProvider = Provider((ref) => SimulationRepository(ref.watch(apiClientProvider), ref.watch(sharedPrefsProvider)));
final wearablesRepositoryProvider = Provider((ref) => WearablesRepository(ref.watch(apiClientProvider)));

// ── Sesión ───────────────────────────────────────────────────────────────
/// Notifica al router cuando cambia la sesión.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._repo) {
    _sub = _repo.changes.listen((_) => notifyListeners());
  }
  final AuthRepository _repo;
  late final StreamSubscription<AuthState> _sub;

  bool get signedIn => _repo.signedIn;
  String? get userId => _repo.user?.id;
  String? get email => _repo.user?.email;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final authNotifierProvider = ChangeNotifierProvider((ref) => AuthNotifier(ref.watch(authRepositoryProvider)));
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(authNotifierProvider).userId);

// ── /me ──────────────────────────────────────────────────────────────────
/// Perfil del backend. Se invalida al hacer PATCH o al cambiar de usuario.
final meProvider = FutureProvider<Me>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).getMe();
});

// ── Onboarding extendido (local) ─────────────────────────────────────────
class OnboardingNotifier extends Notifier<OnboardingData> {
  @override
  OnboardingData build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const OnboardingData();
    return ref.read(profileRepositoryProvider).loadOnboarding(uid);
  }

  Future<void> update(OnboardingData Function(OnboardingData) fn) async {
    state = fn(state);
    final uid = ref.read(currentUserIdProvider);
    if (uid != null) await ref.read(profileRepositoryProvider).saveOnboarding(uid, state);
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingData>(OnboardingNotifier.new);

/// ¿Ya pasó por el onboarding? (perfil del backend completo + extras locales).
final onboardingDoneProvider = Provider<bool>((ref) => ref.watch(onboardingProvider).completo);

// ── Biomarcadores confirmados (local) ────────────────────────────────────
class BiomarcadoresNotifier extends Notifier<List<Biomarcador>> {
  @override
  List<Biomarcador> build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    return ref.read(profileRepositoryProvider).loadBiomarcadores(uid);
  }

  Future<void> set(List<Biomarcador> list) async {
    state = list;
    final uid = ref.read(currentUserIdProvider);
    if (uid != null) await ref.read(profileRepositoryProvider).saveBiomarcadores(uid, list);
  }
}

final biomarcadoresProvider = NotifierProvider<BiomarcadoresNotifier, List<Biomarcador>>(BiomarcadoresNotifier.new);

/// Lectura extraída, pendiente de confirmación (estado efímero entre pantallas).
final lecturaPendienteProvider = StateProvider<List<Biomarcador>?>((_) => null);

// ── Input de simulación (armado desde perfil + onboarding + biomarcadores) ─
final simulacionInputProvider = Provider<SimulacionInput>((ref) {
  final me = ref.watch(meProvider).asData?.value;
  final ob = ref.watch(onboardingProvider);
  final bms = ref.watch(biomarcadoresProvider);
  final p = me?.profile;
  final edad = p?.edad;
  if (p == null || edad == null) {
    // Sin perfil todavía: caso demo (red de seguridad, spec §11 paso 9).
    return DemoData.perfil();
  }
  final faltantes = BiomarcadorDef.all.map((d) => d.id).where((id) => !bms.any((b) => b.nombre == id)).toList();
  return SimulacionInput(
    demografia: {
      'edad': edad,
      'sexo_biologico': p.sexAtBirth?.specCode ?? 'F',
      'peso_kg': p.weightKg,
      'estatura_cm': p.heightCm,
      'nacionalidad': ob.nacionalidad ?? 'CO',
      'ancestria_reportada': ob.ancestria ?? 'mixta_latam',
    },
    objetivos: ob.objetivos.toList(),
    historialFamiliar: ob.historialFamiliar.map((e) => e.condicion).where((c) => c != 'ninguna').toList(),
    biomarcadores: bms,
    habitos: ob.habitosSpec,
    opcionales: {
      'suplementos': ob.suplementos.map((s) => s.nombre).toList(),
      'prueba_genetica': ob.geneticaPath,
      'foto': ob.fotoPath,
    },
    datosFaltantes: faltantes,
    notasIncertidumbre: faltantes.isEmpty
        ? null
        : bms.isEmpty
            ? 'Sin exámenes: los 9 biomarcadores se imputan de medianas NHANES por edad/sexo; la banda es la más ancha posible.'
            : '${faltantes.length} biomarcadores imputados de medianas NHANES por edad/sexo',
  );
});

// ── Simulación en curso / última ─────────────────────────────────────────
sealed class SimState {
  const SimState();
}

class SimIdle extends SimState {
  const SimIdle();
}

class SimRunning extends SimState {
  const SimRunning(this.progreso);
  final SimulacionProgreso progreso;
}

class SimDone extends SimState {
  const SimDone(this.resultado);
  final SimulacionResultado resultado;
}

class SimFailed extends SimState {
  const SimFailed(this.message);
  final String message;
}

class SimulationNotifier extends Notifier<SimState> {
  StreamSubscription<SimulacionProgreso>? _sub;

  @override
  SimState build() {
    ref.onDispose(() => _sub?.cancel());
    final uid = ref.watch(currentUserIdProvider);
    if (uid != null) {
      final h = ref.read(simulationRepositoryProvider).historial(uid);
      if (h.isNotEmpty) return SimDone(h.first);
    }
    return const SimIdle();
  }

  /// Arranca una simulación con el input actual (o uno explícito, p. ej. el demo).
  void start({SimulacionInput? input}) {
    _sub?.cancel();
    final SimulacionInput inp = input ?? ref.read(simulacionInputProvider);
    state = const SimRunning(SimulacionProgreso(fraccion: 0, vidas: 0, totalVidas: 1));
    _sub = ref.read(simulationRepositoryProvider).simular(inp).listen(
      (p) {
        if (p.resultado != null) {
          state = SimDone(p.resultado!);
          final uid = ref.read(currentUserIdProvider);
          if (uid != null) ref.read(simulationRepositoryProvider).guardar(uid, p.resultado!);
        } else {
          state = SimRunning(p);
        }
      },
      onError: (Object e) {
        state = SimFailed(e is ApiException ? e.message : 'La simulación no terminó. Intenta de nuevo.');
      },
    );
  }

  void reset() {
    _sub?.cancel();
    state = const SimIdle();
  }
}

final simulationProvider = NotifierProvider<SimulationNotifier, SimState>(SimulationNotifier.new);

/// Último resultado disponible (o null).
final ultimoResultadoProvider = Provider<SimulacionResultado?>((ref) {
  final s = ref.watch(simulationProvider);
  return s is SimDone ? s.resultado : null;
});

final historialProvider = Provider<List<SimulacionResultado>>((ref) {
  ref.watch(simulationProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  return ref.read(simulationRepositoryProvider).historial(uid);
});
