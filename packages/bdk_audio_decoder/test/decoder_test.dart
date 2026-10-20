import 'dart:io';
import 'dart:typed_data';
import 'package:bdk_audio_decoder/bdk_audio_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final library = '$root/build/native/Release/bdk_audio_decoder.dll';
  final input = '$root/build/fixtures/ramp.wav';
  test(
    'native AAC and M4A fallback also works through isolate bindings',
    () async {
      final decoder = NativeAudioDecoder(libraryPath: library);
      final probe = await decoder.probeAsync('$root/build/fixtures/real.m4a');
      expect(
        (probe.sampleRate, probe.channels, probe.frames),
        (16000, 1, 32000),
      );
      final pcm = await decoder.decodeSegmentAsync(
        '$root/build/fixtures/real.aac',
        outputRate: 11025,
        startFrame: 1000,
        frameCount: 400,
      );
      expect(pcm.length, 400);
      expect(pcm.any((sample) => sample.abs() > 100), isTrue);
    },
    skip: !Platform.isWindows,
  );
  test(
    'real native probe reports source frames and finite duration',
    () {
      final d = NativeAudioDecoder(libraryPath: library), p = d.probe(input);
      expect((p.sampleRate, p.channels, p.frames), (16000, 1, 32000));
      expect(p.duration, const Duration(seconds: 2));
    },
    skip: !Platform.isWindows,
  );
  test(
    'real decode returns owned bounded PCM16 and output-frame positions',
    () {
      final d = NativeAudioDecoder(libraryPath: library);
      final result = d.decodeSegment(
        input,
        outputRate: 16000,
        startFrame: 123,
        frameCount: 100,
      );
      expect(result, isA<Int16List>());
      expect(result.length, 100);
      expect(result[0], 123 * 37 - 10000);
      d.decodeSegment(input, outputRate: 8000, startFrame: 0, frameCount: 100);
      expect(result[0], 123 * 37 - 10000);
      expect(
        () => d.decodeSegment(
          input,
          outputRate: 48000,
          startFrame: 0,
          frameCount: 100,
        ),
        throwsArgumentError,
      );
      expect(
        () => d.decodeSegment(
          input,
          outputRate: 8000,
          startFrame: -1,
          frameCount: 100,
        ),
        throwsArgumentError,
      );
      expect(
        () => d.decodeSegment(
          input,
          outputRate: 8000,
          startFrame: 0,
          frameCount: 102379,
        ),
        throwsArgumentError,
      );
      expect(
        () => d.decodeSegment(
          input,
          outputRate: 16000,
          startFrame: 31999,
          frameCount: 2,
        ),
        throwsA(isA<AudioDecoderException>().having((e) => e.code, 'code', 6)),
      );
    },
    skip: !Platform.isWindows,
  );
  test(
    'async isolate methods open their own native decoder and preserve data',
    () async {
      final d = NativeAudioDecoder(libraryPath: library);
      expect((await d.probeAsync(input)).frames, 32000);
      final pcm = await d.decodeSegmentAsync(
        input,
        outputRate: 16000,
        startFrame: 123,
        frameCount: 100,
      );
      expect(pcm[0], 123 * 37 - 10000);
    },
    skip: !Platform.isWindows,
  );
  test(
    'invalid paths and native failures are typed and do not return silence',
    () {
      final d = NativeAudioDecoder(libraryPath: library);
      expect(() => d.probe('a\u0000b'), throwsArgumentError);
      expect(
        () => d.probe('$root/build/fixtures/invalid.bin'),
        throwsA(isA<AudioDecoderException>()),
      );
      expect(
        () => d.probe('$root/build/fixtures/missing.wav'),
        throwsA(isA<AudioDecoderException>().having((e) => e.code, 'code', 2)),
      );
    },
    skip: !Platform.isWindows,
  );
}
