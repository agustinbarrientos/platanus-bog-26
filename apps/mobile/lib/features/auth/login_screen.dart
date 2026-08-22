import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// Entrar con correo y contraseña. Igual que el registro, el router hace el
/// resto cuando aparece la sesión.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _verClave = false;
  bool _cargando = false;
  String? _aviso;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final clave = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _aviso = 'Ese correo no se ve completo. ¿Lo revisas?');
      return;
    }
    if (clave.isEmpty) {
      setState(() => _aviso = 'Me falta tu contraseña.');
      return;
    }
    setState(() {
      _cargando = true;
      _aviso = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(email: email, password: clave);
      // Este dispositivo puede no tener el onboarding local (nunca lo hizo
      // aquí, o se reinstaló) aunque la cuenta ya lo haya terminado en otro
      // lado — si el backend dice que sí, nos ahorramos repetirlo.
      await ref.read(onboardingProvider.notifier).hydrateFromBackend();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _aviso = e.message);
    } catch (_) {
      if (mounted) setState(() => _aviso = 'No pude conectarme. ¿Tienes internet? Intenta de nuevo en un momento.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MoScreen(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go(Routes.welcome))),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoPrimaryButton(label: 'Entrar', loading: _cargando, onPressed: _entrar),
          const SizedBox(height: Sp.x2),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: _cargando ? null : () => context.go(Routes.register),
              child: const Text('Crear una cuenta'),
            ),
          ),
        ],
      ),
      children: [
        const MoScreenHeader(
          leading: MoiraiMascot(size: 60),
          title: 'Qué bueno verte de nuevo',
          subtitle: 'Entra con tu correo y contraseña y retomamos donde quedamos.',
        ),
        const SizedBox(height: Sp.x7),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Correo',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ).stagger(1),
        const SizedBox(height: Sp.stackCard),
        TextField(
          controller: _password,
          obscureText: !_verClave,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _entrar(),
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _verClave ? 'Ocultar' : 'Mostrar',
              onPressed: () => setState(() => _verClave = !_verClave),
              icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
        ).stagger(2),
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x5),
          MoNotice(tone: MoTone.watch, text: _aviso!).stagger(0),
        ],
      ],
    );
  }
}
