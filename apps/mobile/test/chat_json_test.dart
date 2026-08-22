import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moirai/data/mock/mock_engine.dart';
import 'package:moirai/data/models/chat.dart';
import 'package:moirai/data/repositories/chat_repository.dart';
import 'package:moirai/data/repositories/demo_data.dart';

/// Lo que el chat manda y recibe del backend (`POST /me/health-context/chat`):
/// el resultado compacto (`toChatJson`) y la respuesta con `fuentes`.
void main() {
  test('toChatJson: sin trayectorias, curvas a un decimal, mismo resto que toJson', () async {
    final progreso = await MockEngine(n: 80).simular(DemoData.perfil()).last;
    final r = progreso.resultado!;

    final completo = r.toJson();
    final chat = r.toChatJson();

    expect(completo.containsKey('muestra_trayectorias'), isTrue);
    expect(chat.containsKey('muestra_trayectorias'), isFalse);
    for (final k in ['id', 'edad_cronologica', 'edad_biologica_hoy', 'mejor_decision', 'veredicto_gemelo', 'porque', 'shap_top_drivers', 'comparacion_poblacional', 'incertidumbre', 'descargo', 'intervenciones_catalogo', 'biomarcadores_usados']) {
      expect(chat.containsKey(k), isTrue, reason: k);
    }
    final curva = (chat['trayectoria_baseline'] as Map).cast<String, dynamic>();
    for (final serie in ['mediana', 'p10', 'p90']) {
      for (final v in (curva[serie] as List).cast<num>()) {
        expect(((v * 10).round() / 10 - v).abs(), lessThan(1e-9), reason: '$serie a un decimal');
      }
    }
    expect((chat['escenarios'] as List).length, r.escenarios.length);
    for (final e in (chat['escenarios'] as List).cast<Map>()) {
      expect(e.containsKey('curva'), isTrue);
      expect(e.containsKey('anios_ganados'), isTrue);
    }
    // Es JSON de verdad y pesa poco (el grueso eran las trayectorias).
    final bytesChat = utf8.encode(jsonEncode(chat)).length;
    final bytesCompleto = utf8.encode(jsonEncode(completo)).length;
    expect(bytesChat, lessThan(bytesCompleto));
    expect(bytesChat, lessThan(20 * 1024));
  });

  test('ChatRespuesta.fromJson lee reply, history y fuentes (y tolera su ausencia)', () {
    final r = ChatRespuesta.fromJson({
      'reply': 'Tu glucosa está en 92 mg/dL.',
      'history': [
        {'role': 'user', 'content': '¿Cómo está mi glucosa?'},
        {'role': 'assistant', 'content': 'Tu glucosa está en 92 mg/dL.'},
      ],
      'fuentes': [
        {'id': 'bio:glucosa', 'titulo': 'Tu glucosa en ayunas', 'grupo': 'usuario'},
        {'id': 'kb:biomarcador:glucosa', 'titulo': 'Qué es glucosa en ayunas', 'grupo': 'conocimiento'},
      ],
    });
    expect(r.reply, startsWith('Tu glucosa'));
    expect(r.history.map((m) => m.role), ['user', 'assistant']);
    expect(r.fuentes.map((f) => f.id), ['bio:glucosa', 'kb:biomarcador:glucosa']);
    expect(r.fuentes.first.esDeMisDatos, isTrue);
    expect(r.fuentes.last.esDeMisDatos, isFalse);
    // El historial que vuelve al backend solo lleva role + content.
    expect(r.history.first.toJson().keys, ['role', 'content']);

    final viejo = ChatRespuesta.fromJson({'reply': 'hola', 'history': []});
    expect(viejo.fuentes, isEmpty);
  });

  test('sugerencias con resultado apuntan a lo que está en pantalla', () async {
    final progreso = await MockEngine(n: 80).simular(DemoData.perfil()).last;
    final r = progreso.resultado!;
    final s = ChatRepository.sugerenciasCon(r);
    expect(s, isNotEmpty);
    expect(s.first.toLowerCase(), contains(r.mejorDecision.etiqueta.toLowerCase()));
    expect(s.any((p) => p.contains('rango')), isTrue);
  });
}
