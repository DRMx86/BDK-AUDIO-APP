import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Owns the final GPU field handles, independently of a borrowed source image.
class GpuLightImages {
  GpuLightImages(this.core, this.halo);
  final ui.Image core, halo;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    core.dispose();
    halo.dispose();
  }
}

/// Four reusable GPU passes owned by one preview. No native CPU field builder
/// or effect renderer is involved; rendering only borrows its source image.
class GpuLightFieldRenderer {
  factory GpuLightFieldRenderer(ui.FragmentProgram program) {
    _requireImpeller();
    if (!identical(program, _validatedProgram)) {
      throw StateError('Load and validate GPU float fields before rendering');
    }
    return GpuLightFieldRenderer._(program);
  }

  GpuLightFieldRenderer._(ui.FragmentProgram program) {
    try {
      for (var i = 0; i < 4; i++) {
        _shaders.add(program.fragmentShader());
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  static Future<ui.FragmentProgram?>? _loading;
  static ui.FragmentProgram? _validatedProgram;
  static Map<String, Object?> _lastProbe = const {
    'status': 'not_started',
    'accepted': false,
  };
  static Map<String, Object?> get lastProbe => Map.unmodifiable(_lastProbe);

  /// Cached capability decision. Skia silently quantizes Picture float targets,
  /// so a backend flag alone never enables the path: a completed GPU Gaussian
  /// readback must match an independent double-precision oracle first.
  static Future<ui.FragmentProgram?> load() => _loading ??= _load();

  static void _report(Map<String, Object?> report) {
    _lastProbe = Map.unmodifiable(report);
    debugPrint('BDK_GPU_LIGHT_PROBE $_lastProbe');
  }

  static Future<ui.FragmentProgram?> _load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      _report(const {
        'status': 'unsupported_backend',
        'accepted': false,
        'impeller': false,
      });
      return null;
    }
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/led_gaussian_pass.frag',
      ).timeout(const Duration(seconds: 2));
      final report = await _probe(program);
      _report(report);
      if (report['accepted'] != true) return null;
      _validatedProgram = program;
      return program;
    } catch (error) {
      _report({
        'status': 'probe_failed',
        'accepted': false,
        'impeller': true,
        'error': error.toString(),
      });
      return null;
    }
  }

  static void _requireImpeller() {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      throw UnsupportedError('GPU float light fields require Impeller');
    }
  }

  final _shaders = <ui.FragmentShader>[];
  bool _disposed = false;

  GpuLightImages render(ui.Image source, double haloSigma) {
    if (_disposed) throw StateError('GPU light renderer was disposed');
    _requireImpeller();
    if (source.width != 16 || source.height != 16) {
      throw ArgumentError('Expected a 16 by 16 source image');
    }
    if (!haloSigma.isFinite || haloSigma < .25 || haloSigma > 32) {
      throw ArgumentError('Expected a finite halo sigma from .25 to 32');
    }
    ui.Image? coreX, haloX, core, halo;
    try {
      coreX = _pass(_shaders[0], source, 256, 16, -4, 24, .8, false);
      core = _pass(_shaders[1], coreX, 256, 256, -4, 24, .8, true);
      coreX.dispose();
      coreX = null;
      haloX = _pass(_shaders[2], source, 128, 16, 0, 16, haloSigma, false);
      halo = _pass(_shaders[3], haloX, 128, 128, 0, 16, haloSigma, true);
      return GpuLightImages(core, halo);
    } catch (_) {
      core?.dispose();
      halo?.dispose();
      rethrow;
    } finally {
      // The downstream display lists retain the native image references.
      coreX?.dispose();
      haloX?.dispose();
    }
  }

  static ui.Image _pass(
    ui.FragmentShader shader,
    ui.Image source,
    int width,
    int height,
    double minimum,
    double span,
    double sigma,
    bool vertical,
  ) {
    shader
      ..setFloat(0, width.toDouble())
      ..setFloat(1, height.toDouble())
      ..setFloat(2, minimum)
      ..setFloat(3, span)
      ..setFloat(4, sigma)
      ..setFloat(5, vertical ? 1 : 0)
      ..setImageSampler(0, source, filterQuality: ui.FilterQuality.none);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()
        ..shader = shader
        ..blendMode = ui.BlendMode.src
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(
        width,
        height,
        targetFormat: ui.TargetPixelFormat.rgbaFloat32,
      );
    } finally {
      picture.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final shader in _shaders) {
      shader.dispose();
    }
    _shaders.clear();
  }

  static Future<Map<String, Object?>> _probe(ui.FragmentProgram program) async {
    final watch = Stopwatch()..start();
    GpuLightFieldRenderer? renderer;
    ui.Image? source;
    GpuLightImages? fields;
    try {
      renderer = GpuLightFieldRenderer._(program);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // RGBA8 fixed single cell. Fractional values must be produced by the GPU
      // Gaussian itself, never by a fractional Canvas drawColor argument.
      canvas.drawRect(
        const ui.Rect.fromLTWH(8, 8, 1, 1),
        ui.Paint()
          ..color = const ui.Color(0xff804020)
          ..blendMode = ui.BlendMode.src
          ..isAntiAlias = false,
      );
      final picture = recorder.endRecording();
      try {
        source = picture.toImageSync(16, 16);
      } finally {
        picture.dispose();
      }
      fields = renderer.render(source, 1.7);
      // Exercise deferred-resource ownership as well as precision: the final
      // images must finish without live source handles or mutable shaders.
      source.dispose();
      source = null;
      renderer.dispose();
      renderer = null;
      final bytes = await Future.wait<ByteData?>([
        fields.core.toByteData(format: ui.ImageByteFormat.rawExtendedRgba128),
        fields.halo.toByteData(format: ui.ImageByteFormat.rawExtendedRgba128),
      ]).timeout(const Duration(seconds: 2));
      if (bytes[0] == null || bytes[1] == null) {
        throw StateError('GPU float readback was empty');
      }
      final core = _compare(bytes[0]!, 256, -4, 24, .8, const [
        (133, 133),
        (128, 129),
        (85, 130),
      ]);
      final halo = _compare(bytes[1]!, 128, 0, 16, 1.7, const [
        (67, 67),
        (64, 65),
        (42, 65),
      ]);
      final accepted =
          core.isFinite && halo.isFinite && core < 1e-5 && halo < 1e-5;
      return {
        'status': accepted ? 'ready' : 'float_conformance_failed',
        'accepted': accepted,
        'impeller': true,
        'coreMaxError': core.isFinite ? core : null,
        'haloMaxError': halo.isFinite ? halo : null,
        'elapsedMs': watch.elapsedMilliseconds,
      };
    } finally {
      fields?.dispose();
      source?.dispose();
      renderer?.dispose();
    }
  }

  static double _compare(
    ByteData bytes,
    int width,
    double minimum,
    double span,
    double sigma,
    List<(int, int)> nodes,
  ) {
    const channels = [128, 64, 32];
    var worst = 0.0;
    for (final (x, y) in nodes) {
      final px = minimum + x * span / (width - 1);
      final py = minimum + y * span / (width - 1);
      final distanceSquared = (px - 8.5) * (px - 8.5) + (py - 8.5) * (py - 8.5);
      final weight =
          math.exp(-distanceSquared / (2 * sigma * sigma)) /
          (2 * math.pi * sigma * sigma);
      for (var channel = 0; channel < 4; channel++) {
        final expected = channel == 3 ? 1.0 : channels[channel] / 255 * weight;
        final actual = bytes.getFloat32(
          ((y * width + x) * 4 + channel) * 4,
          Endian.host,
        );
        if (!actual.isFinite) return double.infinity;
        worst = math.max(worst, (actual - expected).abs());
      }
    }
    return worst;
  }
}
