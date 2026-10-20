import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioDeviceIdentity {
  const AudioDeviceIdentity({required this.id, required this.name});
  final String id, name;
}

class AudioConnectionSnapshot {
  const AudioConnectionSnapshot({
    this.devices = const [],
    this.canVerifyIdentity = true,
    this.permissionRequired = false,
    this.message,
  });
  final List<AudioDeviceIdentity> devices;
  final bool canVerifyIdentity, permissionRequired;
  final String? message;
}

abstract interface class AudioConnectionAdapter {
  Future<AudioConnectionSnapshot> snapshot();
  Future<void> requestPermission();
  Future<void> openBluetoothSettings();
}

/// Android verifies the same raw A2DP/BLE identity as the original app.
/// Windows enforces a native identity gate, including when a specific driver
/// cannot be mapped. Other platforms retain explicit OS-managed confirmation.
class SystemAudioConnectionAdapter implements AudioConnectionAdapter {
  const SystemAudioConnectionAdapter({
    this.windowsTimeout = const Duration(seconds: 4),
  });
  static const channel = MethodChannel('bdk_audio/codec');
  static const windowsChannel = MethodChannel('bdk_audio/audio_connection');
  final Duration windowsTimeout;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<AudioConnectionSnapshot> snapshot() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsSnapshot();
    }
    if (!_android) {
      return const AudioConnectionSnapshot(canVerifyIdentity: false);
    }
    final value = await channel
        .invokeMapMethod<String, dynamic>('snapshot')
        .timeout(const Duration(seconds: 12));
    if (value == null) {
      throw const AudioConnectionException(
        'Audio connection information is unavailable.',
      );
    }
    final devices = <AudioDeviceIdentity>[];
    for (final raw in (value['devices'] as List? ?? const [])) {
      if (raw is Map && raw['id'] is String && raw['name'] is String) {
        devices.add(AudioDeviceIdentity(id: raw['id'], name: raw['name']));
      }
    }
    final permission = value['state'] == 'permissionRequired';
    final message = permission
        ? 'Allow Bluetooth access to continue.'
        : value['state'] == 'bluetoothOff'
        ? 'Turn on Bluetooth to connect your speaker.'
        : value['state'] == 'initializing'
        ? 'Checking your Bluetooth audio connection…'
        : null;
    return AudioConnectionSnapshot(
      devices: List.unmodifiable(devices),
      permissionRequired: permission,
      message: message,
    );
  }

  Future<AudioConnectionSnapshot> _windowsSnapshot() async {
    try {
      final value = await windowsChannel
          .invokeMapMethod<String, dynamic>('snapshot')
          .timeout(windowsTimeout);
      if (value == null ||
          value['protocolVersion'] != 1 ||
          !const ['ready', 'unsupported'].contains(value['state']) ||
          value['canVerifyIdentity'] is! bool ||
          value['devices'] is! List ||
          (value['devices'] as List).length > 256 ||
          (value['state'] == 'ready' && value['canVerifyIdentity'] != true)) {
        throw const AudioConnectionException(
          'Windows audio identity information is unavailable or incomplete. Try again.',
        );
      }
      final devices = <String, AudioDeviceIdentity>{};
      for (final raw in value['devices'] as List) {
        if (raw is! Map || raw['id'] is! String || raw['name'] is! String) {
          throw const AudioConnectionException(
            'Windows returned an invalid audio identity. Try again.',
          );
        }
        final id = _windowsAddress(raw['id'] as String);
        final name = (raw['name'] as String).trim();
        if (id == null ||
            name.isEmpty ||
            name.length > 512 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
            value['canVerifyIdentity'] != true) {
          throw const AudioConnectionException(
            'Windows could not verify the Bluetooth audio identity. Try again.',
          );
        }
        devices.putIfAbsent(id, () => AudioDeviceIdentity(id: id, name: name));
      }
      return AudioConnectionSnapshot(
        devices: List.unmodifiable(devices.values),
        // This flag enforces the Windows native identity gate; it does not mean
        // an unsupported route was mapped. Only devices in the verified list
        // authorize discovery. Never fall back to manual confirmation here.
        canVerifyIdentity: true,
        message: value['message'] is String
            ? value['message'] as String
            : value['state'] == 'unsupported'
            ? 'This Windows audio driver does not expose a verified Bluetooth speaker identity.'
            : null,
      );
    } on AudioConnectionException {
      rethrow;
    } catch (_) {
      throw const AudioConnectionException(
        'We couldn’t verify the Windows Bluetooth audio connection. Connect your speaker for audio and try again.',
      );
    }
  }

  static String? _windowsAddress(String value) {
    final compact = RegExp(r'^[0-9a-fA-F]{12}$');
    final colon = RegExp(r'^(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$');
    if (!compact.hasMatch(value) && !colon.hasMatch(value)) return null;
    final digits = value.replaceAll(':', '').toLowerCase();
    if (digits == '000000000000' || digits == 'ffffffffffff') return null;
    return [
      for (var index = 0; index < 12; index += 2)
        digits.substring(index, index + 2),
    ].join(':');
  }

  @override
  Future<void> requestPermission() async {
    if (_android) await channel.invokeMethod<Object?>('requestPermission');
  }

  @override
  Future<void> openBluetoothSettings() async {
    if (_android) {
      await channel.invokeMethod<Object?>('openBluetoothSettings');
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['ms-settings:bluetooth']);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.Bluetooth',
      ]);
      return;
    }
    if (Platform.isLinux) {
      for (final command in const <List<String>>[
        ['blueman-manager'],
        ['gnome-control-center', 'bluetooth'],
        ['cinnamon-settings', 'bluetooth'],
        ['systemsettings', 'kcm_bluetooth'],
      ]) {
        final found = await Process.run('which', [command.first]);
        if (found.exitCode == 0) {
          await Process.start(
            command.first,
            command.skip(1).toList(),
            mode: ProcessStartMode.detached,
          );
          return;
        }
      }
    }
    throw const AudioConnectionException(
      'Open your device’s Bluetooth settings, connect the speaker for audio, then return here.',
    );
  }
}

class AudioConnectionException implements Exception {
  const AudioConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}
