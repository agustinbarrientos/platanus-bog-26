import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

const salida = '/tmp/claude-1000/-home-feru34-Documents-Platanus-platanus-bog-26/1c12cd54-203a-4a66-9c48-bb39057931ac/scratchpad';

Future<void> main() async {
  const fuentes = {
    'plain': '../web/public/moirai/moirai-plain.json',
    'travel': '../web/public/moirai/moirai-mascot.json',
    'horneado': 'assets/moirai/moirai-mascot.json',
  };

  for (final e in fuentes.entries) {
    testWidgets(e.key, (tester) async {
      final bytes = File(e.value).readAsBytesSync();
      final comp = await LottieComposition.fromBytes(bytes);
      debugPrint('COMP ${e.key} ${comp.bounds} start=${comp.startFrame} end=${comp.endFrame} dur=${comp.duration}');

      const w = 576.0, h = 271.0;
      final ctrl = AnimationController(vsync: const TestVSync(), duration: const Duration(seconds: 1));
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Lottie.memory(bytes, controller: ctrl, fit: BoxFit.fill, width: w, height: h),
            ),
          ),
        ),
      ));
      await tester.pump();

      double? minX, minY, maxX, maxY;
      for (var i = 0; i <= 4; i++) {
        ctrl.value = i / 4;
        await tester.pump();
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 1);
        final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final bw = img.width, bh = img.height;
        for (var y = 0; y < bh; y++) {
          for (var x = 0; x < bw; x++) {
            if (data.getUint8((y * bw + x) * 4 + 3) > 10) {
              if (minX == null || x < minX) minX = x.toDouble();
              if (maxX == null || x > maxX) maxX = x.toDouble();
              if (minY == null || y < minY) minY = y.toDouble();
              if (maxY == null || y > maxY) maxY = y.toDouble();
            }
          }
        }
        if (i == 1) {
          final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          File('$salida/${e.key}.png').writeAsBytesSync(png.buffer.asUint8List());
        }
      }
      debugPrint('BBOX ${e.key} comp x=${minX! * 4}..${maxX! * 4} y=${minY! * 4}..${maxY! * 4}');
    });
  }
}
