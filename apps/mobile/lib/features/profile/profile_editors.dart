import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/format.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/me.dart';
import '../../data/models/onboarding.dart';
import '../../widgets/mo.dart';

/// Bottom sheet con el acabado de la app: título Fredoka, subtítulo en voz de
/// la mascota y contenido que respeta el teclado.
Future<T?> showMoSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.x2, Sp.gutter, Sp.x7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: t.headlineSmall),
              if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle, style: t.bodyMedium)],
              const SizedBox(height: Sp.x6),
              Builder(builder: builder),
            ],
          ),
        ),
      );
    },
  );
}

// ── Datos básicos (/me) ──────────────────────────────────────────────────

/// Los 6 campos que el backend guarda hoy en `/me` (AUTH.md).
enum BasicField {
  nombre('full_name', 'Nombre', '¿Cómo te llamo?'),
  nacimiento('date_of_birth', 'Fecha de nacimiento', 'La uso para tu edad cronológica, el punto de partida de todo.'),
  sexo('sex_at_birth', 'Sexo al nacer', 'Las medianas poblacionales con las que te comparo cambian con esto.'),
  estatura('height_cm', 'Estatura', 'En centímetros.'),
  peso('weight_kg', 'Peso', 'En kilogramos. Un decimal basta.'),
  sangre('blood_type', 'Tipo de sangre', 'Por ahora solo lo guardo.');

  const BasicField(this.apiKey, this.label, this.ayuda);
  final String apiKey;
  final String label;
  final String ayuda;
}

/// Abre el editor del campo y devuelve `true` si se guardó.
Future<bool?> editBasicField(BuildContext context, BasicField field, Profile profile) {
  return showMoSheet<bool>(
    context,
    title: field.label,
    subtitle: field.ayuda,
    builder: (_) => _BasicFieldEditor(field: field, profile: profile),
  );
}

class _BasicFieldEditor extends ConsumerStatefulWidget {
  const _BasicFieldEditor({required this.field, required this.profile});
  final BasicField field;
  final Profile profile;

  @override
  ConsumerState<_BasicFieldEditor> createState() => _BasicFieldEditorState();
}

class _BasicFieldEditorState extends ConsumerState<_BasicFieldEditor> {
  late final TextEditingController _text;
  DateTime? _fecha;
  SexAtBirth? _sexo;
  String? _sangre;
  bool _saving = false;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _text = TextEditingController(
      text: switch (widget.field) {
        BasicField.nombre => p.fullName ?? '',
        BasicField.estatura => p.heightCm == null ? '' : Fmt.corto(p.heightCm!),
        BasicField.peso => p.weightKg == null ? '' : Fmt.corto(p.weightKg!),
        _ => '',
      },
    );
    _fecha = p.dateOfBirth;
    _sexo = p.sexAtBirth;
    _sangre = p.bloodType;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Valor listo para `PATCH /me`, o null si no hay nada válido que mandar.
  Object? _valor() {
    switch (widget.field) {
      case BasicField.nombre:
        final v = _text.text.trim();
        return v.isEmpty ? null : v;
      case BasicField.estatura:
      case BasicField.peso:
        final v = double.tryParse(_text.text.trim().replaceAll(',', '.'));
        return v;
      case BasicField.nacimiento:
        return _fecha == null ? null : DateFormat('yyyy-MM-dd').format(_fecha!);
      case BasicField.sexo:
        return _sexo?.api;
      case BasicField.sangre:
        return _sangre;
    }
  }

