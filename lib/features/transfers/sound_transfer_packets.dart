import 'dart:typed_data';
import 'dart:math' as math;

class SoundWavInfo {
  const SoundWavInfo({
    required this.totalBytes,
    required this.dataBytes,
    required this.sampleRate,
  });
  final int totalBytes, dataBytes, sampleRate;
  int get samples => dataBytes ~/ 2;
}

class SoundTransferChunk {
  const SoundTransferChunk({
    required this.packet,
    required this.offset,
    required this.dataLength,
    required this.sequence,
  });
  final Uint8List packet;
  final int offset, dataLength, sequence;
}

abstract final class SoundTransferPackets {
  static const maxWavBytes = 200 * 1024;
  static Uint8List mute(bool value) =>
      Uint8List.fromList([0x10, value ? 1 : 0]);
  static Uint8List delete(int type) {
    RangeError.checkValueInInterval(type, 0, 3, 'soundType');
    return Uint8List.fromList([0x11, type]);
  }

  static Uint8List start(int type, int totalBytes) {
    RangeError.checkValueInInterval(type, 0, 3, 'soundType');
    RangeError.checkValueInInterval(totalBytes, 1, maxWavBytes, 'totalBytes');
    return Uint8List.fromList([
      0x12,
      type,
      totalBytes & 255,
      (totalBytes >> 8) & 255,
      (totalBytes >> 16) & 255,
    ]);
  }

  static Uint8List data(int sequence, List<int> bytes) {
    RangeError.checkValueInInterval(sequence, 0, 255, 'sequence');
    if (bytes.isEmpty ||
        bytes.length > 512 ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError('Sound data must contain 1–512 bytes.');
    }
    return Uint8List.fromList([0x13, sequence, ...bytes]);
  }

  static Uint8List end() => Uint8List.fromList([0x14]);
  static int dataCapacity(int characteristicCapacity) {
    if (characteristicCapacity < 3) {
      throw ArgumentError(
        'BLE capacity cannot hold sound data and its two-byte header.',
      );
    }
    return math.min(characteristicCapacity - 2, 512);
  }

  static Iterable<SoundTransferChunk> chunks(
    Uint8List bytes,
    int characteristicCapacity,
  ) sync* {
    final capacity = dataCapacity(characteristicCapacity);
    if (bytes.isEmpty || bytes.length > maxWavBytes) {
      throw ArgumentError('Sound bytes must fit the 200 KiB total bound.');
    }
    var sequence = 0;
    for (var offset = 0; offset < bytes.length;) {
      final length = math.min(capacity, bytes.length - offset);
      yield SoundTransferChunk(
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

  static SoundWavInfo validateWav(Uint8List bytes) {
    if (bytes.length < 46 || bytes.length > maxWavBytes) {
      throw const FormatException(
        'Prepared WAV must contain PCM samples and fit 200 KiB including its header.',
      );
    }
    bool tag(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        if (bytes[offset + index] != value.codeUnitAt(index)) return false;
      }
      return true;
    }

    final data = ByteData.sublistView(bytes);
    final rate = data.getUint32(24, Endian.little),
        length = data.getUint32(40, Endian.little);
    if (!tag(0, 'RIFF') ||
        !tag(8, 'WAVE') ||
        !tag(12, 'fmt ') ||
        !tag(36, 'data') ||
        data.getUint32(4, Endian.little) != bytes.length - 8 ||
        data.getUint32(16, Endian.little) != 16 ||
        data.getUint16(20, Endian.little) != 1 ||
        data.getUint16(22, Endian.little) != 1 ||
        data.getUint16(32, Endian.little) != 2 ||
        data.getUint16(34, Endian.little) != 16 ||
        rate < 8000 ||
        rate > 48000 ||
        data.getUint32(28, Endian.little) != rate * 2 ||
        length < 2 ||
        length.isOdd ||
        length != bytes.length - 44) {
      throw const FormatException(
        'Use canonical mono PCM16 WAV with a 44-byte header, consistent sizes and an 8–48 kHz sample rate.',
      );
    }
    return SoundWavInfo(
      totalBytes: bytes.length,
      dataBytes: length,
      sampleRate: rate,
    );
  }
}
