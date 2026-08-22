import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/tokens.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mo.dart';

/// Registro contra el backend (correo + contraseña). Al crear la cuenta ya hay
/// sesión: el router se entera solo y manda al onboarding.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _verClave = false;
  bool _cargando = false;
  String? _aviso;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final clave = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _aviso = 'Ese correo no se ve completo. ¿Lo revisas?');
      return;
    }
    if (clave.length < 8) {
      setState(() => _aviso = 'La contraseña necesita al menos 8 caracteres.');
      return;
    }
    setState(() {
      _cargando = true;
      _aviso = null;
    });
    try {
      await ref.read(authRepositoryProvider).signUp(email: email, password: clave, fullName: _nombre.text);
      // Nada más: el router escucha la sesión y redirige solo.
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
          MoPrimaryButton(label: 'Crear mi cuenta', loading: _cargando, onPressed: _crear),
          const SizedBox(height: Sp.x2),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: _cargando ? null : () => context.go(Routes.login),
              child: const Text('Ya tengo cuenta'),
            ),
          ),
        ],
      ),
      children: [
        const MoScreenHeader(
          leading: MoiraiMascot(size: 60),
          title: 'Creemos tu cuenta',
          subtitle: 'Solo correo y contraseña. Así guardo tus futuros para cuando vuelvas.',
        ),
        const SizedBox(height: Sp.x7),
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: '¿Cómo te llamo? (opcional)',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ).stagger(1),
        const SizedBox(height: Sp.stackCard),
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
        ).stagger(2),
        const SizedBox(height: Sp.stackCard),
        TextField(
          controller: _password,
          obscureText: !_verClave,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _crear(),
          decoration: InputDecoration(
            labelText: 'Contraseña',
            helperText: 'Mínimo 8 caracteres.',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _verClave ? 'Ocultar' : 'Mostrar',
              onPressed: () => setState(() => _verClave = !_verClave),
              icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
        ).stagger(3),
        if (_aviso != null) ...[
          const SizedBox(height: Sp.x5),
          MoNotice(tone: MoTone.watch, text: _aviso!).stagger(0),
        ],
        const SizedBox(height: Sp.x7),
        const MoFootnote('Tus datos son tuyos. Los uso solo para simular tu futuro.').stagger(4),
      ],
    );
  }
}