  Future<void> _guardar() async {
    final v = _valor();
    if (v == null) {
      setState(() => _aviso = 'Necesito un valor para guardar.');
      return;
    }
    setState(() {
      _saving = true;
      _aviso = null;
    });
    try {
      await ref.read(profileRepositoryProvider).patchMe({widget.field.apiKey: v});
      ref.invalidate(meProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _aviso = e.fields[widget.field.apiKey] ?? e.message);
    } catch (_) {
      setState(() => _aviso = 'No pude guardar eso. ¿Tienes internet?');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hoy = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (widget.field) {
          BasicField.nombre => TextField(
              controller: _text,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Tu nombre'),
              onSubmitted: (_) => _guardar(),
            ),
          BasicField.estatura || BasicField.peso => TextField(
              controller: _text,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                hintText: widget.field == BasicField.estatura ? '170' : '65,5',
                suffixText: widget.field == BasicField.estatura ? 'cm' : 'kg',
              ),
              onSubmitted: (_) => _guardar(),
            ),
          BasicField.nacimiento => DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: MoiraiColors.line),
                borderRadius: BorderRadius.circular(Rad.md),
              ),
              child: CalendarDatePicker(
                initialDate: _fecha ?? DateTime(hoy.year - 30, hoy.month, hoy.day),
                firstDate: DateTime(hoy.year - 120),
                lastDate: DateTime(hoy.year - 18, hoy.month, hoy.day),
                initialCalendarMode: DatePickerMode.year,
                onDateChanged: (d) => setState(() => _fecha = d),
              ),
            ),
          BasicField.sexo => MoChoiceGroup<SexAtBirth>(
              options: {for (final s in SexAtBirth.values) s: s.label},
              value: _sexo,
              onChanged: (v) => setState(() => _sexo = v),
            ),
          BasicField.sangre => MoChoiceGroup<String>(
              options: {for (final b in bloodTypes) b: b},
              value: _sangre,
              onChanged: (v) => setState(() => _sangre = v),
            ),
        },
        if (widget.field == BasicField.nacimiento && _fecha != null) ...[
          const SizedBox(height: Sp.x3),
          Text(DateFormat("d 'de' MMMM 'de' yyyy", 'es_CO').format(_fecha!), style: t.titleSmall!.copyWith(color: MoiraiColors.blueInk)),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x4),
          MoNotice(text: _aviso!, tone: MoTone.watch, icon: Icons.info_outline_rounded),
        ],
        const SizedBox(height: Sp.x6),
        MoPrimaryButton(label: 'Guardar', loading: _saving, onPressed: _guardar),
      ],
    );
  }
}

// ── Objetivos y familia (onboarding local) ───────────────────────────────

Future<void> editGoalsAndFamily(BuildContext context) {
  return showMoSheet<void>(
    context,
    title: 'Objetivos y familia',
    subtitle: 'Lo que te importa y lo que corre en tu familia. Cambia lo que quieras.',
    builder: (_) => const _GoalsFamilyEditor(),
  );
}

class _GoalsFamilyEditor extends ConsumerStatefulWidget {
  const _GoalsFamilyEditor();

  @override
  ConsumerState<_GoalsFamilyEditor> createState() => _GoalsFamilyEditorState();
}

class _GoalsFamilyEditorState extends ConsumerState<_GoalsFamilyEditor> {
  late Set<String> _objetivos;
  late Map<String, String?> _familia; // condicion → parentesco
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final ob = ref.read(onboardingProvider);
    _objetivos = {...ob.objetivos};
    _familia = {for (final f in ob.historialFamiliar) f.condicion: f.parentesco};
  }

  void _toggleCondicion(String c) {
    setState(() {
      if (_familia.containsKey(c)) {
        _familia.remove(c);
      } else if (c == 'ninguna') {
        _familia = {'ninguna': null};
      } else {
        _familia.remove('ninguna');
        _familia[c] = null;
      }
    });
  }

  Future<void> _guardar() async {
    setState(() => _saving = true);
    await ref.read(onboardingProvider.notifier).update(
          (o) => o.copyWith(
            objetivos: _objetivos,
            historialFamiliar: [for (final e in _familia.entries) FamiliarCondicion(condicion: e.key, parentesco: e.value)],
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Qué buscas', style: t.titleMedium),
        const SizedBox(height: Sp.x3),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in Catalogos.objetivos.entries)
              MoChoice(
                label: e.value,
                selected: _objetivos.contains(e.key),
                onTap: () => setState(() => _objetivos.contains(e.key) ? _objetivos.remove(e.key) : _objetivos.add(e.key)),
              ),
          ],
        ),
        const SizedBox(height: Sp.x7),
        Text('En tu familia cercana', style: t.titleMedium),
        const SizedBox(height: Sp.x3),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in Catalogos.condicionesFamiliares.entries)
              MoChoice(
                label: e.value,
                selected: _familia.containsKey(e.key),
                good: e.key == 'ninguna',
                onTap: () => _toggleCondicion(e.key),
              ),
          ],
        ),
        for (final e in _familia.entries.where((e) => e.key != 'ninguna')) ...[
          const SizedBox(height: Sp.x5),
          Text('${Catalogos.condicionesFamiliares[e.key] ?? e.key} · ¿quién?', style: t.labelMedium),
          const SizedBox(height: Sp.x3),
          MoChoiceGroup<String>(
            options: Catalogos.parentescos,
            value: e.value,
            onChanged: (v) => setState(() => _familia[e.key] = v),
          ),
        ],
        const SizedBox(height: Sp.x7),
        MoPrimaryButton(label: 'Guardar', loading: _saving, onPressed: _guardar),
      ],
    );
  }
}

