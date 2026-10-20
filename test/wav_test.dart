import 'dart:typed_data';
import 'package:bdk_audio/features/sounds/wav_audio.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fixture({
  int channels = 1,
  int rate = 22050,
  List<int> samples = const [-32768, -1, 0, 32767],
  bool extraChunks = false,
}) {
  final chunks = BytesBuilder();
  void chunk(String id, Uint8List data) {
    chunks.add(id.codeUnits);
    chunks.add(
      (ByteData(
        4,
      )..setUint32(0, data.length, Endian.little)).buffer.asUint8List(),
    );
    chunks.add(data);
    if (data.length.isOdd) chunks.addByte(0);
  }

  final fmt = ByteData(extraChunks ? 18 : 16)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, channels, Endian.little)
    ..setUint32(4, rate, Endian.little)
    ..setUint32(8, rate * channels * 2, Endian.little)
    ..setUint16(12, channels * 2, Endian.little)
    ..setUint16(14, 16, Endian.little);
  if (extraChunks) chunk('JUNK', Uint8List.fromList([1, 2, 3]));
  chunk('fmt ', fmt.buffer.asUint8List());
  if (extraChunks) chunk('LIST', Uint8List.fromList([0, 0, 0, 0]));
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  chunk('data', data.buffer.asUint8List());
  final body = chunks.takeBytes();
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...(ByteData(
      4,
    )..setUint32(0, body.length + 4, Endian.little)).buffer.asUint8List(),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
}

void main() {
  test(
    'canonical encoding round-trips signed PCM and little-endian header fields',
    () {
      final input = Int16List.fromList([-32768, -1, 0, 32767]);
      final bytes = Pcm16Wave.encodeMono(input, 16000);
      expect(bytes.length, 52);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(4, Endian.little), 44);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(28, Endian.little), 32000);
      final wave = Pcm16Wave.decode(bytes);
      expect(wave.channels, 1);
      expect(wave.sampleRate, 16000);
      expect(wave.samples, orderedEquals(input));
    },
  );

  test('chunk walking handles non44-byte headers and odd metadata padding', () {
    final bytes = fixture(channels: 2, rate: 48000, extraChunks: true);
    final wave = Pcm16Wave.decode(bytes);
    expect(wave.channels, 2);
    expect(wave.frames, 2);
    expect(wave.samples, [-32768, -1, 0, 32767]);
  });

  test('truncated chunks bad PCM bounds and empty data are rejected', () {
    final good = fixture();
    for (final corrupt in [
      good.sublist(0, good.length - 1),
      Uint8List.fromList(good)..[0] = 0,
      Uint8List.fromList(good)..[20] = 3,
      Uint8List.fromList(good)..[22] = 0,
      Uint8List.fromList(good)..[32] = 4,
      Uint8List.fromList(good)..[34] = 24,
      fixture(samples: const []),
    ]) {
      expect(() => Pcm16Wave.decode(corrupt), throwsFormatException);
    }
    expect(
      () => Pcm16Wave.decode(good, maximumBytes: good.length - 1),
      throwsFormatException,
    );
    expect(
      () => Pcm16Wave.encodeMono(Int16List(0), 22050),
      throwsArgumentError,
    );
  });

  test(
    'a short notification keeps preferred quality and a longer one lowers rate explicitly',
    () {
      final short = SoundClipPolicy.plan(total: const Duration(seconds: 2));
      expect(short.outputRate, 22050);
      expect(short.frameCount, 44100);
      expect(short.outputBytes, 88244);
      expect(short.lowerRate, isFalse);
      final medium = SoundClipPolicy.plan(total: const Duration(seconds: 6));
      expect(medium.outputRate, 16000);
      expect(medium.lowerRate, isTrue);
      expect(medium.outputBytes, 192044);
    },
  );

  test(
    'overlong input requires an explicit clip and never silently truncates',
    () {
      final whole = SoundClipPolicy.plan(total: const Duration(minutes: 1));
      expect(whole.requiresTrim, isTrue);
      expect(whole.outputRate, isNull);
      expect(whole.start, Duration.zero);
      expect(whole.end, const Duration(minutes: 1));
      final selected = SoundClipPolicy.plan(
        total: const Duration(minutes: 1),
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 20),
      );
      expect(selected.outputRate, 8000);
      expect(selected.isExcerpt, isTrue);
      expect(selected.outputBytes, 160044);
      expect(
        () => SoundClipPolicy.plan(
          total: const Duration(seconds: 1),
          start: const Duration(seconds: 2),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'exact200KiB boundary includes the WAV header and one additional sample needs trim',
    () {
      final maximum = SoundClipPolicy.maximumDuration;
      final fit = SoundClipPolicy.plan(total: maximum);
      expect(fit.outputRate, 8000);
      expect(fit.frameCount, 102378);
      expect(fit.outputBytes, 204800);
      expect(
        SoundClipPolicy.plan(
          total: maximum + const Duration(microseconds: 125),
        ).requiresTrim,
        isTrue,
      );
    },
  );
}
