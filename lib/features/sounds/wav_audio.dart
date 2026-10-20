import 'dart:typed_data';

/// PCM16 WAV boundary. Imported compressed/float files use the native decoder;
/// upload files are canonical mono PCM16 with an explicit, bounded RIFF size.
class Pcm16Wave {
  Pcm16Wave._(this.sampleRate, this.channels, Int16List samples)
    : samples = samples.asUnmodifiableView();
  final int sampleRate, channels;
  final Int16List samples;
  int get frames => samples.length ~/ channels;
  Duration get duration =>
      Duration(microseconds: frames * 1000000 ~/ sampleRate);

  static Pcm16Wave decode(
    Uint8List bytes, {
    int maximumBytes = 64 * 1024 * 1024,
  }) {
    if (bytes.length < 12 || bytes.length > maximumBytes) {
      throw const FormatException('WAV file is empty, truncated or too large.');
    }
    bool tag(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        if (bytes[offset + i] != value.codeUnitAt(i)) return false;
      }
      return true;
    }

    final view = ByteData.sublistView(bytes);
    if (!tag(0, 'RIFF') ||
        !tag(8, 'WAVE') ||
        view.getUint32(4, Endian.little) + 8 != bytes.length) {
      throw const FormatException('Invalid or truncated WAV RIFF boundary.');
    }
    int? formatOffset, formatLength, dataOffset, dataLength;
    var offset = 12, chunks = 0;
    while (offset < bytes.length) {
      if (++chunks > 1024 || bytes.length - offset < 8) {
        throw const FormatException('Invalid WAV chunk boundary.');
      }
      final length = view.getUint32(offset + 4, Endian.little);
      final begin = offset + 8, end = begin + length;
      final paddedEnd = end + (length & 1);
      if (end > bytes.length || paddedEnd > bytes.length) {
        throw const FormatException('Truncated WAV chunk.');
      }
      if (tag(offset, 'fmt ')) {
        if (formatOffset != null || length < 16) {
          throw const FormatException('Ambiguous or truncated WAV format.');
        }
        formatOffset = begin;
        formatLength = length;
      } else if (tag(offset, 'data')) {
        if (dataOffset != null) {
          throw const FormatException(
            'Multiple WAV data chunks are unsupported.',
          );
        }
        dataOffset = begin;
        dataLength = length;
      }
      offset = paddedEnd;
    }
    if (formatOffset == null || dataOffset == null || dataLength == null) {
      throw const FormatException('WAV needs format and audio data chunks.');
    }
    final format = formatOffset;
    final encoding = view.getUint16(format, Endian.little);
    final channels = view.getUint16(format + 2, Endian.little);
    final rate = view.getUint32(format + 4, Endian.little);
    final byteRate = view.getUint32(format + 8, Endian.little);
    final alignment = view.getUint16(format + 12, Endian.little);
    final bits = view.getUint16(format + 14, Endian.little);
    if (encoding != 1 || bits != 16) {
      throw const FormatException('Expected PCM16 WAV audio.');
    }
    if (channels < 1 ||
        channels > 8 ||
        rate < 1 ||
        rate > 384000 ||
        alignment != channels * 2 ||
        byteRate != rate * alignment ||
        dataLength == 0 ||
        dataLength % alignment != 0 ||
        (formatLength! > 16 && formatLength < 18)) {
      throw const FormatException('Invalid WAV PCM dimensions.');
    }
    final samples = Int16List(dataLength ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = view.getInt16(dataOffset + i * 2, Endian.little);
    }
    return Pcm16Wave._(rate, channels, samples);
  }

  static Uint8List encodeMono(Int16List samples, int sampleRate) {
    if (samples.isEmpty ||
        samples.length > SoundClipPolicy.maximumFrames ||
        !SoundClipPolicy.rates.contains(sampleRate)) {
      throw ArgumentError('Use a nonempty bounded notification clip.');
    }
    final bytes = Uint8List(44 + samples.length * 2);
    void tag(int at, String text) =>
        bytes.setRange(at, at + text.length, text.codeUnits);
    final view = ByteData.sublistView(bytes);
    tag(0, 'RIFF');
    view.setUint32(4, bytes.length - 8, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    view.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      view.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bytes;
  }
}

class SoundClipPlan {
  const SoundClipPlan._(this.total, this.start, this.end, this.outputRate);
  final Duration total, start, end;
  final int? outputRate;
  Duration get duration => end - start;
  bool get requiresTrim => outputRate == null;
  bool get isExcerpt => start != Duration.zero || end != total;
  bool get lowerRate =>
      outputRate != null && outputRate != SoundClipPolicy.rates.first;
  int? get frameCount => outputRate == null
      ? null
      : duration.inMicroseconds * outputRate! ~/ 1000000;
  int? get startFrame =>
      outputRate == null ? null : start.inMicroseconds * outputRate! ~/ 1000000;
  int? get outputBytes => frameCount == null ? null : 44 + frameCount! * 2;
}

abstract final class SoundClipPolicy {
  static const maximumBytes = 200 * 1024;
  static const maximumFrames = (maximumBytes - 44) ~/ 2;
  static const rates = [22050, 16000, 11025, 8000];
  static const maximumDuration = Duration(microseconds: maximumFrames * 125);
  static SoundClipPlan plan({
    required Duration total,
    Duration start = Duration.zero,
    Duration? end,
  }) {
    final finish = end ?? total;
    if (total <= Duration.zero ||
        start < Duration.zero ||
        finish <= start ||
        finish > total) {
      throw ArgumentError('Choose a nonempty clip within the original audio.');
    }
    for (final rate in rates) {
      final frames = (finish - start).inMicroseconds * rate ~/ 1000000;
      if (frames >= 1 && frames <= maximumFrames) {
        return SoundClipPlan._(total, start, finish, rate);
      }
    }
    return SoundClipPlan._(total, start, finish, null);
  }
}
