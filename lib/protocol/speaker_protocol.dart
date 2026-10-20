import 'dart:convert';
import 'dart:typed_data';
import '../domain/speaker_state.dart';

class ProtocolEvent {
  const ProtocolEvent(
    this.id, {
    this.eq,
    this.controlFlags,
    this.led,
    this.name,
    this.firmware,
    this.soundFlags,
    this.commandId,
    this.error,
    this.progress,
  });
  final int id;
  final EqGains? eq;
  final int? controlFlags, soundFlags, commandId, error, progress;
  final LedSettings? led;
  final String? name, firmware;
  bool get fullStatus => id == 0xf0;
  SpeakerState apply(SpeakerState current) => current.copyWith(
    eq: eq,
    controlFlags: controlFlags,
    led: led,
    name: name,
    firmware: firmware,
    soundFlags: soundFlags,
  );
}

abstract final class SpeakerProtocol {
  static const service = '12345678-1234-1234-1234-123456789000';
  static const command = '12345678-1234-1234-1234-123456789001';
  static const status = '12345678-1234-1234-1234-123456789002';
  static const meterCharacteristic = '12345678-1234-1234-1234-123456789003';
  static Uint8List setEq(EqGains value) =>
      Uint8List.fromList([1, ...value.values.map((v) => v & 255)]);
  static Uint8List setControl(int flags) {
    RangeError.checkValueInInterval(flags, 0, 255);
    return Uint8List.fromList([3, flags]);
  }

  static Uint8List setLed(LedSettings led) {
    // Tolerate legacy app status sentinels on input, but this project's wire
    // contract requires Off as brightness zero with a valid user effect.
    if (led.isOff) {
      throw ArgumentError('Turn lights off with zero brightness.');
    }
    return Uint8List.fromList([5, ...led.toPayload()]);
  }

  static Uint8List setLedBrightness(int brightness) {
    RangeError.checkValueInInterval(brightness, 0, 100, 'brightness');
    return Uint8List.fromList([7, brightness]);
  }

  static Uint8List requestStatus() => Uint8List.fromList([0xf0]);
  static Uint8List rename(String raw) {
    final value = raw.trim(), bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > 31 || value.contains('\u0000')) {
      throw ArgumentError('Use 1–31 UTF-8 bytes without a null character.');
    }
    return Uint8List.fromList([4, ...bytes, 0]);
  }

  static int _signed(int v) => v >= 128 ? v - 256 : v;
  static EqGains _eq(List<int> p, int o) {
    try {
      return EqGains(_signed(p[o]), _signed(p[o + 1]), _signed(p[o + 2]));
    } on RangeError {
      throw const FormatException('Invalid EQ levels');
    }
  }

  static LedSettings _led(List<int> p, int o) {
    final led = LedSettings(
      effect: p[o],
      brightness: p[o + 1],
      speed: p[o + 2],
      color1: (p[o + 3] << 16) | (p[o + 4] << 8) | p[o + 5],
      color2: (p[o + 6] << 16) | (p[o + 7] << 8) | p[o + 8],
      gradient: p[o + 9],
    );
    try {
      led.toPayload();
    } on RangeError {
      throw const FormatException('Invalid LED settings');
    }
    return led;
  }

  static String _text(List<int> bytes) => utf8
      .decode(bytes, allowMalformed: false)
      .replaceFirst(RegExp(r'\x00$'), '');
  static ProtocolEvent parse(List<int> p) {
    if (p.isEmpty || p.any((v) => v < 0 || v > 255)) {
      throw const FormatException('Invalid notification');
    }
    final id = p[0];
    void length(int n) {
      if (p.length != n) {
        throw FormatException('Invalid notification $id length');
      }
    }

    switch (id) {
      case 1:
        length(4);
        return ProtocolEvent(id, eq: _eq(p, 1));
      case 2:
        length(2);
        return ProtocolEvent(id, controlFlags: p[1]);
      case 3:
        if (p.length > 33) throw const FormatException('Invalid name length');
        return ProtocolEvent(id, name: _text(p.sublist(1)));
      case 4:
        if (p.length > 65) {
          throw const FormatException('Invalid version length');
        }
        return ProtocolEvent(id, firmware: _text(p.sublist(1)));
      case 5:
        length(11);
        return ProtocolEvent(id, led: _led(p, 1));
      case 6:
        length(2);
        return ProtocolEvent(id, soundFlags: p[1]);
      case 0x10:
        length(2);
        return ProtocolEvent(id, commandId: p[1]);
      case 0x11:
        length(3);
        return ProtocolEvent(id, commandId: p[1], error: p[2]);
      case 0x20:
      case 0x30:
        length(2);
        if (p[1] > 100) throw const FormatException('Invalid progress');
        return ProtocolEvent(id, progress: p[1]);
      case 0x21:
      case 0x22:
      case 0x31:
      case 0x32:
      case 0xff:
        length(1);
        return ProtocolEvent(id);
      case 0x23:
      case 0x33:
        length(2);
        return ProtocolEvent(id, error: p[1]);
      case 0xf0:
        if (p.length < 18) throw const FormatException('Truncated full status');
        final n = p[16], fwIndex = 17 + n;
        if (n > 31 || fwIndex >= p.length) {
          throw const FormatException('Truncated name');
        }
        final f = p[fwIndex];
        if (f > 64 || p.length != fwIndex + 1 + f) {
          throw const FormatException('Truncated firmware version');
        }
        return ProtocolEvent(
          id,
          eq: _eq(p, 1),
          controlFlags: p[4],
          led: _led(p, 5),
          soundFlags: p[15],
          name: _text(p.sublist(17, fwIndex)),
          firmware: _text(p.sublist(fwIndex + 1)),
        );
      default:
        throw FormatException('Unknown notification $id');
    }
  }

  static MeterLevels meter(List<int> packet, DateTime receivedAt) {
    if (packet.length != 3 || packet.any((v) => v < 0 || v > 100)) {
      throw const FormatException('Invalid meter');
    }
    return MeterLevels(packet[0], packet[1], packet[2], receivedAt);
  }
}
