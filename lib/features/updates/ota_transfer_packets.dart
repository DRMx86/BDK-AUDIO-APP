import 'dart:math' as math;
import 'dart:typed_data';

class OtaTransferChunk {
  const OtaTransferChunk({
    required this.packet,
    required this.offset,
    required this.dataLength,
    required this.sequence,
  });
  final Uint8List packet;
  final int offset, dataLength, sequence;
}

abstract final class OtaTransferPackets {
  static Uint8List begin(int size) {
    RangeError.checkValueInInterval(size, 1, 0xffffffff, 'size');
    return Uint8List.fromList([
      0x20,
      size & 255,
      (size >> 8) & 255,
      (size >> 16) & 255,
      (size >> 24) & 255,
    ]);
  }

  static Uint8List data(int sequence, List<int> bytes) {
    RangeError.checkValueInInterval(sequence, 0, 255, 'sequence');
    if (bytes.length < 2 ||
        bytes.length > 510 ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError(
        'OTA data requires 2–510 bytes; one-byte legacy flush packets do not write image data.',
      );
    }
    return Uint8List.fromList([0x21, sequence, ...bytes]);
  }

  static Uint8List end() => Uint8List.fromList([0x22]);
  static Uint8List abort() => Uint8List.fromList([0x23]);
  static int dataCapacity(int capacity) {
    if (capacity < 4) {
      throw ArgumentError(
        'BLE capacity cannot carry two image bytes plus the command header.',
      );
    }
    return math.min(capacity, 512) - 2;
  }

  static Iterable<OtaTransferChunk> chunks(
    Uint8List bytes,
    int capacity,
  ) sync* {
    final payload = dataCapacity(capacity);
    if (bytes.length < 2 || (payload == 2 && bytes.length.isOdd)) {
      throw ArgumentError(
        'Image cannot be partitioned without an ignored one-byte OTA packet.',
      );
    }
    var sequence = 1;
    for (var offset = 0; offset < bytes.length;) {
      final remaining = bytes.length - offset;
      var length = math.min(remaining, payload);
      if (remaining - length == 1) length--;
      yield OtaTransferChunk(
        packet: data(
          sequence,
          Uint8List.sublistView(bytes, offset, offset + length),
        ),
        offset: offset,
        dataLength: length,
        sequence: sequence,
      );
      offset += length;
      sequence = (sequence + 1) & 255;
    }
  }
}
