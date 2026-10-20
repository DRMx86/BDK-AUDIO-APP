import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'sound_transfer_packets.dart';
import 'sound_transfer_state.dart';

/// Owns SOUND worker transactions, never the shared session or transport.
/// READY/COMPLETE lack transaction or sequence IDs. One armed response window
/// rejects idle, wrong-stage and duplicate bursts, but cannot identify arbitrary
/// delayed protocol-violating duplicates within an otherwise successful epoch.
/// COMPLETE is the upload boundary. Slot presence is read back separately;
/// missing readback never turns that receipt into an uncertain upload retry.
class SoundTransferController {
  SoundTransferController({
    required SpeakerSession session,
    this.allowChanges = true,
    this.packetTimeout = const Duration(seconds: 5),
    this.completionTimeout = const Duration(seconds: 10),
    this.overallTimeout = const Duration(minutes: 5),
  }) : _session = session {
    if (packetTimeout <= Duration.zero ||
        completionTimeout <= Duration.zero ||
        overallTimeout <= Duration.zero) {
      throw ArgumentError('Transfer deadlines must be positive.');
    }
    _connected = session.state.value.connected;
    _deviceId = session.state.value.deviceId;
    session.state.addListener(_sessionChanged);
  }
  final SpeakerSession _session;
  final bool allowChanges;
  final Duration packetTimeout, completionTimeout, overallTimeout;
  final _state = ValueNotifier(const SoundTransferState());
  ValueListenable<SoundTransferState> get state => _state;
  bool _disposed = false, _connected = false;
  String? _deviceId;
  int _epoch = 0;
  int? _blockedEpoch;
  _SoundOperation? _active;

  Future<SoundTransferResult> upload({
    required int soundType,
    required Uint8List wav,
  }) {
    return _run(
      SoundTransferOperation.upload,
      soundType,
      () {
        SoundTransferPackets.start(soundType, wav.length);
        SoundTransferPackets.validateWav(wav);
        return Uint8List.fromList(
          wav,
        ); // Bound allocation, then own immutable input.
      },
      (op, writer, bytes) async {
        final capacity = _session.state.value.writeCapacity;
        SoundTransferPackets.dataCapacity(capacity);
        await _exchange(
          op,
          writer,
          SoundTransferPackets.start(soundType, bytes.length),
          (event) => event.id == 0x31,
        );
        for (final chunk in SoundTransferPackets.chunks(bytes, capacity)) {
          _emit(op, SoundTransferPhase.uploading);
          await _exchange(
            op,
            writer,
            chunk.packet,
            (event) => event.id == 0x31,
          );
          op.acknowledgedBytes += chunk.dataLength;
          _emit(op, SoundTransferPhase.uploading);
        }
        _emit(op, SoundTransferPhase.finishing);
        await _exchange(
          op,
          writer,
          SoundTransferPackets.end(),
          (event) => event.id == 0x32,
          timeout: completionTimeout,
        );
        op.uploadCompleted = true;
        op.deadline?.cancel();
        await _readUploadPresence(op, writer, soundType);
      },
    );
  }

  Future<void> _readUploadPresence(
    _SoundOperation op,
    SessionWriter writer,
    int soundType,
  ) async {
    op.matchesFlags = (flags) => flags & (1 << soundType) != 0;
    op.observedFlags = null;
    op.flagsConfirmed = false;
    _emit(op, SoundTransferPhase.verifying);
    final window = op.window = _ResponseWindow(
      0xf0,
      (event) => event.soundFlags != null,
    );
    try {
      // Arm first: the status may precede the ATT callback. A fresh response
      // must follow COMPLETE; an earlier cached presence bit is insufficient.
      final att = writer.write(Uint8List.fromList([0xf0]), withResponse: true);
      await Future.any<void>([
        Future.wait<void>([
          att,
          window.reply.future,
        ], eagerError: true).then((_) {}),
        op.aborted.future.then<void>((failure) => throw failure),
      ]).timeout(packetTimeout);
    } on TimeoutException {
      // A missing read-only status reply does not undo worker COMPLETE, and
      // must not trigger an automatic retry of the destructive replacement.
    } finally {
      if (identical(op.window, window)) op.window = null;
    }
  }

