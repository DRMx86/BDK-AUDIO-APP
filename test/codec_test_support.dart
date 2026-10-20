import 'package:bdk_audio/features/codec/codec_adapter.dart';
import 'package:bdk_audio/features/codec/codec_models.dart';

/// Exact normal-app Redmagic probe shape, with optional negative-case fields.
CodecSnapshot lhdcV5Fixture({
  String id = 'AA',
  int stamp = 100000,
  int rate = 32,
  int type = 15,
  String name = 'LHDC V5',
  int cs1 = 0x8008,
  int cs2 = 0,
  int cs3 = 0x5c000000,
  int cs4 = 0,
  List<CodecConfiguration>? capabilities,
}) => CodecSnapshot(
  access: CodecAccess.ready,
  devices: [CodecAudioDevice(id: id, name: 'BDK SPEAKER', associated: true)],
  selectedDeviceId: id,
  active: CodecConfiguration(
    codecType: type,
    codecName: name,
    sampleRateMask: rate,
    bitsMask: 2,
    channelMask: 2,
    cs1: cs1,
    cs2: cs2,
    cs3: cs3,
    cs4: cs4,
  ),
  canApply: true,
  source: 'direct',
  observedAtMs: stamp,
  capabilities:
      capabilities ??
      [
        CodecConfiguration(
          codecType: type,
          codecName: name,
          sampleRateMask: 43,
          bitsMask: 3,
          channelMask: 2,
        ),
      ],
);

CodecSnapshot codecFixture({
  String id = 'AA',
  int rate = 2,
  int qualityCode = 1003,
  int? stamp,
  bool writable = true,
  List<CodecConfiguration>? capabilities,
}) => CodecSnapshot(
  access: CodecAccess.ready,
  devices: [CodecAudioDevice(id: id, name: 'BDK SPEAKER', associated: true)],
  selectedDeviceId: id,
  active: CodecConfiguration(
    codecType: 4,
    codecName: 'LDAC',
    sampleRateMask: rate,
    bitsMask: 2,
    channelMask: 2,
    cs1: qualityCode,
    cs2: -7,
  ),
  canApply: writable,
  source: 'direct',
  observedAtMs: stamp ?? DateTime.now().millisecondsSinceEpoch,
  capabilities:
      capabilities ??
      const [
        CodecConfiguration(
          codecType: 4,
          codecName: 'LDAC',
          sampleRateMask: 10,
          bitsMask: 3,
          channelMask: 2,
        ),
        CodecConfiguration(
          codecType: 1,
          codecName: 'AAC',
          sampleRateMask: 2,
          bitsMask: 1,
          channelMask: 2,
        ),
      ],
);

class FakeCodecAdapter implements CodecAdapter {
  Future<CodecSnapshot> Function(String?)? onSnapshot;
  Future<bool> Function(String, CodecConfiguration)? onApply;
  Future<void> Function()? onConsent;
  final events = <String>[];
  final writes = <CodecConfiguration>[];
  int activeCalls = 0, maxActiveCalls = 0, disposed = 0;
  Future<T> _observe<T>(Future<T> Function() body) async {
    activeCalls++;
    if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
    try {
      return await body();
    } finally {
      activeCalls--;
    }
  }

  @override
  Future<CodecSnapshot> snapshot({String? deviceId}) => _observe(() async {
    events.add('snapshot:${deviceId ?? "auto"}');
    return onSnapshot == null
        ? codecFixture(id: deviceId ?? 'AA')
        : await onSnapshot!(deviceId);
  });
  @override
  Future<bool> apply({
    required String deviceId,
    required CodecConfiguration configuration,
  }) => _observe(() async {
    events.add('apply:$deviceId');
    writes.add(configuration);
    return onApply == null ? true : await onApply!(deviceId, configuration);
  });
  @override
  Future<void> requestPermission() async {
    events.add('permission');
    await onConsent?.call();
  }

  @override
  Future<void> associate(String deviceId) async {
    events.add('associate:$deviceId');
    await onConsent?.call();
  }

  @override
  Future<void> openBluetoothSettings() async {
    events.add('settings');
  }

  @override
  void dispose() {
    disposed++;
  }
}
