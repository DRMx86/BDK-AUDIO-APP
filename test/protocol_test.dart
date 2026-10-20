import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bdk_audio/domain/speaker_state.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';

Uint8List hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

void main() {
  test('signed EQ wire bytes and actual DSP gains are distinct', () {
    final eq = EqGains(6, -2, 4);
    expect(SpeakerProtocol.setEq(eq), hex('0106FE04'));
    expect(eq.appliedDb, [3, -1.4, 2.8]);
    expect(() => EqGains(13, 0, 0), throwsRangeError);
  });
  test('flags preserve the firmware masks', () {
    const state = SpeakerState(controlFlags: 3);
    expect(state.bassBoost, isTrue);
    expect(state.outputSwap, isTrue);
    expect(state.fullRange, isFalse);
    expect(const SpeakerState(controlFlags: 4).fullRange, isTrue);
  });
  test('unified LED payload and off restore preserve colors/effect', () {
    const led = LedSettings(
      effect: 21,
      brightness: 70,
      speed: 50,
      color1: 0xff8000,
      color2: 0x0080ff,
      gradient: 3,
    );
    expect(SpeakerProtocol.setLed(led), hex('05154632FF80000080FF03'));
    expect(led.copyWith(brightness: 0).copyWith(brightness: 70), led);
  });
  test('legacy Off ID255 is tolerated in both incoming status forms', () {
    const off = LedSettings(effect: 255);
    final partial = SpeakerProtocol.parse(hex('05FF463274D9FFBC9AFF01'));
    final full = SpeakerProtocol.parse(
      hex('F000000004FF463274D9FFBC9AFF01000342444B027631'),
    );
    expect(partial.led, off);
    expect(full.apply(const SpeakerState()).led, off);
    expect(full.name, 'BDK');
    expect(full.firmware, 'v1');
  });
  test(
    'outgoing Off uses zero brightness and never sends legacy effect255',
    () {
      expect(
        SpeakerProtocol.setLed(const LedSettings(effect: 21, brightness: 0)),
        hex('0515003274D9FFBC9AFF01'),
      );
      expect(
        () => SpeakerProtocol.setLed(const LedSettings(effect: 255)),
        throwsArgumentError,
      );
    },
  );
  test(
    'Off support does not admit unassigned effect IDs or invalid brightness',
    () {
      for (final effect in [-1, 22, 254, 256]) {
        expect(() => LedSettings(effect: effect).toPayload(), throwsRangeError);
      }
      expect(
        () => SpeakerProtocol.parse(hex('0516463274D9FFBC9AFF01')),
        throwsFormatException,
      );
      expect(
        () => SpeakerProtocol.parse(hex('05FF653274D9FFBC9AFF01')),
        throwsFormatException,
      );
    },
  );
  test(
    'rename is UTF8 bounded and explicitly terminated for legacy firmware',
    () {
      expect(SpeakerProtocol.rename('BDK'), hex('0442444B00'));
      expect(() => SpeakerProtocol.rename('🙂' * 8), throwsArgumentError);
      expect(() => SpeakerProtocol.rename('a\u0000b'), throwsArgumentError);
      expect(() => SpeakerProtocol.rename('  '), throwsArgumentError);
    },
  );
  final vectors =
      (jsonDecode(
                File('docs/migration/protocol-vectors.json').readAsStringSync(),
              )
              as Map)['vectors']
          as List;
  for (final raw in vectors) {
    final v = raw as Map<String, dynamic>;
    test('source vector ${v['name']}', () {
      final packet = hex(v['hex'] as String);
      expect(packet.length, v['length']);
      if (v['channel'] == 'cmd') return;
      final expected = v['expected'] as Map<String, dynamic>;
      if (v['channel'] == 'meter') {
        if (expected['reject'] == true) {
          expect(
            () => SpeakerProtocol.meter(packet, DateTime(2026)),
            throwsFormatException,
          );
          return;
        }
        final result = SpeakerProtocol.meter(packet, DateTime(2026));
        expect(result.values, expected['levels']);
        expect(result.db, expected['approxDb']);
        return;
      }
      if (expected['reject'] == true) {
        expect(() => SpeakerProtocol.parse(packet), throwsFormatException);
        return;
      }
      final event = SpeakerProtocol.parse(packet);
      expect(event.id, packet[0]);
      if (expected.containsKey('bass')) {
        expect(
          event.eq,
          EqGains(expected['bass'], expected['mid'], expected['treble']),
        );
      }
      if (expected.containsKey('name')) expect(event.name, expected['name']);
      if (expected.containsKey('firmware')) {
        expect(event.firmware, expected['firmware']);
      }
      if (expected.containsKey('brightness')) {
        expect(event.led!.brightness, expected['brightness']);
      }
      if (expected.containsKey('commandId')) {
        expect(event.commandId, expected['commandId']);
      }
      if (expected.containsKey('error')) expect(event.error, expected['error']);
      if (expected.containsKey('sound')) {
        expect(event.soundFlags, expected['sound']);
      }
    });
  }
  test('full status rejects every truncation and bad UTF8/levels', () {
    final full = hex('F006FE0403154632FF80000080FF03050342444B05312E302E33');
    for (var i = 0; i < full.length; i++) {
      expect(
        () => SpeakerProtocol.parse(full.sublist(0, i)),
        throwsFormatException,
      );
    }
    expect(() => SpeakerProtocol.parse(hex('03FF')), throwsFormatException);
    expect(
      () => SpeakerProtocol.meter(hex('0065FF'), DateTime(2026)),
      throwsFormatException,
    );
  });
  test('meter becomes stale and never invents a replacement', () {
    final now = DateTime(2026);
    final meter = MeterLevels(0, 50, 100, now);
    expect(meter.isFresh(now.add(const Duration(milliseconds: 499))), isTrue);
    expect(meter.isFresh(now.add(const Duration(seconds: 1))), isFalse);
  });
}
