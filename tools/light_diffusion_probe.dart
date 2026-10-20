// Hardware-free native GPU check. This entry point never creates a BLE session.
// Build with -t tools/light_diffusion_probe.dart and a BDK_DIFFUSION_REPORT path.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdk_audio/features/light/light_screen.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sourceRecorder = ui.PictureRecorder();
  Canvas(sourceRecorder).drawRect(
    const Rect.fromLTWH(0, 0, 16, 16),
    Paint()..color = const Color(0xff003000),
  );
  final sourcePicture = sourceRecorder.endRecording();
  final source = await sourcePicture.toImage(16, 16);
  sourcePicture.dispose();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.black, BlendMode.src);
  FirmwareLightPainter(image: source).paint(canvas, const Size(680, 300));
  final picture = recorder.endRecording();
  final image = await picture.toImage(680, 300);
  picture.dispose();
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  int green(int x) => data.getUint8((150 * 680 + x) * 4 + 1);
  var jump = 0;
  for (final start in [175, 475]) {
    for (var x = start; x < start + 30; x++) {
      final next = (green(x + 1) - green(x)).abs();
      if (next > jump) jump = next;
    }
  }
  final pass = jump <= 6 && green(10) > 0;
  final result =
      'Offscreen ${pass ? 'PASS' : 'FAIL'} maxEdgeJump=$jump '
      'sideGreen=${green(10)} coreGreen=${green(340)}';
  const report = String.fromEnvironment('BDK_DIFFUSION_REPORT');
  if (report.isNotEmpty) {
    await File('$report.txt').writeAsString(result);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$report.png').writeAsBytes(png!.buffer.asUint8List());
  }
  image.dispose();
  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(result),
              SizedBox(
                width: 680,
                height: 300,
                child: CustomPaint(
                  painter: FirmwareLightPainter(image: source),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
