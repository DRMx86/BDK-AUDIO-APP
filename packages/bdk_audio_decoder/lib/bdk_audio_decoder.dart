import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

class AudioProbe {
  const AudioProbe({
    required this.sampleRate,
    required this.channels,
    required this.frames,
  });
  final int sampleRate, channels, frames;
  Duration get duration => Duration(
    microseconds:
        (frames ~/ sampleRate) * 1000000 +
        (frames % sampleRate) * 1000000 ~/ sampleRate,
  );
}

class AudioDecoderException implements Exception {
  const AudioDecoderException(this.code);
  final int code;
  String get message => switch (code) {
    1 => 'Invalid audio decoding request.',
    2 => 'The audio file could not be opened or read.',
    3 => 'Choose an audio file no larger than 64 MiB.',
    4 => 'This audio format is not supported by this device.',
    5 => 'The audio file is empty, damaged or unsupported.',
    6 => 'The selected audio segment is outside the file.',
    7 => 'The audio output buffer is too small.',
    8 => 'There is not enough memory to decode this audio.',
    9 => 'The selected audio segment could not be decoded completely.',
    10 => 'The audio file path is not valid UTF-8.',
    _ => 'Audio decoding failed (code $code).',
  };
  @override
  String toString() => message;
}

final class _NativeProbe extends Struct {
  @Uint32()
  external int sampleRate;
  @Uint32()
  external int channels;
  @Uint64()
  external int frames;
}

typedef _ProbeNative =
    Int32 Function(Pointer<Utf8>, Int32, Pointer<_NativeProbe>);
typedef _ProbeDart = int Function(Pointer<Utf8>, int, Pointer<_NativeProbe>);
typedef _DecodeNative =
    Int32 Function(
      Pointer<Utf8>,
      Int32,
      Uint32,
      Uint64,
      Uint32,
      Pointer<Int16>,
      Uint32,
      Pointer<Uint32>,
    );
typedef _DecodeDart =
    int Function(
      Pointer<Utf8>,
      int,
      int,
      int,
      int,
      Pointer<Int16>,
      int,
      Pointer<Uint32>,
    );

/// Stateless synchronous bindings. Prefer the async isolate methods from UI code.
/// No playback, device initialization, global engine or persistent decoder handle.
class NativeAudioDecoder {
  NativeAudioDecoder({DynamicLibrary? library, String? libraryPath})
    : _libraryPath = libraryPath,
      _customLibrary = library != null {
    if (library != null && libraryPath != null) {
      throw ArgumentError('Choose a library or libraryPath, not both.');
    }
    final source =
        library ??
        (libraryPath == null ? _load() : DynamicLibrary.open(libraryPath));
    _probe = source.lookupFunction<_ProbeNative, _ProbeDart>('bdk_audio_probe');
    _decode = source.lookupFunction<_DecodeNative, _DecodeDart>(
      'bdk_audio_decode_segment',
    );
  }
  static const maxSamples = 102378;
  static const outputRates = <int>[22050, 16000, 11025, 8000];
  final String? _libraryPath;
  final bool _customLibrary;
  late final _ProbeDart _probe;
  late final _DecodeDart _decode;
  static DynamicLibrary _load() {
    if (Platform.isWindows) return DynamicLibrary.open('bdk_audio_decoder.dll');
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libbdk_audio_decoder.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        return DynamicLibrary.open(
          'bdk_audio_decoder.framework/bdk_audio_decoder',
        );
      } on ArgumentError {
        return DynamicLibrary.process();
      }
    }
    throw UnsupportedError(
      'Native audio decoding is unavailable on this platform.',
    );
  }

  Pointer<Utf8> _path(String path) {
    final bytes = utf8.encode(path);
    if (bytes.isEmpty || bytes.length > 16384 || path.contains('\u0000')) {
      throw ArgumentError(
        'Use a nonempty UTF-8 file path of at most 16384 bytes without NUL.',
      );
    }
    return path.toNativeUtf8(allocator: calloc);
  }

  AudioProbe probe(String path) {
    final nativePath = _path(path), info = calloc<_NativeProbe>();
    try {
      final code = _probe(nativePath, nativePath.length, info);
      if (code != 0) throw AudioDecoderException(code);
      return AudioProbe(
        sampleRate: info.ref.sampleRate,
        channels: info.ref.channels,
        frames: info.ref.frames,
      );
    } finally {
      calloc.free(nativePath);
      calloc.free(info);
    }
  }

  Int16List decodeSegment(
    String path, {
    required int outputRate,
    required int startFrame,
    required int frameCount,
  }) {
    if (!outputRates.contains(outputRate) ||
        startFrame < 0 ||
        frameCount < 1 ||
        frameCount > maxSamples) {
      throw ArgumentError(
        'Use a supported output rate, nonnegative output-frame offset and 1..$maxSamples samples.',
      );
    }
    final nativePath = _path(path),
        samples = calloc<Int16>(frameCount),
        written = calloc<Uint32>();
    try {
      final code = _decode(
        nativePath,
        nativePath.length,
        outputRate,
        startFrame,
        frameCount,
        samples,
        frameCount,
        written,
      );
      if (code != 0) throw AudioDecoderException(code);
      if (written.value != frameCount) throw const AudioDecoderException(9);
      return Int16List.fromList(samples.asTypedList(frameCount));
    } finally {
      calloc.free(nativePath);
      calloc.free(samples);
      calloc.free(written);
    }
  }

  Future<AudioProbe> probeAsync(String path) {
    _checkAsync();
    final arguments = (path, _libraryPath);
    return Isolate.run(() => _probeWorker(arguments));
  }

  Future<Int16List> decodeSegmentAsync(
    String path, {
    required int outputRate,
    required int startFrame,
    required int frameCount,
  }) {
    _checkAsync();
    final arguments = (path, _libraryPath, outputRate, startFrame, frameCount);
    return Isolate.run(() => _decodeWorker(arguments));
  }

  void _checkAsync() {
    if (_customLibrary) {
      throw UnsupportedError(
        'Async decoding needs the bundled library or libraryPath so each isolate can open it independently.',
      );
    }
  }
}

AudioProbe _probeWorker((String, String?) args) =>
    NativeAudioDecoder(libraryPath: args.$2).probe(args.$1);
Int16List _decodeWorker((String, String?, int, int, int) args) =>
    NativeAudioDecoder(libraryPath: args.$2).decodeSegment(
      args.$1,
      outputRate: args.$3,
      startFrame: args.$4,
      frameCount: args.$5,
    );
