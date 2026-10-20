import 'dart:async';
import 'package:flutter/foundation.dart';
import 'codec_adapter.dart';
import 'codec_models.dart';

enum CodecOperationPhase {
  idle,
  loading,
  submitting,
  verifying,
  confirmed,
  refused,
  timedOut,
  error,
}

enum CodecApplyResult { confirmed, refused, timedOut, cancelled, disabled }

class _Operation {
  final cancelled = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }
}

class _Superseded implements Exception {
  const _Superseded();
}

/// One native lease at a time. A UI timeout never releases an in-flight setter.
/// This controller owns its adapter; the screen only listens to this controller.
class CodecController extends ChangeNotifier {
  CodecController({
    required this._adapter,
    this._deviceId,
    this.allowChanges = true,
    this._nativeTimeout = const Duration(seconds: 10),
    this._consentTimeout = const Duration(minutes: 3, seconds: 15),
    this._verificationTimeout = const Duration(seconds: 6),
    this._pollInterval = const Duration(milliseconds: 250),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final CodecAdapter _adapter;
  final bool allowChanges;
  final Duration _nativeTimeout,
      _consentTimeout,
      _verificationTimeout,
      _pollInterval;
  final DateTime Function() _now;
  String? _deviceId;
  CodecSnapshot? _snapshot;
  CodecPreference? _preference;
  CodecOperationPhase _phase = CodecOperationPhase.idle;
  String? _message, _errorDetails;
  bool _requiresRefresh = false, _disposed = false;
  Future<void> _nativeTail = Future<void>.value();
  Future<CodecApplyResult>? _pendingApply;
  _Operation? _operation;

  CodecSnapshot? get snapshot => _snapshot;
  CodecPreference? get preference => _preference;
  CodecOperationPhase get phase => _phase;
  String? get message => _message;
  String? get errorDetails => _errorDetails;
  bool get busy => const [
    CodecOperationPhase.loading,
    CodecOperationPhase.submitting,
    CodecOperationPhase.verifying,
  ].contains(_phase);
  bool get requiresRefresh => _requiresRefresh;
  bool get hasFreshObservation => _snapshot?.isFresh(_now()) == true;
  bool get canEdit =>
      !_disposed &&
      allowChanges &&
      !busy &&
      !_requiresRefresh &&
      _snapshot?.canApply == true;
  List<LdacQuality> get ldacQualities =>
      _preference?.codecType == 4 &&
          const [1, 2, 4, 8].contains(_preference?.sampleRateMask)
      ? _snapshot?.ldacQualities ?? const []
      : const [];
  List<LhdcV5Quality> get lhdcV5Qualities =>
      _snapshot != null &&
          _preference?.codecType == _snapshot!.active?.codecType
      ? _snapshot!.lhdcV5QualitiesForRate(_preference?.sampleRateMask ?? 0)
      : const [];
  Duration? get observationValidityRemaining {
    final value = _snapshot;
    if (value == null || !value.isFresh(_now())) {
      return null;
    }
    return Duration(
      milliseconds: value.observedAtMs + 5001 - _now().millisecondsSinceEpoch,
    );
  }

  List<CodecPreference> get _choices => _snapshot?.preferences ?? const [];
  List<int> get codecTypes => _choices.map((p) => p.codecType).toSet().toList();
  List<int> get sampleRates =>
      _choices
          .where((p) => p.codecType == _preference?.codecType)
          .map((p) => p.sampleRateMask)
          .toSet()
          .toList()
        ..sort();
  List<int> get bitDepths =>
      _choices
          .where(
            (p) =>
                p.codecType == _preference?.codecType &&
                p.sampleRateMask == _preference?.sampleRateMask,
          )
          .map((p) => p.bitsMask)
          .toSet()
          .toList()
        ..sort();
  List<int> get channelModes =>
      _choices
          .where(
            (p) =>
                p.codecType == _preference?.codecType &&
                p.sampleRateMask == _preference?.sampleRateMask &&
                p.bitsMask == _preference?.bitsMask,
          )
          .map((p) => p.channelMask)
          .toSet()
          .toList()
        ..sort();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(_Operation op) =>
      !_disposed && identical(op, _operation) && !op.cancelled.isCompleted;
  _Operation _begin(CodecOperationPhase phase) {
    if (_disposed) throw StateError('Audio quality controller is closed.');
    _operation?.cancel();
    final op = _Operation();
    _operation = op;
    _phase = phase;
    _message = null;
    _errorDetails = null;
    _notify();
    return op;
  }

  Future<T> _wait<T>(
    Future<T> raw,
    _Operation op, {
    Future<void>? deadline,
    Duration? timeout,
  }) async {
    final expired = Completer<void>();
    final timer = Timer(timeout ?? _nativeTimeout, expired.complete);
    try {
      final value = await Future.any<T>([
        raw,
        op.cancelled.future.then<T>((_) => throw const _Superseded()),
        expired.future.then<T>(
          (_) => throw TimeoutException('Android Bluetooth did not respond.'),
        ),
        if (deadline != null)
          deadline.then<T>(
            (_) => throw TimeoutException(
              'Negotiated readback was not confirmed.',
            ),
          ),
      ]);
      if (!_valid(op)) throw const _Superseded();
      return value;
    } finally {
      timer.cancel();
    }
  }

  Future<T> _native<T>(
    _Operation op,
    Future<T> Function() call, {
    Future<void>? deadline,
    Duration? timeout,
  }) {
    final raw = _nativeTail.then<T>((_) {
      if (!_valid(op)) throw const _Superseded();
      return call();
    });
    // Await the REAL completion here, not the timeout wrapper returned to the UI.
    _nativeTail = raw.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return _wait(raw, op, deadline: deadline, timeout: timeout);
  }

  Future<void> _delay(_Operation op, Future<void> deadline) async {
    final ready = Completer<void>();
    final timer = Timer(_pollInterval, ready.complete);
    try {
      await _wait(ready.future, op, deadline: deadline);
    } finally {
      timer.cancel();
    }
  }

  bool _sameDevice(CodecSnapshot value, String? target) =>
      target == null ||
      value.selectedDeviceId?.toLowerCase() == target.toLowerCase();

  void _accept(CodecSnapshot value, {bool keepDraft = false}) {
    _snapshot = value;
    _deviceId ??= value.selectedDeviceId;
    if (keepDraft) return;
    if (_preference != null && value.supports(_preference!)) return;
    final matching = value.preferences.where(
      (p) => value.active != null && p.matches(value.active!),
    );
    _preference = matching.isNotEmpty
        ? matching.first
        : value.preferences.firstOrNull;
  }

  Future<void> refresh() async {
    if (const [
      CodecOperationPhase.submitting,
      CodecOperationPhase.verifying,
    ].contains(_phase)) {
      await _pendingApply;
      return;
    }
    final target = _deviceId;
    final op = _begin(CodecOperationPhase.loading);
    final deadline = Completer<void>();
    final initializationTimer = Timer(_nativeTimeout, deadline.complete);
    try {
      CodecSnapshot next;
      while (true) {
        next = await _native(
          op,
          () => _adapter.snapshot(deviceId: target),
          deadline: deadline.future,
        );
        if (next.access == CodecAccess.ready && !_sameDevice(next, target)) {
          throw const CodecAdapterException(
            'deviceChanged',
            'The audio device changed. Select your speaker again.',
          );
        }
        _accept(next);
        if (next.access != CodecAccess.initializing) break;
        // A2DP profile acquisition is asynchronous. Stay within one read
        // deadline instead of leaving the first screen waiting for a tap.
        _notify();
        await _delay(op, deadline.future);
      }
      _requiresRefresh =
          next.access == CodecAccess.ready && !next.isFresh(_now());
      _phase = CodecOperationPhase.idle;
      _message = _requiresRefresh
          ? 'Current information is old. Refresh before changing preferences.'
          : null;
      _notify();
    } on _Superseded {
      return;
    } catch (error) {
      if (_valid(op)) _failure(error);
    } finally {
      initializationTimer.cancel();
    }
  }

  Future<void> selectDevice(String id) async {
    if (id.trim().isEmpty) throw ArgumentError('Select an audio device.');
    _operation?.cancel();
    _deviceId = id;
    _snapshot = null;
    _preference = null;
    _phase = CodecOperationPhase.idle;
    _requiresRefresh = false;
    await refresh();
  }

  void setPreference(CodecPreference value) {
    if (!canEdit) {
      throw StateError('Refresh supported preferences before changing them.');
    }
    if (!_snapshot!.supports(value)) {
      throw ArgumentError(
        'This combination is not reported by the connected device.',
      );
    }
    _preference = value;
    _message = null;
    _errorDetails = null;
    _phase = CodecOperationPhase.idle;
    _notify();
  }

  void _choose(Iterable<CodecPreference> choices) {
    final values = choices.toList();
    if (values.isEmpty) throw ArgumentError('This choice is not supported.');
    final old = _preference;
    final sameFormat = values.where(
      (p) =>
          p.sampleRateMask == old?.sampleRateMask &&
          p.bitsMask == old?.bitsMask &&
          p.channelMask == old?.channelMask,
    );
    final same = values.where(
      (p) => p.bitsMask == old?.bitsMask && p.channelMask == old?.channelMask,
    );
    final sameChannel = values.where((p) => p.channelMask == old?.channelMask);
    var chosen =
        sameFormat.firstOrNull ??
        same.firstOrNull ??
        sameChannel.firstOrNull ??
        values.first;
    if (chosen.codecType == old?.codecType && old?.ldacQuality != null) {
      final retained = chosen.withLdacQuality(old!.ldacQuality);
      if (_snapshot!.supports(retained)) chosen = retained;
    }
    final active = _snapshot!.active;
    if (chosen.codecType == active?.codecType &&
        active?.lhdcV5Quality != null) {
      final allowed = _snapshot!.lhdcV5QualitiesForRate(chosen.sampleRateMask);
      final previous = old?.lhdcV5Quality ?? active!.lhdcV5Quality!;
      var adjusted = previous;
      if (!allowed.contains(previous) && allowed.isNotEmpty) {
        final fixed = allowed
            .where((q) => q.nominalTargetKbps != null)
            .toList();
        if (fixed.isEmpty || previous.nominalTargetKbps == null) {
          adjusted = LhdcV5Quality.adaptive;
        } else {
          final below = fixed.where(
            (q) => q.nominalTargetKbps! <= previous.nominalTargetKbps!,
          );
          adjusted = below.lastOrNull ?? fixed.first;
        }
      }
      if (allowed.contains(adjusted)) {
        chosen = chosen.withLhdcV5Quality(adjusted);
      }
    }
    setPreference(chosen);
  }

  void selectCodec(int value) {
    final choices = _choices.where((p) => p.codecType == value).toList();
    final current = choices.where(
      (p) => _snapshot?.active != null && p.matches(_snapshot!.active!),
    );
    if (current.isNotEmpty) {
      setPreference(current.first);
    } else {
      _choose(choices);
    }
  }

  void selectSampleRate(int value) => _choose(
    _choices.where(
      (p) => p.codecType == _preference?.codecType && p.sampleRateMask == value,
    ),
  );
  void selectBitDepth(int value) => _choose(
    _choices.where(
      (p) =>
          p.codecType == _preference?.codecType &&
          p.sampleRateMask == _preference?.sampleRateMask &&
          p.bitsMask == value,
    ),
  );
  void selectChannelMode(int value) => _choose(
    _choices.where(
      (p) =>
          p.codecType == _preference?.codecType &&
          p.sampleRateMask == _preference?.sampleRateMask &&
          p.bitsMask == _preference?.bitsMask &&
          p.channelMask == value,
    ),
  );
  void selectLdacQuality(LdacQuality value) {
    if (!canEdit || !ldacQualities.contains(value)) {
      throw StateError(
        'Read a recognized LDAC connection before choosing quality.',
      );
    }
    setPreference(_preference!.withLdacQuality(value));
  }

  void selectLhdcV5Quality(LhdcV5Quality value) {
    if (!canEdit || !lhdcV5Qualities.contains(value)) {
      throw StateError(
        'Read a recognized LHDC V5 connection before choosing a target.',
      );
    }
    setPreference(_preference!.withLhdcV5Quality(value));
  }

  Future<CodecApplyResult> applyPreference() async {
    if (!canEdit || _preference == null || _deviceId == null) {
      return CodecApplyResult.disabled;
    }
    final pending = _apply(_preference!, _deviceId!);
    _pendingApply = pending;
    try {
      return await pending;
    } finally {
      if (identical(_pendingApply, pending)) _pendingApply = null;
    }
  }

  Future<CodecApplyResult> _apply(CodecPreference requested, String id) async {
    final op = _begin(CodecOperationPhase.submitting);
    Timer? verificationTimer;
    var submitted = false, writeStarted = false;
    try {
      final fresh = await _native(op, () => _adapter.snapshot(deviceId: id));
      if (!_sameDevice(fresh, id)) {
        throw const CodecAdapterException(
          'deviceChanged',
          'The selected audio speaker is no longer available.',
        );
      }
      _accept(fresh, keepDraft: true);
      if (!fresh.canApply ||
          !fresh.isFresh(_now()) ||
          !fresh.supports(requested)) {
        _phase = CodecOperationPhase.refused;
        _message =
            'This preference is no longer available. Refresh the connection.';
        _requiresRefresh = true;
        _notify();
        return CodecApplyResult.refused;
      }
      final submittedAfter = _now().millisecondsSinceEpoch;
      writeStarted = true;
      submitted = await _native(
        op,
        () => _adapter.apply(
          deviceId: id,
          configuration: fresh.configurationFor(requested),
        ),
      );
      if (!submitted) {
        _phase = CodecOperationPhase.refused;
        _message = 'The device declined this preference.';
        _notify();
        return CodecApplyResult.refused;
      }
      _phase = CodecOperationPhase.verifying;
      _message = 'Checking the current connection…';
      _notify();
      final deadline = Completer<void>();
      verificationTimer = Timer(_verificationTimeout, deadline.complete);
      while (_valid(op)) {
        final next = await _native(
          op,
          () => _adapter.snapshot(deviceId: id),
          deadline: deadline.future,
        );
        if (next.access == CodecAccess.apiUnavailable &&
            _sameDevice(next, id)) {
          // The native bridge discards pre-submission broadcasts. OEMs that
          // restrict direct reads may need time to deliver the next one.
          // Missing telemetry cannot confirm a preference or extend the bound.
          _accept(next, keepDraft: true);
          _notify();
          await _delay(op, deadline.future);
          continue;
        }
        if (next.access != CodecAccess.ready) {
          _accept(next, keepDraft: true);
          throw const CodecAdapterException(
            'readbackUnavailable',
            'The current connection could not be confirmed. Refresh or check Bluetooth settings.',
          );
        }
        if (!_sameDevice(next, id)) {
          throw const CodecAdapterException(
            'deviceChanged',
            'The audio connection changed before confirmation.',
          );
        }
        // Older cached broadcasts may be valid telemetry, but cannot confirm this request.
        if (next.isFresh(_now()) && next.observedAtMs > submittedAfter) {
          _accept(next, keepDraft: true);
          _notify();
          if (requested.matches(next.active!)) {
            _phase = CodecOperationPhase.confirmed;
            _requiresRefresh = false;
            _message = 'Current connection confirmed.';
            _notify();
            return CodecApplyResult.confirmed;
          }
        }
        await _delay(op, deadline.future);
      }
      return CodecApplyResult.cancelled;
    } on _Superseded {
      return CodecApplyResult.cancelled;
    } catch (error) {
      if (!_valid(op)) return CodecApplyResult.cancelled;
      _requiresRefresh = writeStarted || submitted;
      _failure(error, applying: true);
      return _isTimeout(error)
          ? CodecApplyResult.timedOut
          : CodecApplyResult.refused;
    } finally {
      verificationTimer?.cancel();
    }
  }

  void _failure(Object error, {bool applying = false}) {
    // A timeout can win before a queued closure obtains the native lease.
    // Prevent that obsolete closure from starting later; _nativeTail still
    // waits for any real native call that has already begun.
    _operation?.cancel();
    _requiresRefresh = true;
    _phase = _isTimeout(error)
        ? CodecOperationPhase.timedOut
        : applying
        ? CodecOperationPhase.refused
        : CodecOperationPhase.error;
    _message = error is CodecAdapterException
        ? error.message
        : error is TimeoutException
        ? applying
              ? 'The preference was not confirmed in time. Refresh before retrying.'
              : 'Android did not finish reading audio quality. Refresh to try again.'
        : 'Audio quality is unavailable. Refresh or use Bluetooth settings.';
    _errorDetails = error is CodecAdapterException ? error.details : '$error';
    _notify();
  }

  bool _isTimeout(Object error) =>
      error is TimeoutException ||
      error is CodecAdapterException &&
          const ['codecTimeout', 'consentTimeout'].contains(error.code);

  Future<void> _consent(
    Future<void> Function() action, {
    bool refreshAfter = true,
  }) async {
    if (_disposed || !allowChanges || busy) return;
    final op = _begin(CodecOperationPhase.loading);
    try {
      await _native(
        op,
        action,
        timeout: refreshAfter ? _consentTimeout : _nativeTimeout,
      );
      if (refreshAfter) {
        _phase = CodecOperationPhase.idle;
        await refresh();
      } else {
        _phase = CodecOperationPhase.idle;
        _notify();
      }
    } on _Superseded {
      return;
    } catch (error) {
      if (_valid(op)) _failure(error);
    }
  }

  Future<void> requestPermission() => _consent(_adapter.requestPermission);
  Future<void> associate() async {
    final id = _deviceId ?? _snapshot?.selectedDeviceId;
    if (id == null) return;
    await _consent(() => _adapter.associate(id));
  }

  Future<void> openBluetoothSettings() =>
      _consent(_adapter.openBluetoothSettings, refreshAfter: false);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operation?.cancel();
    _adapter.dispose();
    super.dispose();
  }
}