  Future<SoundTransferResult> delete(int soundType) => _control(
    SoundTransferOperation.delete,
    soundType,
    () => SoundTransferPackets.delete(soundType),
    (flags) => flags & (1 << soundType) == 0,
  );
  Future<SoundTransferResult> setMuted(bool value) => _control(
    SoundTransferOperation.mute,
    null,
    () => SoundTransferPackets.mute(value),
    (flags) => (flags & 0x80 != 0) == value,
  );
  Future<SoundTransferResult> _control(
    SoundTransferOperation kind,
    int? type,
    Uint8List Function() packet,
    bool Function(int) matches,
  ) {
    return _run(kind, type, packet, (op, writer, bytes) async {
      op.matchesFlags = matches;
      op.controlCommand = bytes.first;
      await _exchange(
        op,
        writer,
        bytes,
        (event) => event.id == 0x10 && event.commandId == bytes.first,
      );
      if (!op.flagsConfirmed) {
        _emit(op, SoundTransferPhase.verifying);
        await _exchange(
          op,
          writer,
          Uint8List.fromList([0xf0]),
          (event) => event.soundFlags != null && matches(event.soundFlags!),
        );
      }
      if (!op.flagsConfirmed) {
        throw const _SoundFailure(
          SoundTransferErrorFamily.command,
          'Speaker sound status changed before confirmation.',
        );
      }
    });
  }

  Future<SoundTransferResult> _run(
    SoundTransferOperation kind,
    int? type,
    Uint8List Function() prepare,
    Future<void> Function(_SoundOperation, SessionWriter, Uint8List) action,
  ) async {
    if (_active != null) return SoundTransferResult.busy;
    if (_disposed) return SoundTransferResult.disabled;
    if (!allowChanges) {
      _state.value = SoundTransferState(
        phase: SoundTransferPhase.disabled,
        operation: kind,
        soundType: type,
        errorFamily: SoundTransferErrorFamily.policy,
        message: 'Changes are unavailable in Demo or preview mode.',
      );
      return SoundTransferResult.disabled;
    }
    if (!_session.state.value.connected || _blockedEpoch == _epoch) {
      _state.value = SoundTransferState(
        phase: SoundTransferPhase.disabled,
        operation: kind,
        soundType: type,
        requiresReconnect: _blockedEpoch != null,
        errorFamily: SoundTransferErrorFamily.connection,
        message:
            'Reconnect and synchronize the speaker before changing sounds.',
      );
      return SoundTransferResult.disabled;
    }
    late Uint8List bytes;
    try {
      bytes = prepare();
    } catch (error) {
      _state.value = SoundTransferState(
        phase: SoundTransferPhase.failed,
        operation: kind,
        soundType: type,
        errorFamily: SoundTransferErrorFamily.validation,
        message: 'Sound input is invalid: $error',
      );
      return SoundTransferResult.failed;
    }
    final op = _active = _SoundOperation(
      kind,
      type,
      _epoch,
      kind == SoundTransferOperation.upload ? bytes.length : 0,
    );
    _emit(op, SoundTransferPhase.starting);
    op.deadline = Timer(
      overallTimeout,
      () => _stop(
        op,
        const _SoundFailure(
          SoundTransferErrorFamily.timeout,
          'The sound operation timed out.',
        ),
      ),
    );
    try {
      _check(op);
      await _session.withExclusiveWriter((writer) async {
        _check(op);
        op.subscription = _session.responses.listen(
          (event) => _response(op, event),
          onError: (Object error) => _stop(
            op,
            _SoundFailure(
              SoundTransferErrorFamily.connection,
              'Sound responses stopped: $error',
            ),
          ),
          onDone: () => _stop(
            op,
            const _SoundFailure(
              SoundTransferErrorFamily.connection,
              'Speaker session closed.',
            ),
          ),
        );
        await action(op, writer, bytes);
        _check(op);
      });
      _check(op);
      op.succeeded = true;
      _emit(op, SoundTransferPhase.completed);
      return SoundTransferResult.completed;
    } catch (error) {
      if (op.uploadCompleted) {
        op.succeeded = true;
        _emit(op, SoundTransferPhase.completed);
        return SoundTransferResult.completed;
      }
      final failure =
          op.failure ??
          (error is _SoundFailure
              ? error
              : _SoundFailure(
                  _session.state.value.connected
                      ? SoundTransferErrorFamily.transport
                      : SoundTransferErrorFamily.connection,
                  'Sound operation failed: $error',
                ));
      _stop(op, failure);
      await op.disconnect;
      _emit(
        op,
        failure.family == SoundTransferErrorFamily.cancelled
            ? SoundTransferPhase.cancelled
            : SoundTransferPhase.failed,
      );
      return failure.family == SoundTransferErrorFamily.cancelled
          ? SoundTransferResult.cancelled
          : SoundTransferResult.failed;
    } finally {
      op.deadline?.cancel();
      await op.subscription?.cancel();
      op.window = null;
      if (identical(_active, op)) _active = null;
      op.finished.complete();
    }
  }

