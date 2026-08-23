import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/models/me.dart';
import '../../data/models/onboarding.dart';
import '../../widgets/mo.dart';
import 'onboarding_widgets.dart';

/// Pasos a–c: lo básico (va a `/me`) y el origen (local).

// ── a. Nacimiento, sexo al nacer ─────────────────────────────────────────
class PasoIdentidad extends StatelessWidget {
  const PasoIdentidad({
    super.key,
    required this.nacimiento,
    required this.sexo,
    required this.errores,
    required this.onNacimiento,
    required this.onSexo,
  });

  final DateTime? nacimiento;
  final SexAtBirth? sexo;
  final Map<String, String> errores;
  final ValueChanged<DateTime> onNacimiento;
  final ValueChanged<SexAtBirth> onSexo;

  Future<void> _elegirFecha(BuildContext context) async {
    final hoy = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: nacimiento ?? DateTime(hoy.year - 30, hoy.month, hoy.day),
      firstDate: DateTime(hoy.year - 120, hoy.month, hoy.day),
      lastDate: DateTime(hoy.year - 18, hoy.month, hoy.day),
      initialDatePickerMode: DatePickerMode.year,
      locale: const Locale('es', 'CO'),
      helpText: 'Tu fecha de nacimiento',
      confirmText: 'Listo',
      cancelText: 'Ahora no',
    );
    if (d != null) onNacimiento(d);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final edad = Profile(dateOfBirth: nacimiento).edad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(Rad.md + 2),
          onTap: () => _elegirFecha(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Fecha de nacimiento',
              prefixIcon: const Icon(Icons.cake_outlined),
              suffixIcon: const Icon(Icons.calendar_month_outlined),
              errorText: errores['date_of_birth'],
            ),
            isEmpty: nacimiento == null,
            child: Text(
              nacimiento == null ? '' : DateFormat.yMMMMd('es_CO').format(nacimiento!),
              style: t.bodyLarge,
            ),
          ),
        ).stagger(0),
        if (edad != null) ...[
          const SizedBox(height: Sp.x3),
          Row(
            children: [
              const SizedBox(width: Sp.x2),
              MoBadge('${Fmt.entero(edad)} años', tone: MoTone.good, icon: Icons.check_rounded),
              const SizedBox(width: Sp.x3),
              Expanded(child: Text('Con eso ya sé con qué población compararte.', style: t.bodySmall)),
            ],
          ).animate().fadeIn(duration: Motion.base).slideX(begin: -.03, end: 0, curve: Motion.out),
        ],
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('Sexo asignado al nacer', hint: 'Lo uso para las curvas de referencia, nada más.'),
        MoChoiceGroup<SexAtBirth>(
          options: {for (final s in SexAtBirth.values) s: s.label},
          value: sexo,
          onChanged: onSexo,
        ).stagger(1),
        if (errores['sex_at_birth'] != null) PistaCampo(errores['sex_at_birth']!),
      ],
    );
  }
}

// ── b. Estatura, peso, tipo de sangre ────────────────────────────────────
class PasoCuerpo extends StatelessWidget {
  const PasoCuerpo({
    super.key,
    required this.estatura,
    required this.peso,
    required this.sangre,
    required this.errores,
    required this.onSangre,
    required this.onEditado,
  });

  final TextEditingController estatura;
  final TextEditingController peso;
  final String? sangre;
  final Map<String, String> errores;
  final ValueChanged<String> onSangre;
  final ValueChanged<String> onEditado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: estatura,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                onChanged: (_) => onEditado('height_cm'),
                decoration: InputDecoration(
                  labelText: 'Estatura',
                  suffixText: 'cm',
                  hintText: '170',
                  prefixIcon: const Icon(Icons.height_rounded),
                  errorText: errores['height_cm'],
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: Sp.x4),
            Expanded(
              child: TextField(
                controller: peso,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(6)],
                onChanged: (_) => onEditado('weight_kg'),
                decoration: InputDecoration(
                  labelText: 'Peso',
                  suffixText: 'kg',
                  hintText: '68,5',
                  prefixIcon: const Icon(Icons.monitor_weight_outlined),
                  errorText: errores['weight_kg'],
                  errorMaxLines: 3,
                ),
              ),
            ),
          ],
        ).stagger(0),
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('Tipo de sangre', opcional: true, hint: 'Si no lo sabes, sigue sin problema.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in bloodTypes) MoChoice(label: b, selected: sangre == b, onTap: () => onSangre(b)),
          ],
        ).stagger(1),
        if (errores['blood_type'] != null) PistaCampo(errores['blood_type']!),
      ],
    );
  }
}

// ── c. Nacionalidad, residencia, ancestría (local) ───────────────────────
class PasoOrigen extends ConsumerWidget {
  const PasoOrigen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);
    final n = ref.read(onboardingProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PickerField<String>(
          label: 'Nacionalidad',
          titulo: '¿Cuál es tu nacionalidad?',
          icon: Icons.flag_outlined,
          options: Catalogos.paises,
          value: ob.nacionalidad,
          onChanged: (v) => n.update((d) => d.copyWith(nacionalidad: v, paisResidencia: d.paisResidencia ?? v)),
        ).stagger(0),
        const SizedBox(height: Sp.stackCard),
        PickerField<String>(
          label: 'País donde vives',
          titulo: '¿Dónde vives hoy?',
          icon: Icons.home_outlined,
          options: Catalogos.paises,
          value: ob.paisResidencia,
          onChanged: (v) => n.update((d) => d.copyWith(paisResidencia: v)),
        ).stagger(1),
        const SizedBox(height: Sp.stackSection),
        const Etiqueta('Ancestría que reportas', hint: 'Es autorreporte. Me ayuda a elegir la población de referencia.'),
        MoChoiceGroup<String>(
          options: Catalogos.ancestria,
          value: ob.ancestria,
          onChanged: (v) => n.update((d) => d.copyWith(ancestria: v)),
        ).stagger(2),
      ],
    );
  }
}
