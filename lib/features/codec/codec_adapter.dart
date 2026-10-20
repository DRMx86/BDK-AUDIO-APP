import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'codec_models.dart';

abstract interface class CodecAdapter {
  Future<CodecSnapshot> snapshot({String? deviceId});
  Future<bool> apply({
    required String deviceId,
    required CodecConfiguration configuration,
  });
  Future<void> requestPermission();
  Future<void> associate(String deviceId);
  Future<void> openBluetoothSettings();
  void dispose();
}

class CodecAdapterException implements Exception {
  const CodecAdapterException(this.code, this.message, {this.details});
  final String code, message;
  final String? details;
  @override
  String toString() => message;
}

/// Uses only the normal app bridge. Association never implies API access.
class SystemCodecAdapter implements CodecAdapter {
  SystemCodecAdapter({TargetPlatform? platform, MethodChannel? channel})
    : _platform = platform ?? defaultTargetPlatform,
      _channel = channel ?? const MethodChannel('bdk_audio/codec');
  final TargetPlatform _platform;
  final MethodChannel _channel;
  bool _closed = false;
  bool get _android => !kIsWeb && _platform == TargetPlatform.android;
  void _check() {
    if (_closed) throw StateError('Codec adapter is closed.');
  }

  Future<Object?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    _check();
    if (!_android) {
      throw const CodecAdapterException(
        'unsupportedPlatform',
        'Audio quality is managed by your device.',
      );
    }
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw CodecAdapterException(error.code, switch (error.code) {
        'permissionRequired' => 'Allow Bluetooth access to read audio quality.',
        'associationUnavailable' || 'associationFailed' =>
          'Companion access was unavailable or cancelled. You can try again.',
        'codecTimeout' || 'consentTimeout' =>
          'Android did not respond in time. Refresh before retrying.',
        'invalidCodecRequest' =>
          'This preference is not supported by the current connection.',
        'codecBusy' =>
          'Another Bluetooth request is still pending. Wait and refresh.',
        _ =>
          'Android did not expose audio quality access. Use Bluetooth settings or refresh.',
      }, details: error.message);
    } on MissingPluginException {
      throw const CodecAdapterException(
        'apiUnavailable',
        'Audio quality access is unavailable in this app build.',
      );
    }
  }

  @override
  Future<CodecSnapshot> snapshot({String? deviceId}) async {
    _check();
    if (!_android) {
      return CodecSnapshot(
        access: CodecAccess.unsupportedPlatform,
        reason:
            'Audio quality is managed by this platform. Manual app codec selection is unavailable.',
      );
    }
    final value = await _invoke('snapshot', {'deviceId': deviceId});
    try {
      return CodecSnapshot.fromMap(value);
    } on FormatException catch (error) {
      throw CodecAdapterException(
        'invalidSnapshot',
        'Current audio quality could not be read.',
        details: error.message,
      );
    }
  }

  @override
  Future<bool> apply({
    required String deviceId,
    required CodecConfiguration configuration,
  }) async {
    final payload = configuration.toMap()..remove('codecName');
    final value = await _invoke('apply', {'deviceId': deviceId, ...payload});
    if (value is! Map || value['submitted'] is! bool) {
      throw const CodecAdapterException(
        'invalidAcknowledgment',
        'Android did not acknowledge this preference. Refresh the current connection.',
      );
    }
    return value['submitted']
        as bool; // Submission is never negotiated confirmation.
  }

  @override
  Future<void> requestPermission() async {
    await _invoke('requestPermission');
  }

  @override
  Future<void> associate(String deviceId) async {
    await _invoke('associate', {'deviceId': deviceId});
  }

  @override
  Future<void> openBluetoothSettings() async {
    await _invoke('openBluetoothSettings');
  }

  @override
  void dispose() {
    _closed = true;
  }
}