  Future<void> _exchange(
    _SoundOperation op,
    SessionWriter writer,
    Uint8List packet,
    bool Function(ProtocolEvent) accepts, {
    Duration? timeout,
  }) async {
    _check(op);
    final window = op.window = _ResponseWindow(packet.first, accepts);
    final timer = Timer(
      timeout ?? packetTimeout,
      () => _stop(
        op,
        _SoundFailure(
          SoundTransferErrorFamily.timeout,
          'Speaker did not confirm sound command 0x${packet.first.toRadixString(16)}. Reconnect before retrying.',
        ),
      ),
    );
    try {
      // Arm before issuing: replies can precede ATT. No await/notifier in between.
      op.wrote = true;
      final att = writer.write(packet, withResponse: true);
      await Future.any<void>([
        Future.wait<void>([
          att,
          window.reply.future,
        ], eagerError: true).then((_) {}),
        op.aborted.future.then<void>((failure) => throw failure),
      ]);
      _check(op);
    } finally {
      timer.cancel();
      if (identical(op.window, window)) op.window = null;
    }
  }

  void _response(_SoundOperation op, ProtocolEvent event) {
    if (!identical(_active, op) ||
        op.failure != null ||
        _disposed ||
        op.epoch != _epoch) {
      return;
    }
    if (!op.wrote || op.succeeded) return;
    if (event.id == 0x33 &&
        op.kind == SoundTransferOperation.upload &&
        !op.uploadCompleted) {
      _stop(
        op,
        _SoundFailure(
          SoundTransferErrorFamily.worker,
          'Speaker sound worker failed. The previous sound may already be removed.',
          code: event.error,
        ),
      );
      return;
    }
    final window = op.window;
    if (window == null) return;
    if (event.id == 0x11 &&
        (event.commandId == window.command ||
            event.commandId == op.controlCommand)) {
      _stop(
        op,
        _SoundFailure(
          SoundTransferErrorFamily.command,
          'Speaker rejected the sound command.',
          code: event.error,
        ),
      );
      return;
    }
    if (event.id == 0x30 && op.kind == SoundTransferOperation.upload) {
      op.reportedProgress = event.progress;
      _emit(op, _state.value.phase);
    }
    if (event.soundFlags != null && op.matchesFlags != null) {
      op.observedFlags = event.soundFlags;
      op.flagsConfirmed = op.matchesFlags!(event.soundFlags!);
    }
    if (!window.reply.isCompleted && window.accepts(event)) {
      window.reply.complete();
    }
  }

  void _check(_SoundOperation op) {
    if (op.failure != null) throw op.failure!;
    if (_disposed || !identical(_active, op)) {
      throw const _SoundFailure(
        SoundTransferErrorFamily.cancelled,
        'Sound operation cancelled.',
      );
    }
    if (op.epoch != _epoch || !_session.state.value.connected) {
      throw const _SoundFailure(
        SoundTransferErrorFamily.connection,
        'Speaker connection changed.',
      );
    }
  }

  void _stop(_SoundOperation op, _SoundFailure failure) {
    if (!identical(_active, op) || op.failure != null || op.succeeded) return;
    op.failure = failure;
    op.aborted.complete(failure);
    if (op.uploadCompleted) return;
    if (op.wrote) {
      _blockedEpoch = op.epoch;
      // Disconnect invalidates pending ATT/lease. No abort packet or retry exists.
      if (_session.state.value.connected) {
        op.disconnect = _session.disconnect().catchError((_) {});
      }
    }
  }

