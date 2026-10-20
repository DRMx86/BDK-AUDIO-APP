import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdk_led_engine/bdk_led_engine.dart';
import 'package:flutter/material.dart';
import 'gpu_light_fields.dart';

class LedDiffusion {
  static Future<ui.FragmentProgram>? _loading;
  static Future<ui.FragmentProgram> load() =>
      _loading ??= ui.FragmentProgram.fromAsset('shaders/led_diffusion.frag');
}

/// No RGBA8 intermediate: fractional light must reach the final display shader.
Future<ui.Image> decodeLightField(
  Float32List pixels,
  int width,
  int height,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
  );
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      rowBytes: width * 16,
      pixelFormat: ui.PixelFormat.rgbaFloat32,
    );
    codec = await descriptor.instantiateCodec(
      targetFormat: ui.TargetPixelFormat.rgbaFloat32,
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Color? uniformLightColor(List<int> pixels) {
  final r = pixels[0], g = pixels[1], b = pixels[2];
  for (var i = 4; i < pixels.length; i += 4) {
    if (pixels[i] != r || pixels[i + 1] != g || pixels[i + 2] != b) return null;
  }
  return Color.fromARGB(255, r, g, b);
}

typedef LightFieldBuilder =
    NativeLightFields Function(Uint8List source, double haloSigma);
typedef LightFieldDecoder =
    Future<ui.Image> Function(Float32List pixels, int width, int height);

/// Owns decoded optical fields for one preview, coalescing new source frames.
/// Layout/texture work never advances the firmware effect's animation clock.
class FirmwareLightView extends StatefulWidget {
  const FirmwareLightView({
    super.key,
    required this.image,
    required this.pixels,
    this.shader,
    this.fieldBuilder,
    this.gpuProgram,
    this.opacity = 1,
    this.titleShade = false,
    this.hasEmission = true,
    this.uniformColor,
    this.willChange = false,
    this.paintKey,
    this.decoder = decodeLightField,
  });
  final ui.Image? image;
  final Uint8List? pixels;
  final ui.FragmentShader? shader;
  final LightFieldBuilder? fieldBuilder;
  final ui.FragmentProgram? gpuProgram;
  final LightFieldDecoder decoder;
  final double opacity;
  final bool titleShade, hasEmission, willChange;
  final Color? uniformColor;
  final Key? paintKey;

  @override
  State<FirmwareLightView> createState() => _FirmwareLightViewState();
}

class _LightImages {
  _LightImages(this.source, this.core, this.halo, this.sigma);
  final ui.Image source, core, halo;
  final double sigma;
  void dispose() {
    source.dispose();
    core.dispose();
    halo.dispose();
  }
}

class _FirmwareLightViewState extends State<FirmwareLightView> {
  static bool _reportedGpuUse = false;
  Size _size = Size.zero;
  Uint8List? _requested;
  double? _requestedSigma;
  _LightImages? _fields;
  GpuLightFieldRenderer? _gpu;
  bool _gpuDisabled = false;
  bool _busy = false, _disabled = false;
  int _generation = 0;
  double get _sigma => 640 / math.max(_size.width, _size.height);
  bool get _needsFields =>
      widget.shader != null &&
      (widget.fieldBuilder != null ||
          (widget.gpuProgram != null && !_gpuDisabled)) &&
      widget.image != null &&
      widget.pixels != null &&
      widget.hasEmission &&
      widget.opacity > 0 &&
      widget.uniformColor == null &&
      !_size.isEmpty &&
      !_disabled;

  @override
  void didUpdateWidget(covariant FirmwareLightView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldBuilder != widget.fieldBuilder ||
        oldWidget.gpuProgram != widget.gpuProgram) {
      _generation++;
      _requested = null;
      _disabled = false;
      _gpuDisabled = false;
      _gpu?.dispose();
      _gpu = null;
      _fields?.dispose();
      _fields = null;
    }
  }

  void _pump() {
    if (!mounted || _busy || !_needsFields) return;
    final pixels = widget.pixels!, sigma = _sigma;
    if (identical(_requested, pixels) && _requestedSigma == sigma) return;
    _requested = pixels;
    _requestedSigma = sigma;
    _busy = true;
    final generation = _generation;
    final source = widget.image!.clone();
    final builder = widget.fieldBuilder, decoder = widget.decoder;
    final gpuProgram = widget.gpuProgram;
    unawaited(() async {
      try {
        // A synchronous unsupported-library error must also happen after layout.
        await Future<void>.value();
        if (!mounted ||
            generation != _generation ||
            _size.isEmpty ||
            sigma != _sigma) {
          source.dispose();
          return;
        }
        List<ui.Image>? images;
        if (gpuProgram != null && !_gpuDisabled) {
          try {
            _gpu ??= GpuLightFieldRenderer(gpuProgram);
            final fields = _gpu!.render(source, sigma);
            images = [fields.core, fields.halo];
            if (!_reportedGpuUse) {
              _reportedGpuUse = true;
              debugPrint('BDK_GPU_LIGHT_FIELDS active: impeller_float32');
            }
          } catch (error) {
            debugPrint('BDK_GPU_LIGHT_FIELDS fallback: $error');
            _gpuDisabled = true;
            _gpu?.dispose();
            _gpu = null;
          }
        }
        if (images == null) {
          if (builder == null) {
            throw UnsupportedError('No compatible light fields');
          }
          final fields = builder(pixels, sigma);
          images = await Future.wait([
            decoder(
              fields.core,
              NativeLightFields.coreWidth,
              NativeLightFields.coreHeight,
            ),
            decoder(
              fields.halo,
              NativeLightFields.haloWidth,
              NativeLightFields.haloHeight,
            ),
          ], cleanUp: (image) => image.dispose());
        }
        final decoded = _LightImages(source, images[0], images[1], sigma);
        if (!mounted ||
            generation != _generation ||
            _size.isEmpty ||
            sigma != _sigma) {
          decoded.dispose();
          return;
        }
        final previous = _fields;
        setState(() => _fields = decoded);
        previous?.dispose();
      } catch (_) {
        source.dispose();
        // Older native libraries/unsupported textures retain the direct shader.
        if (mounted && generation == _generation) {
          setState(() => _disabled = true);
        }
      } finally {
        _busy = false;
        // Accept a completed frame first, then decode the newest pending frame.
        // Discarding on every incoming source frame would starve playback.
        _pump();
      }
    }());
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      _pump();
      final fields = _needsFields && _fields?.sigma == _sigma ? _fields : null;
      return CustomPaint(
        key: widget.paintKey,
        isComplex: true,
        willChange: widget.willChange,
        painter: FirmwareLightPainter(
          image: fields?.source ?? widget.image,
          shader: widget.shader,
          opacity: widget.opacity,
          pixelRatio: View.of(context).devicePixelRatio,
          titleShade: widget.titleShade,
          hasEmission: widget.hasEmission,
          uniformColor: widget.uniformColor,
          coreField: fields?.core,
          haloField: fields?.halo,
        ),
      );
    },
  );

  @override
  void dispose() {
    _generation++;
    _fields?.dispose();
    _gpu?.dispose();
    super.dispose();
  }
}

