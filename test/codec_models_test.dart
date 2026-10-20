import 'package:bdk_audio/features/codec/codec_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> config({
  int type = 4,
  int rate = 8,
  int bits = 2,
  int channels = 2,
}) => {
  'codecType': type,
  'codecName': type == 4 ? 'LDAC' : 'AAC',
  'sampleRateMask': rate,
  'bitsMask': bits,
  'channelMask': channels,
  'cs1': 1003,
  'cs2': -7,
  'cs3': 123,
  'cs4': 456,
};

Map<String, Object?> snapshotMap() => {
  'state': 'ready',
  'devices': [
    {'id': 'AA', 'name': 'BDK SPEAKER', 'associated': true},
  ],
  'selectedDeviceId': 'AA',
  'active': config(),
  'capabilities': [config(rate: 9, bits: 3, channels: 3)],
  'canApply': true,
  'source': 'direct',
  'observedAtMs': 10000,
  'reason': 'Read back after applying.',
};

void main() {
  test(
    'LDAC codes describe quality and cadence-based nominal targets only',
    () {
      for (final quality in LdacQuality.values) {
        final raw = {...config(), 'cs1': quality.wireValue};
        final value = CodecConfiguration.fromMap(raw);
        expect(value.ldacQuality, quality);
        expect(
          CodecConfiguration.fromMap({...raw, 'codecType': 11}).ldacQuality,
          isNull,
        );
      }
      for (final raw in [0, 3, 999, 1004, 2000, -1]) {
        expect(
          CodecConfiguration.fromMap({...config(), 'cs1': raw}).ldacQuality,
          isNull,
        );
      }
      for (final rate in [1, 4]) {
        expect(
          CodecConfiguration.fromMap({
            ...config(rate: rate),
            'cs1': 1000,
          }).ldacNominalTargetKbps,
          909,
        );
        expect(
          CodecConfiguration.fromMap({
            ...config(rate: rate),
            'cs1': 1001,
          }).ldacNominalTargetKbps,
          606,
        );
        expect(
          CodecConfiguration.fromMap({
            ...config(rate: rate),
            'cs1': 1002,
          }).ldacNominalTargetKbps,
          303,
        );
      }
      for (final rate in [2, 8]) {
        expect(
          CodecConfiguration.fromMap({
            ...config(rate: rate),
            'cs1': 1000,
          }).ldacNominalTargetKbps,
          990,
        );
        expect(
          CodecConfiguration.fromMap({
            ...config(rate: rate),
            'cs1': 1001,
          }).ldacNominalTargetKbps,
          660,
        );
        expect(
          CodecConfiguration.fromMap({
            ...config(rate: rate),
            'cs1': 1002,
          }).ldacNominalTargetKbps,
          330,
        );
      }
      expect(
        CodecConfiguration.fromMap(config()).ldacNominalTargetKbps,
        isNull,
      );
      expect(
        CodecConfiguration.fromMap({
          ...config(rate: 16),
          'cs1': 1000,
        }).ldacNominalTargetKbps,
        isNull,
      );
    },
  );

  test(
    'quality capabilities require recognized active LDAC and one supported row',
    () {
      final snapshot = CodecSnapshot.fromMap(snapshotMap());
      const quality = CodecPreference(
        codecType: 4,
        sampleRateMask: 8,
        bitsMask: 2,
        channelMask: 2,
        ldacQuality: LdacQuality.high,
      );
      expect(snapshot.supports(quality), isTrue);
      final desired = snapshot.configurationFor(quality);
      expect(
        [desired.cs1, desired.cs2, desired.cs3, desired.cs4],
        [1000, -7, 123, 456],
      );
      expect(
        quality.matches(CodecConfiguration.fromMap({...config(), 'cs1': 1003})),
        isFalse,
      );
      expect(
        quality.matches(CodecConfiguration.fromMap({...config(), 'cs1': 1000})),
        isTrue,
      );
      for (final active in [
        {...config(), 'cs1': 1009},
        {...config(), 'codecType': 11},
        {...config(), 'sampleRateMask': 3},
      ]) {
        final unavailable = CodecSnapshot.fromMap({
          ...snapshotMap(),
          'active': active,
        });
        expect(unavailable.supports(quality), isFalse);
        expect(
          () => unavailable.configurationFor(quality),
          throwsArgumentError,
        );
      }
      final missing = CodecSnapshot.fromMap({
        ...snapshotMap(),
        'capabilities': [],
      });
      expect(missing.supports(quality), isFalse);
    },
  );
  test(
    'default LDAC permits explicit quality without fabricating the current target',
    () {
      final snapshot = CodecSnapshot.fromMap({
        ...snapshotMap(),
        'active': {...config(), 'cs1': 0},
      });
      expect(snapshot.active!.ldacQuality, isNull);
      expect(snapshot.active!.ldacNominalTargetKbps, isNull);
      expect(snapshot.ldacQualities, LdacQuality.values);
      const preferred = CodecPreference(
        codecType: 4,
        sampleRateMask: 8,
        bitsMask: 2,
        channelMask: 2,
        ldacQuality: LdacQuality.high,
      );
      expect(snapshot.supports(preferred), isTrue);
      final desired = snapshot.configurationFor(preferred);
      expect(
        [desired.cs1, desired.cs2, desired.cs3, desired.cs4],
        [1000, -7, 123, 456],
      );
      expect(preferred.matches(snapshot.active!), isFalse);
    },
  );
  test(
    'zero quality on a non-LDAC connection cannot authorize LDAC bitrate choices',
    () {
      const desired = CodecPreference(
        codecType: 4,
        sampleRateMask: 8,
        bitsMask: 2,
        channelMask: 2,
        ldacQuality: LdacQuality.high,
      );
      for (final type in [0, 1, 11]) {
        final active = {
          ...config(type: type, rate: 2, bits: 1),
          'codecName': 'Codec $type',
          'cs1': 0,
        };
        final snapshot = CodecSnapshot.fromMap({
          ...snapshotMap(),
          'active': active,
          'capabilities': [active, config(rate: 10, bits: 3)],
        });
        expect(
          snapshot.ldacQualities,
          isEmpty,
          reason: 'Active codec $type is not LDAC',
        );
        expect(snapshot.supports(desired), isFalse);
        expect(() => snapshot.configurationFor(desired), throwsArgumentError);
      }
    },
  );
  test(
    'Android masks decode reported choices without inventing unknown rates',
    () {
      final value = CodecConfiguration.fromMap(
        config(rate: 0x4b, bits: 7, channels: 3),
      );
      expect(value.sampleRates, [1, 2, 8]);
      expect(value.bitDepths, [1, 2, 4]);
      expect(value.channelModes, [1, 2]);
      expect(CodecConfiguration.sampleRateLabel(4), '88.2 kHz');
      expect(CodecConfiguration.sampleRateLabel(3), 'Not reported');
      expect(CodecConfiguration.bitDepthLabel(4), '32-bit');
      expect(CodecConfiguration.channelLabel(3), 'Not reported');
    },
  );

  test(
    'configuration rejects missing, fractional and negative mask fields',
    () {
      for (final bad in [
        {...config()}..remove('cs4'),
        {...config(), 'sampleRateMask': 1.5},
        {...config(), 'bitsMask': -1},
        {...config(), 'codecType': 1000000},
        {...config(), 'codecName': ''},
      ]) {
        expect(() => CodecConfiguration.fromMap(bad), throwsFormatException);
      }
    },
  );

  test('configuration preserves signed opaque codec-specific fields', () {
    final value = CodecConfiguration.fromMap(config());
    expect(value.cs1, 1003);
    expect(value.cs2, -7);
    expect(value.cs3, 123);
    expect(value.cs4, 456);
  });

  test('capability combinations must come from the same reported row', () {
    final snapshot = CodecSnapshot.fromMap({
      ...snapshotMap(),
      'capabilities': [config(rate: 8, bits: 2), config(rate: 2, bits: 1)],
    });
    expect(
      snapshot.supports(
        const CodecPreference(
          codecType: 4,
          sampleRateMask: 8,
          bitsMask: 2,
          channelMask: 2,
        ),
      ),
      isTrue,
    );
    expect(
      snapshot.supports(
        const CodecPreference(
          codecType: 4,
          sampleRateMask: 8,
          bitsMask: 1,
          channelMask: 2,
        ),
      ),
      isFalse,
    );
    expect(
      snapshot.supports(
        const CodecPreference(
          codecType: 4,
          sampleRateMask: 3,
          bitsMask: 2,
          channelMask: 2,
        ),
      ),
      isFalse,
    );
    expect(
      snapshot.supports(
        const CodecPreference(
          codecType: 4,
          sampleRateMask: 0,
          bitsMask: 2,
          channelMask: 2,
        ),
      ),
      isFalse,
    );
  });

  test(
    'ready snapshots require current device identity, source and observation',
    () {
      for (final bad in [
        {...snapshotMap(), 'selectedDeviceId': 'BB'},
        {...snapshotMap(), 'active': null},
        {...snapshotMap(), 'source': 'none'},
        {...snapshotMap(), 'observedAtMs': 0},
        {...snapshotMap(), 'canApply': 'true'},
        {...snapshotMap(), 'state': 'madeUp'},
        {
          ...snapshotMap(),
          'devices': [
            {'id': 'AA', 'name': 'One', 'associated': true},
            {'id': 'aa', 'name': 'Two', 'associated': true},
          ],
        },
      ]) {
        expect(() => CodecSnapshot.fromMap(bad), throwsFormatException);
      }
    },
  );

  test(
    'missing capabilities remain read-only and provide no fallback rates',
    () {
      final value = CodecSnapshot.fromMap({
        ...snapshotMap(),
        'capabilities': [],
      });
      expect(value.canApply, isFalse);
      expect(value.preferences, isEmpty);
    },
  );

  test('freshness rejects old and future observations', () {
    final value = CodecSnapshot.fromMap(snapshotMap());
    expect(value.isFresh(DateTime.fromMillisecondsSinceEpoch(14999)), isTrue);
    expect(value.isFresh(DateTime.fromMillisecondsSinceEpoch(15001)), isFalse);
    expect(value.isFresh(DateTime.fromMillisecondsSinceEpoch(9999)), isFalse);
  });

  test(
    'same-codec preference preserves opaque fields while switching uses defaults',
    () {
      final value = CodecSnapshot.fromMap(snapshotMap());
      final same = value.configurationFor(
        const CodecPreference(
          codecType: 4,
          sampleRateMask: 1,
          bitsMask: 1,
          channelMask: 1,
        ),
      );
      expect(same.toMap(), {
        'codecType': 4,
        'codecName': 'LDAC',
        'sampleRateMask': 1,
        'bitsMask': 1,
        'channelMask': 1,
        'cs1': 1003,
        'cs2': -7,
        'cs3': 123,
        'cs4': 456,
      });
      final switched = value.configurationFor(
        const CodecPreference(
          codecType: 1,
          sampleRateMask: 2,
          bitsMask: 1,
          channelMask: 2,
        ),
      );
      expect(
        [switched.cs1, switched.cs2, switched.cs3, switched.cs4],
        [0, 0, 0, 0],
      );
    },
  );

  test(
    'preference confirmation compares negotiated fields rather than codec labels',
    () {
      const preference = CodecPreference(
        codecType: 4,
        sampleRateMask: 8,
        bitsMask: 2,
        channelMask: 2,
      );
      expect(
        preference.matches(
          CodecConfiguration.fromMap({...config(), 'codecName': 'Vendor LDAC'}),
        ),
        isTrue,
      );
      expect(
        preference.matches(CodecConfiguration.fromMap(config(rate: 2))),
        isFalse,
      );
    },
  );
}
