import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _LightFieldsNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Int32,
      Float,
      Pointer<Float>,
      Int32,
      Pointer<Float>,
      Int32,
    );
typedef _LightFieldsDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      double,
      Pointer<Float>,
      int,
      Pointer<Float>,
      int,
    );

/// Owned continuous Gaussian fields, with no gain or 8-bit intermediate.
///
/// Row-major RGBA nodes include both domain endpoints: core [-4,20], halo
/// [0,16]. Source LED centers remain x+.5/y+.5. All output alpha values are 1.
class NativeLightFields {
  const NativeLightFields({required this.core, required this.halo});

  static const coreWidth = 256, coreHeight = 256;
  static const haloWidth = 128, haloHeight = 128;
  static const coreFloatCount = coreWidth * coreHeight * 4;
  static const haloFloatCount = haloWidth * haloHeight * 4;

  final Float32List core, halo;
}

/// Owns one firmware effect and its buffers. Render returns an owned RGBA copy.
class NativeLedEngine {
  NativeLedEngine({DynamicLibrary? library}) {
    _library = library ?? _load();
    final lib = _library;
    _create = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'bdk_led_create',
        );
    _destroy = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('bdk_led_destroy');
    _settings = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
          int Function(Pointer<Void>, Pointer<Uint8>, int)
        >('bdk_led_settings');
    _render = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Float>,
            Uint8,
            Int32,
            Pointer<Uint8>,
            Int32,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Float>,
            int,
            int,
            Pointer<Uint8>,
            int,
          )
        >('bdk_led_render');
    _context = _create();
    if (_context == nullptr) {
      throw StateError('Could not allocate firmware renderer');
    }
    _audio = calloc<Float>(7);
    _output = calloc<Uint8>(1024);
    _config = calloc<Uint8>(10);
  }
  static DynamicLibrary _load() {
    if (Platform.isWindows) return DynamicLibrary.open('bdk_led_engine.dll');
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libbdk_led_engine.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.open('bdk_led_engine.framework/bdk_led_engine');
    }
    throw UnsupportedError('Firmware renderer is unavailable on this platform');
  }

  late final Pointer<Void> Function() _create;
  late final DynamicLibrary _library;
  // Keep the new export lazy so render-only consumers can retain their loaded
  // library until their owning application explicitly upgrades/restarts it.
  late final _LightFieldsDart _computeFields = _library
      .lookupFunction<_LightFieldsNative, _LightFieldsDart>(
        'bdk_led_light_fields',
      );
  late final void Function(Pointer<Void>) _destroy;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _settings;
  late final int Function(
    Pointer<Void>,
    Pointer<Float>,
    int,
    int,
    Pointer<Uint8>,
    int,
  )
  _render;
  late Pointer<Void> _context;
  late final Pointer<Float> _audio;
  late final Pointer<Uint8> _output, _config;
  Pointer<Uint8> _lightInput = nullptr;
  Pointer<Float> _coreField = nullptr, _haloField = nullptr;
  bool _disposed = false;
  void _check() {
    if (_disposed) throw StateError('Renderer was disposed');
  }

  void configure(List<int> payload) {
    _check();
    if (payload.length != 10 || payload.any((v) => v < 0 || v > 255)) {
      throw ArgumentError('Expected ten LED bytes');
    }
    // Off is a wire-protocol sentinel, not one of the 22 source effects.
    // Render it as a zero-brightness frame without changing their algorithms.
    final off = payload[0] == 255;
    if (off && payload[1] > 100) {
      throw ArgumentError('Invalid LED brightness');
    }
    _config
        .asTypedList(10)
        .setAll(0, off ? [0, 0, ...payload.skip(2)] : payload);
    if (_settings(_context, _config, 10) != 1) {
      throw ArgumentError('Invalid LED settings');
    }
  }

  Uint8List render({
    bool demo = false,
    List<double>? audio,
    bool beat = false,
    bool audioActive = false,
  }) {
    _check();
    final values = audio ?? const [0.0, 0.0, 0.0, -60.0, -60.0, -60.0, 0.0];
    if (values.length != 7 || values.any((v) => !v.isFinite)) {
      throw ArgumentError('Expected seven finite audio values');
    }
    _audio.asTypedList(7).setAll(0, values);
    final flags = (beat ? 1 : 0) | (audioActive ? 2 : 0);
    if (_render(_context, _audio, flags, demo ? 1 : 0, _output, 1024) != 1024) {
      throw StateError('Renderer rejected frame');
    }
    return Uint8List.fromList(_output.asTypedList(1024));
  }

  /// Reconstructs an existing frame without advancing/configuring its effect.
  /// Returned float32 lists are owned copies that survive later calls/disposal.
  NativeLightFields lightFields(Uint8List source, double haloSigma) {
    _check();
    if (source.length != 1024) {
      throw ArgumentError('Expected a 16 by 16 RGBA frame');
    }
    if (!haloSigma.isFinite || haloSigma < .25 || haloSigma > 32) {
      throw ArgumentError('Expected a finite halo sigma from .25 to 32');
    }
    final compute = _computeFields;
    // Each allocation remains owned if a later allocation fails, and is either
    // reused by a subsequent call or released by dispose.
    if (_lightInput == nullptr) _lightInput = calloc<Uint8>(1024);
    if (_coreField == nullptr) {
      _coreField = calloc<Float>(NativeLightFields.coreFloatCount);
    }
    if (_haloField == nullptr) {
      _haloField = calloc<Float>(NativeLightFields.haloFloatCount);
    }
    _lightInput.asTypedList(1024).setAll(0, source);
    if (compute(
          _context,
          _lightInput,
          1024,
          haloSigma,
          _coreField,
          NativeLightFields.coreFloatCount,
          _haloField,
          NativeLightFields.haloFloatCount,
        ) !=
        1) {
      throw StateError('Renderer rejected light fields');
    }
    return NativeLightFields(
      core: Float32List.fromList(
        _coreField.asTypedList(NativeLightFields.coreFloatCount),
      ),
      halo: Float32List.fromList(
        _haloField.asTypedList(NativeLightFields.haloFloatCount),
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_context);
    _context = nullptr;
    calloc.free(_audio);
    calloc.free(_output);
    calloc.free(_config);
    if (_lightInput != nullptr) calloc.free(_lightInput);
    if (_coreField != nullptr) calloc.free(_coreField);
    if (_haloField != nullptr) calloc.free(_haloField);
    _lightInput = nullptr;
    _coreField = nullptr;
    _haloField = nullptr;
  }
}
