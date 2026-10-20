import 'dart:typed_data';
import 'package:bdk_audio/features/updates/ota_transfer_packets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unified OTA commands size endian and source sequence match Android builders',
    () {
      expect(OtaTransferPackets.begin(0x01020304), [0x20, 4, 3, 2, 1]);
      expect(OtaTransferPackets.data(255, [0xe9, 0x01]), [0x21, 255, 0xe9, 1]);
      expect(OtaTransferPackets.end(), [0x22]);
      expect(OtaTransferPackets.abort(), [0x23]);
    },
  );
  test(
    'MTU23 permits18 data bytes per20 byte characteristic without minimum payload floor',
    () {
      final source = Uint8List.fromList(List.generate(40, (i) => i));
      final chunks = OtaTransferPackets.chunks(source, 20).toList();
      expect(chunks.map((chunk) => chunk.dataLength), [18, 18, 4]);
      expect(chunks.map((chunk) => chunk.sequence), [1, 2, 3]);
      expect(chunks.every((chunk) => chunk.packet.length <= 20), isTrue);
      expect(chunks.expand((chunk) => chunk.packet.skip(2)), source);
    },
  );
  test('one byte tail is repartitioned never padded or silently counted', () {
    for (final size in [19, 37, 55, 73]) {
      final source = Uint8List.fromList(List.generate(size, (i) => i & 255));
      final chunks = OtaTransferPackets.chunks(source, 20).toList();
      expect(chunks.last.dataLength, 2);
      expect(chunks[chunks.length - 2].dataLength, 17);
      expect(
        chunks.every(
          (chunk) => chunk.dataLength >= 2 && chunk.packet.length <= 20,
        ),
        isTrue,
      );
      expect(chunks.expand((chunk) => chunk.packet.skip(2)), source);
    }
  });
  test(
    'sequence starts1 wraps255 to0 and emitted chunks own packet copies',
    () {
      final source = Uint8List.fromList(
        List.generate(18 * 258, (i) => i & 255),
      );
      final chunks = OtaTransferPackets.chunks(source, 20).toList();
      expect(chunks[254].sequence, 255);
      expect(chunks[255].sequence, 0);
      expect(chunks[256].sequence, 1);
      final first = chunks.first.packet.toList();
      source.fillRange(0, source.length, 0);
      expect(chunks.first.packet, first);
    },
  );
  test('attribute bound512 and ignored one byte data are enforced', () {
    expect(OtaTransferPackets.dataCapacity(20), 18);
    expect(OtaTransferPackets.dataCapacity(244), 242);
    expect(OtaTransferPackets.dataCapacity(600), 510);
    expect(() => OtaTransferPackets.dataCapacity(3), throwsArgumentError);
    expect(() => OtaTransferPackets.data(0, [1]), throwsArgumentError);
    expect(
      () => OtaTransferPackets.chunks(Uint8List(3), 4).toList(),
      throwsArgumentError,
    );
    expect(() => OtaTransferPackets.begin(0), throwsRangeError);
  });
}