// ── Cuenta: contraseña y borrado (/auth/*) ───────────────────────────────

/// Cambiar contraseña (actual + nueva ≥ 8). Devuelve `true` si se cambió.
Future<bool?> changePasswordSheet(BuildContext context) {
  return showMoSheet<bool>(
    context,
    title: 'Cambiar contraseña',
    subtitle: 'Dime la actual y la nueva. Mínimo 8 caracteres.',
    builder: (_) => const _PasswordEditor(),
  );
}

class _PasswordEditor extends ConsumerStatefulWidget {
  const _PasswordEditor();

  @override
  ConsumerState<_PasswordEditor> createState() => _PasswordEditorState();
}

class _PasswordEditorState extends ConsumerState<_PasswordEditor> {
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  bool _ver = false;
  bool _saving = false;
  String? _aviso;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_actual.text.isEmpty) {
      setState(() => _aviso = 'Me falta tu contraseña actual.');
      return;
    }
    if (_nueva.text.length < 8) {
      setState(() => _aviso = 'La nueva contraseña necesita al menos 8 caracteres.');
      return;
    }
    setState(() {
      _saving = true;
      _aviso = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(current: _actual.text, nueva: _nueva.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _aviso = e.message);
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude cambiarla. ¿Tienes internet?');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ojo = IconButton(
      tooltip: _ver ? 'Ocultar' : 'Mostrar',
      onPressed: () => setState(() => _ver = !_ver),
      icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _actual,
          autofocus: true,
          obscureText: !_ver,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(labelText: 'Contraseña actual', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: ojo),
        ),
        const SizedBox(height: Sp.stackCard),
        TextField(
          controller: _nueva,
          obscureText: !_ver,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _guardar(),
          decoration: const InputDecoration(
            labelText: 'Contraseña nueva',
            helperText: 'Mínimo 8 caracteres.',
            prefixIcon: Icon(Icons.lock_reset_rounded),
          ),
        ),
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x4),
          MoNotice(text: _aviso!, tone: MoTone.watch, icon: Icons.info_outline_rounded),
        ],
        const SizedBox(height: Sp.x6),
        MoPrimaryButton(label: 'Cambiar contraseña', loading: _saving, onPressed: _guardar),
      ],
    );
  }
}

/// Borrar la cuenta (pide la contraseña). Devuelve `true` si el backend la
/// borró; en ese momento la sesión local ya quedó limpia.
Future<bool?> confirmDeleteAccount(BuildContext context) {
  return showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _borrando = false;
  String? _aviso;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _borrar() async {
    if (_password.text.isEmpty) {
      setState(() => _aviso = 'Necesito tu contraseña para confirmar.');
      return;
    }
    setState(() {
      _borrando = true;
      _aviso = null;
    });
    try {
      await ref.read(authRepositoryProvider).deleteAccount(password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _aviso = e.message);
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude borrar tu cuenta. ¿Tienes internet?');
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('¿Borro tu cuenta?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Borro tu cuenta, tu perfil y tus simulaciones. Esto no se puede deshacer.', style: t.bodyMedium),
          const SizedBox(height: Sp.x5),
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _borrar(),
            decoration: const InputDecoration(labelText: 'Tu contraseña', prefixIcon: Icon(Icons.lock_outline_rounded)),
          ),
          if (_aviso != null) ...[
            const SizedBox(height: Sp.x4),
            MoNotice(text: _aviso!, tone: MoTone.watch, icon: Icons.info_outline_rounded),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _borrando ? null : () => Navigator.of(context).pop(false), child: const Text('Mejor no')),
        TextButton(
          onPressed: _borrando ? null : _borrar,
          style: TextButton.styleFrom(foregroundColor: MoiraiColors.amberInk),
          child: Text(_borrando ? 'Borrando…' : 'Sí, borrar'),
        ),
      ],
    );
  }
}
