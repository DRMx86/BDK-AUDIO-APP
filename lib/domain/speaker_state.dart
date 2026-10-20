import 'dart:typed_data';

enum ConnectionPhase {
  disconnected,
  scanning,
  connecting,
  synchronizing,
  ready,
  error,
}

/// Firmware wire levels. Actual filter gains scale by .5/.7/.7.
class EqGains {
  factory EqGains(int bass, int mid, int treble) {
    for (final value in [bass, mid, treble]) {
      RangeError.checkValueInInterval(value, -12, 12, 'EQ level');
    }
    return EqGains._(bass, mid, treble);
  }
  const EqGains.zero() : bass = 0, mid = 0, treble = 0;
  const EqGains._(this.bass, this.mid, this.treble);
  final int bass, mid, treble;
  List<int> get values => [bass, mid, treble];
  List<double> get appliedDb => [bass * .5, mid * .7, treble * .7];
  @override
  bool operator ==(Object other) =>
      other is EqGains &&
      bass == other.bass &&
      mid == other.mid &&
      treble == other.treble;
  @override
  int get hashCode => Object.hash(bass, mid, treble);
}

class LedSettings {
  static const offEffect = 255;
  const LedSettings({
    this.effect = 0,
    this.brightness = 70,
    this.speed = 50,
    this.color1 = 0x74d9ff,
    this.color2 = 0xbc9aff,
    this.gradient = 1,
  });
  final int effect, brightness, speed, color1, color2, gradient;
  bool get isOff => effect == offEffect;
  bool get lightsOn => !isOff && brightness > 0;
  LedSettings copyWith({
    int? effect,
    int? brightness,
    int? speed,
    int? color1,
    int? color2,
    int? gradient,
  }) => LedSettings(
    effect: effect ?? this.effect,
    brightness: brightness ?? this.brightness,
    speed: speed ?? this.speed,
    color1: color1 ?? this.color1,
    color2: color2 ?? this.color2,
    gradient: gradient ?? this.gradient,
  );
  Uint8List toPayload() {
    if (!isOff) RangeError.checkValueInInterval(effect, 0, 21, 'effect');
    RangeError.checkValueInInterval(brightness, 0, 100, 'brightness');
    RangeError.checkValueInInterval(speed, 0, 100, 'speed');
    RangeError.checkValueInInterval(gradient, 0, 4, 'gradient');
    for (final color in [color1, color2]) {
      RangeError.checkValueInInterval(color, 0, 0xffffff, 'color');
    }
    return Uint8List.fromList([
      effect,
      brightness,
      speed,
      color1 >> 16,
      (color1 >> 8) & 255,
      color1 & 255,
      color2 >> 16,
      (color2 >> 8) & 255,
      color2 & 255,
      gradient,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is LedSettings &&
      effect == other.effect &&
      brightness == other.brightness &&
      speed == other.speed &&
      color1 == other.color1 &&
      color2 == other.color2 &&
      gradient == other.gradient;
  @override
  int get hashCode =>
      Object.hash(effect, brightness, speed, color1, color2, gradient);
}

class MeterLevels {
  const MeterLevels(this.hz30, this.hz60, this.hz100, this.receivedAt);
  final int hz30, hz60, hz100;
  final DateTime receivedAt;
  List<int> get values => [hz30, hz60, hz100];
  List<double> get db => values.map((v) => v * .6 - 60).toList();
  bool isFresh(DateTime now) {
    final age = now.difference(receivedAt);
    return !age.isNegative && age.inMilliseconds < 500;
  }
}

class SpeakerState {
  const SpeakerState({
    this.phase = ConnectionPhase.disconnected,
    this.deviceId,
    this.name = 'BDK speaker',
    this.firmware = '',
    this.eq = const EqGains.zero(),
    this.controlFlags = 4,
    this.led = const LedSettings(),
    this.soundFlags = 0,
    this.meter,
    this.message,
    this.writeCapacity = 20,
  });
  final ConnectionPhase phase;
  final String? deviceId, message;
  final String name, firmware;
  final EqGains eq;
  final int controlFlags, soundFlags, writeCapacity;
  final LedSettings led;
  final MeterLevels? meter;
  bool get connected => phase == ConnectionPhase.ready;
  bool get bassBoost => (controlFlags & 1) != 0;
  bool get outputSwap => (controlFlags & 2) != 0;
  bool get fullRange => (controlFlags & 4) != 0;
  SpeakerState copyWith({
    ConnectionPhase? phase,
    String? deviceId,
    String? name,
    String? firmware,
    EqGains? eq,
    int? controlFlags,
    LedSettings? led,
    int? soundFlags,
    MeterLevels? meter,
    String? message,
    int? writeCapacity,
    bool clearMeter = false,
    bool clearMessage = false,
  }) => SpeakerState(
    phase: phase ?? this.phase,
    deviceId: deviceId ?? this.deviceId,
    name: name ?? this.name,
    firmware: firmware ?? this.firmware,
    eq: eq ?? this.eq,
    controlFlags: controlFlags ?? this.controlFlags,
    led: led ?? this.led,
    soundFlags: soundFlags ?? this.soundFlags,
    meter: clearMeter ? null : meter ?? this.meter,
    message: clearMessage ? null : message ?? this.message,
    writeCapacity: writeCapacity ?? this.writeCapacity,
  );
}
