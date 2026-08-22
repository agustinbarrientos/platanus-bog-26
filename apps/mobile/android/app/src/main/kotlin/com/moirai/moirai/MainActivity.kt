package com.moirai.moirai

import io.flutter.embedding.android.FlutterFragmentActivity

/// `FlutterFragmentActivity`, no `FlutterActivity`: el plugin `health` pide los
/// permisos de Health Connect con `registerForActivityResult`, que solo existe
/// en `androidx.activity.ComponentActivity`. Con `FlutterActivity` (que hereda
/// de `android.app.Activity`) el cast falla y el plugin ni siquiera se
/// registra —"Error registering plugin health … ClassCastException"—, así que
/// conectar un reloj o una pulsera es imposible. Ver README del paquete
/// `health`, sección "Android 14".
class MainActivity : FlutterFragmentActivity()