  void _sessionChanged() {
    final current = _session.state.value;
    if (current.connected != _connected || current.deviceId != _deviceId) {
      _epoch++;
      _connected = current.connected;
      _deviceId = current.deviceId;
      final op = _active;
      if (op != null) {
        _stop(
          op,
          const _SoundFailure(
            SoundTransferErrorFamily.connection,
            'Speaker connection was lost or changed.',
          ),
        );
      }
      if (op == null || op.uploadCompleted) {
        // A receipt from an old connection is historical evidence, not the
        // current speaker's slot state, even while its readback lease drains.
        _state.value = const SoundTransferState();
      }
      if (current.connected && _blockedEpoch != _epoch) _blockedEpoch = null;
    }
  }

  void _emit(_SoundOperation op, SoundTransferPhase phase) {
    if (_disposed ||
        !identical(_active, op) ||
        (op.uploadCompleted && op.epoch != _epoch)) {
      return;
    }
    _state.value = SoundTransferState(
      phase: phase,
      operation: op.kind,
      soundType: op.type,
      totalBytes: op.totalBytes,
      acknowledgedBytes: op.acknowledgedBytes,
      reportedProgress: op.reportedProgress,
      observedSoundFlags: op.observedFlags,
      uploadCompleted: op.uploadCompleted,
      presenceConfirmed: op.uploadCompleted && op.flagsConfirmed,
      errorFamily: op.uploadCompleted ? null : op.failure?.family,
      errorCode: op.uploadCompleted ? null : op.failure?.code,
      message: op.uploadCompleted && !op.flagsConfirmed
          ? 'Upload confirmed by speaker; sound presence could not be confirmed. Reconnect to refresh the slot status before relying on it.'
          : op.failure?.message,
      requiresReconnect: op.uploadCompleted
          ? !_session.state.value.connected
          : op.failure != null && op.wrote,
      previousSoundMayBeLost:
          op.kind == SoundTransferOperation.upload &&
          !op.uploadCompleted &&
          op.wrote &&
          op.failure != null,
    );
  }

  Future<void> cancel() async {
    final op = _active;
    if (op == null) return;
    if (op.succeeded) {
      await op.finished.future;
      return;
    }
    _stop(
      op,
      const _SoundFailure(
        SoundTransferErrorFamily.cancelled,
        'Sound operation cancelled. Reconnect before retrying.',
      ),
    );
    _emit(op, SoundTransferPhase.cancelling);
    await op.finished.future;
  }

  Future<void> onAudioDisconnected() => cancel();
  void dispose() {
    if (_disposed) return;
    final op = _active;
    if (op != null) {
      _stop(
        op,
        const _SoundFailure(
          SoundTransferErrorFamily.cancelled,
          'Sound operation cancelled.',
        ),
      );
    }
    _disposed = true;
    _session.state.removeListener(_sessionChanged);
    _state.dispose();
  }
}

class _SoundOperation {
  _SoundOperation(this.kind, this.type, this.epoch, this.totalBytes);
  final SoundTransferOperation kind;
  final int? type;
  final int epoch, totalBytes;
  final aborted = Completer<_SoundFailure>();
  final finished = Completer<void>();
  int acknowledgedBytes = 0;
  int? reportedProgress, observedFlags, controlCommand;
  bool wrote = false,
      flagsConfirmed = false,
      succeeded = false,
      uploadCompleted = false;
  bool Function(int)? matchesFlags;
  _SoundFailure? failure;
  _ResponseWindow? window;
  Timer? deadline;
  StreamSubscription<ProtocolEvent>? subscription;
  Future<void>? disconnect;
}

class _ResponseWindow {
  _ResponseWindow(this.command, this.accepts);
  final int command;
  final bool Function(ProtocolEvent) accepts;
  final reply = Completer<void>();
}

class _SoundFailure implements Exception {
  const _SoundFailure(this.family, this.message, {this.code});
  final SoundTransferErrorFamily family;
  final String message;
  final int? code;
  @override
  String toString() => message;
}
