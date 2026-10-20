import 'dart:typed_data';
import 'package:bdk_audio/features/transfers/sound_transfer_packets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sound_transfer_test_support.dart';

void main() {
  test(
    'sound command bytes and u24 total size match the existing protocol',
    () {
      expect(SoundTransferPackets.mute(true), [0x10, 1]);
      expect(SoundTransferPackets.mute(false), [0x10, 0]);
      expect(SoundTransferPackets.delete(3), [0x11, 3]);
      expect(SoundTransferPackets.start(2, 0x010203), [0x12, 2, 3, 2, 1]);
      expect(SoundTransferPackets.start(0, 204800), [0x12, 0, 0, 32, 3]);
      expect(SoundTransferPackets.data(255, [4, 5, 6]), [0x13, 255, 4, 5, 6]);
      expect(SoundTransferPackets.end(), [0x14]);
    },
  );

  test(
    'builders reject invalid type, size, sequence, empty and oversize data',
    () {
      expect(() => SoundTransferPackets.delete(4), throwsRangeError);
      expect(() => SoundTransferPackets.start(-1, 44), throwsRangeError);
      expect(() => SoundTransferPackets.start(0, 0), throwsRangeError);
      expect(() => SoundTransferPackets.start(0, 204801), throwsRangeError);
      expect(() => SoundTransferPackets.data(256, [1]), throwsRangeError);
      expect(() => SoundTransferPackets.data(0, []), throwsArgumentError);
      expect(
        () => SoundTransferPackets.data(0, List.filled(513, 0)),
        throwsArgumentError,
      );
      expect(() => SoundTransferPackets.data(0, [256]), throwsArgumentError);
    },
  );

  test(
    '20-byte characteristic capacity carries exactly18 data bytes without a forced minimum',
    () {
      final raw = Uint8List.fromList(List.generate(40, (index) => index));
      final chunks = SoundTransferPackets.chunks(raw, 20).toList();
      expect(chunks.map((chunk) => chunk.dataLength), [18, 18, 4]);
      expect(chunks.map((chunk) => chunk.offset), [0, 18, 36]);
      expect(chunks.first.packet, [
        0x13,
        0,
        ...List.generate(18, (index) => index),
      ]);
      expect(chunks.expand((chunk) => chunk.packet.skip(2)), raw);
      expect(chunks.every((chunk) => chunk.packet.length <= 20), isTrue);
    },
  );

  test(
    'capacity includes the two-byte header and respects the512-byte worker bound',
    () {
      expect(SoundTransferPackets.dataCapacity(20), 18);
      expect(SoundTransferPackets.dataCapacity(244), 242);
      expect(SoundTransferPackets.dataCapacity(512), 510);
      expect(SoundTransferPackets.dataCapacity(600), 512);
      expect(() => SoundTransferPackets.dataCapacity(2), throwsArgumentError);
    },
  );

  test(
    'sequence starts at0 and wraps255 to0 without dropping or duplicating bytes',
    () {
      final bytes = Uint8List.fromList(
        List.generate(18 * 258, (index) => index & 255),
      );
      final chunks = SoundTransferPackets.chunks(bytes, 20).toList();
      expect(chunks[0].sequence, 0);
      expect(chunks[255].sequence, 255);
      expect(chunks[256].sequence, 0);
      expect(chunks[257].sequence, 1);
      expect(chunks.expand((chunk) => chunk.packet.skip(2)), bytes);
    },
  );

  test(
    'canonical monoPCM16 WAV validation retains exact size and sample rate',
    () {
      final info = SoundTransferPackets.validateWav(
        soundWav(dataBytes: 100, sampleRate: 22050),
      );
      expect(info.totalBytes, 144);
      expect(info.dataBytes, 100);
      expect(info.samples, 50);
      expect(info.sampleRate, 22050);
      expect(
        SoundTransferPackets.validateWav(
          soundWav(dataBytes: 204756),
        ).totalBytes,
        204800,
      );
    },
  );

  test(
    'WAV gate rejects inconsistent or noncanonical compressed/stereo/float data',
    () {
      final cases = <Uint8List>[];
      for (final change in <int, int>{
        0: 0,
        8: 0,
        12: 0,
        16: 18,
        20: 3,
        22: 2,
        28: 0,
        32: 4,
        34: 24,
        36: 0,
        40: 9,
      }.entries) {
        final bytes = soundWav(dataBytes: 100);
        bytes[change.key] = change.value;
        cases.add(bytes);
      }
      cases.add(soundWav(dataBytes: 100)..[4] = 0);
      cases.add(soundWav(dataBytes: 3));
      cases.add(soundWav(dataBytes: 0));
      cases.add(soundWav(dataBytes: 204758));
      cases.add(soundWav(dataBytes: 100, sampleRate: 192000));
      cases.add(Uint8List(43));
      for (final bytes in cases) {
        expect(
          () => SoundTransferPackets.validateWav(bytes),
          throwsFormatException,
        );
      }
    },
  );
}
