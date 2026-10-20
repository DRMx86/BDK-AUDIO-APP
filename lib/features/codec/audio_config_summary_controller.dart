import 'dart:async';
import 'package:flutter/foundation.dart';
import 'codec_adapter.dart';
import 'codec_models.dart';

/// Read-only, identity-bound codec observations for the common app header.
/// A display timeout does not release an outstanding native snapshot lease.
class AudioConfigSummaryController extends ChangeNotifier {
  AudioConfigSummaryController({
    required this._adapter,
    DateTime Function()? now,
    Duration refreshInterval = const Duration(seconds: 5),
    Duration requestTimeout = const Duration(seconds: 3),
  }) : _now = now ?? DateTime.now,
       _refreshInterval = refreshInterval,
       _requestTimeout = requestTimeout {
    if (refreshInterval <= Duration.zero || requestTimeout <= Duration.zero) {
      throw ArgumentError('Audio summary deadlines must be positive.');
    }
  }
  final CodecAdapter _adapter;
  final DateTime Function() _now;
  final Duration _refreshInterval, _requestTimeout;
  CodecSnapshot? _snapshot;
  String? _deviceId;
  bool _active = false, _disposed = false, _reading = false, _failed = false;
  int _epoch = 0;
  Timer? _poll, _expiry, _deadline;

  CodecSnapshot? get snapshot => _snapshot;
  bool _same(String? left, String? right) =>
      left != null &&
      right != null &&
      left.toLowerCase() == right.toLowerCase();
  bool _matches(CodecSnapshot value) =>
      value.access == CodecAccess.ready &&
      value.active != null &&
      const ['direct', 'broadcast'].contains(value.source) &&
      _same(value.selectedDeviceId, _deviceId) &&
      value.devices.any((device) => _same(device.id, _deviceId));
  bool get hasFreshObservation =>
      !_disposed &&
      _active &&
      !_failed &&
      _snapshot != null &&
      _matches(_snapshot!) &&
      _snapshot!.isFresh(_now());

  String get text {
    final value = _snapshot;
    if (!_active || value == null) return 'Audio quality';
    if (!hasFreshObservation) return 'Audio quality · stale';
    final current = value.active!;
    final rate = CodecConfiguration.rates[current.sampleRateMask];
    final depth = CodecConfiguration.depths[current.bitsMask];
    final target = current.nominalTargetKbps;
    return [
      current.codecName,
      ?rate,
      ?depth,
      if (target != null)
        '$target kbps'
      else if (current.ldacQuality == LdacQuality.adaptive ||
          current.lhdcV5Quality == LhdcV5Quality.adaptive)
        'Adaptive',
    ].join(' · ');
  }

  /// Caller supplies the verified current OS audio identity and foreground gate.
  /// Repeated meter-driven app rebuilds must not restart native reads or timers.
  void configure({required String? deviceId, required bool active}) {
    if (_disposed) return;
    final target = deviceId?.trim();
    final nextId = target == null || target.isEmpty ? null : target;
    final nextActive = active && nextId != null;
    final sameId =
        nextId == null && _deviceId == null || _same(nextId, _deviceId);
    if (sameId && nextActive == _active) return;
    _deviceId = nextId;
    _active = nextActive;
    _epoch++;
    _poll?.cancel();
    _expiry?.cancel();
    _deadline?.cancel();
    _snapshot = null;
    _failed = false;
    _notify();
    if (_active && !_reading) _refresh();
  }

  bool _current(int epoch) => !_disposed && _active && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _refresh() {
    if (_disposed || !_active || _reading || _deviceId == null) return;
    _poll?.cancel();
    final epoch = _epoch, target = _deviceId!;
    _reading = true;
    var expired = false;
    _deadline = Timer(_requestTimeout, () {
      expired = true;
      if (_current(epoch)) {
        _failed = true;
        _notify();
      }
    });
    // Future.sync also contains synchronous adapter failures. The real future
    // retains ownership until it settles, even after the display deadline.
    Future<CodecSnapshot>.sync(() => _adapter.snapshot(deviceId: target))
        .then<void>(
          (value) {
            if (!_current(epoch) || expired) return;
            _failed = false;
            _snapshot = _matches(value) ? value : null;
            _expiry?.cancel();
            final observation = _snapshot;
            if (observation?.isFresh(_now()) == true) {
              final remaining =
                  observation!.observedAtMs +
                  5001 -
                  _now().millisecondsSinceEpoch;
              _expiry = Timer(
                Duration(milliseconds: remaining > 0 ? remaining : 1),
                () {
                  if (_current(epoch)) _notify();
                },
              );
            }
            _notify();
          },
          onError: (Object _, StackTrace _) {
            if (_current(epoch)) {
              _failed = true;
              _notify();
            }
          },
        )
        .whenComplete(() {
          _deadline?.cancel();
          _reading = false;
          if (_disposed || !_active) return;
          if (epoch != _epoch) {
            // An identity/lifecycle change queued a new observation while the
            // old real native read was still leased. Only now may it start.
            _refresh();
          } else {
            _poll = Timer(_refreshInterval, _refresh);
          }
        });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _poll?.cancel();
    _expiry?.cancel();
    _deadline?.cancel();
    _adapter.dispose();
    super.dispose();
  }
}