class FirmwareLightPainter extends CustomPainter {
  const FirmwareLightPainter({
    required this.image,
    this.opacity = 1,
    this.shader,
    this.pixelRatio = 1,
    this.titleShade = false,
    this.hasEmission = true,
    this.uniformColor,
    this.coreField,
    this.haloField,
  });
  final ui.Image? image;
  final double opacity, pixelRatio;
  final ui.FragmentShader? shader;
  final bool titleShade, hasEmission;
  final Color? uniformColor;
  final ui.Image? coreField, haloField;

  static Rect containedRect(Size size) => Rect.fromCenter(
    center: size.center(Offset.zero),
    width: math.min(size.width, size.height),
    height: math.min(size.width, size.height),
  );
  static Rect coverRect(Size size) => Rect.fromCenter(
    center: size.center(Offset.zero),
    width: math.max(size.width, size.height),
    height: math.max(size.width, size.height),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final frame = image;
    if (frame == null || size.isEmpty) return;
    final bounds = Offset.zero & size;
    if (!hasEmission || opacity <= 0) {
      return;
    }
    final diffusion = shader;
    if (diffusion != null) {
      final color = uniformColor;
      diffusion
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, opacity)
        ..setFloat(3, pixelRatio)
        ..setFloat(4, titleShade ? 1 : 0)
        ..setFloat(5, color == null ? 0 : 1)
        ..setFloat(6, color?.r ?? 0)
        ..setFloat(7, color?.g ?? 0)
        ..setFloat(8, color?.b ?? 0)
        ..setFloat(9, coreField != null && haloField != null ? 1 : 0)
        ..setImageSampler(0, frame, filterQuality: FilterQuality.none)
        ..setImageSampler(
          1,
          coreField ?? frame,
          filterQuality: FilterQuality.low,
        )
        ..setImageSampler(
          2,
          haloField ?? frame,
          filterQuality: FilterQuality.low,
        );
      canvas.drawRect(bounds, Paint()..shader = diffusion);
      return;
    }
    // Native Gaussian fallback while the program loads, or on an unsupported
    // backend. Its source geometry and exposure stay the same.
    final source = Rect.fromLTWH(
      0,
      0,
      frame.width.toDouble(),
      frame.height.toDouble(),
    );
    final core = containedRect(size);
    canvas.save();
    canvas.clipRect(bounds);
    canvas.saveLayer(
      bounds,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: opacity),
    );
    void diffused(Rect destination, double sigma, double alpha) {
      canvas.saveLayer(
        bounds.inflate(sigma * 3),
        Paint()
          ..blendMode = BlendMode.plus
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      canvas.drawImageRect(
        frame,
        source,
        destination,
        Paint()
          ..filterQuality = FilterQuality.high
          ..color = Colors.white.withValues(alpha: alpha),
      );
      canvas.restore();
    }

    diffused(coverRect(size), 40, .65);
    diffused(core, core.width / 16 * .8, 1);
    canvas.restore();
    canvas.restore();
    if (titleShade) _shadeTitle(canvas, bounds);
  }

  void _shadeTitle(Canvas canvas, Rect bounds) {
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xa6000000),
            Color(0x99000000),
            Color(0x00000000),
            Color(0x22000000),
          ],
          stops: [0, .35, .75, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(FirmwareLightPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.opacity != opacity ||
      oldDelegate.shader != shader ||
      oldDelegate.pixelRatio != pixelRatio ||
      oldDelegate.titleShade != titleShade ||
      oldDelegate.hasEmission != hasEmission ||
      oldDelegate.uniformColor != uniformColor ||
      oldDelegate.coreField != coreField ||
      oldDelegate.haloField != haloField;
}
