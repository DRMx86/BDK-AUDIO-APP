import 'dart:async';
import 'package:bdk_audio/connection/speaker_session.dart';
import 'package:bdk_audio/protocol/speaker_protocol.dart';
import 'package:flutter/foundation.dart';
import 'firmware_image.dart';
import 'ota_transfer_packets.dart';
import 'ota_transfer_state.dart';

/// Baseline OTA protocol controller. DATA is ATT-confirmed, not worker-receipted.
/// Untagged READY/COMPLETE cannot identify arbitrarily delayed protocol-violating
/// duplicates in an otherwise successful epoch. One armed window rejects idle,
/// wrong-stage and duplicate bursts. Uncertainty is never resumed or retried.
/// A reported-version match is not attestation of image bytes or authenticity.
class OtaTransferController {
  OtaTransferController({
    required SpeakerSession session,
    this.allowChanges = true,
    this.packetTimeout = const Duration(seconds: 5),
    this.completionTimeout = const Duration(seconds: 10),
    this.overallTimeout = const Duration(minutes: 15),
    this.abortTimeout = const Duration(seconds: 2),
    this.verificationTimeout = const Duration(seconds: 5),
  }) : _session = session {
    for (final deadline in [
      packetTimeout,
      completionTimeout,
      overallTimeout,
      abortTimeout,
      verificationTimeout,
    ]) {
      if (deadline <= Duration.zero) {
        throw ArgumentError('OTA deadlines must be positive.');
      }
    }
    _connected = session.state.value.connected;
    _deviceId = session.state.value.deviceId;
    session.state.addListener(_sessionChanged);
  }
  final SpeakerSession _session;
  final bool allowChanges;
  final Duration packetTimeout,
      completionTimeout,
      overallTimeout,
      abortTimeout,
      verificationTimeout;
  final _state = ValueNotifier(const OtaTransferState());
  ValueListenable<OtaTransferState> get state => _state;
  bool _disposed = false, _connected = false;
  String? _deviceId;
  int _epoch = 0;
  int? _blockedEpoch;
  _OtaOperation? _active;
  _OtaReceipt? _receipt;
  bool get canTransfer =>
      !_disposed &&
      allowChanges &&
      _active == null &&
      _session.state.value.connected &&
      _blockedEpoch != _epoch &&
      (_receipt == null || _receipt!.epoch != _epoch);
  bool get canVerify =>
      !_disposed &&
      allowChanges &&
      _active == null &&
      _receipt != null &&
      _receipt!.lostConnection &&
      _session.state.value.connected &&
      _session.state.value.deviceId == _receipt!.id &&
      _receipt!.epoch != _epoch;

  Future<OtaTransferResult> transfer(
    FirmwareImage image, {
    String? expectedVersion,
  }) async {
    if (_active != null) return OtaTransferResult.busy;
    if (_disposed) return OtaTransferResult.disabled;
    if (!canTransfer) return _unavailable(policy: !allowChanges);
    final expected = (expectedVersion ?? image.version).trim();
    if (expected.isEmpty ||
        expected.length > 64 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(expected)) {
      _state.value = const OtaTransferState(
        phase: OtaTransferPhase.failed,
        errorFamily: OtaTransferErrorFamily.validation,
        message: 'Choose a valid expected reported firmware version.',
      );
      return OtaTransferResult.failed;
    }
    final op = _OtaOperation(
      _epoch,
      _session.state.value.deviceId!,
      image,
      expected,
    );
    return _run(op, (writer) async {
      _emit(op, OtaTransferPhase.starting);
      await _exchange(
        op,
        writer,
        OtaTransferPackets.begin(image.sizeBytes),
        (event) => event.id == 0x21,
      );
      final capacity = _session.state.value.writeCapacity;
      for (final chunk in OtaTransferPackets.chunks(image.bytes, capacity)) {
        _emit(op, OtaTransferPhase.uploading);
        await _exchange(op, writer, chunk.packet, null);
        op.attCompletedBytes += chunk.dataLength;
        _emit(op, OtaTransferPhase.uploading);
      }
      _emit(op, OtaTransferPhase.finishing);
      await _exchange(
        op,
        writer,
        OtaTransferPackets.end(),
        (event) => event.id == 0x22,
        timeout: completionTimeout,
      );
      // Both END ATT and worker COMPLETE are now confirmed. An immediate reboot
      // may invalidate the old lease; it must not undo this terminal boundary.
      op.succeeded = true;
      op.successResult = OtaTransferResult.transferred;
      _receipt = _OtaReceipt(op.epoch, op.id, image, expected);
      _emit(
        op,
        OtaTransferPhase.awaitingRestart,
        message:
            'Transfer confirmed. Reconnect the original speaker to check its reported version.',
      );
    });
  }

  Future<OtaTransferResult> verifyAfterReconnect() async {
    if (_active != null) return OtaTransferResult.busy;
    if (_disposed) return OtaTransferResult.disabled;
    if (!allowChanges) return _unavailable(policy: true);
    final receipt = _receipt;
    if (!canVerify || receipt == null) {
      _state.value = _state.value.copyWith(
        phase: OtaTransferPhase.verificationUnavailable,
        message:
            'Reconnect and synchronize the original speaker before reading its reported version.',
      );
      return OtaTransferResult.verificationUnavailable;
    }
    final op = _OtaOperation(
      _epoch,
      receipt.id,
      receipt.image,
      receipt.expected,
      verifying: true,
    );
    op.attCompletedBytes = receipt.image.sizeBytes;
    return _run(op, (writer) async {
      _emit(
        op,
        OtaTransferPhase.verifying,
        message: 'Reading the reconnected speaker’s reported version…',
      );
      final event = await _exchange(
        op,
        writer,
        Uint8List.fromList([0xf0]),
        (event) => event.fullStatus,
        timeout: verificationTimeout,
      );
      final reported = event!.firmware?.trim() ?? '';
      op.reportedVersion = reported;
      receipt.reportedVersion = reported;
      op.succeeded = true;
      if (reported.isEmpty) {
        op.successResult = OtaTransferResult.verificationUnavailable;
        _emit(
          op,
          OtaTransferPhase.verificationUnavailable,
          message:
              'The speaker did not report a firmware version. Transfer completion remains separate from verification.',
        );
      } else if (reported == receipt.expected) {
        op.successResult = OtaTransferResult.versionMatched;
        _emit(
          op,
          OtaTransferPhase.versionMatched,
          message:
              'The reconnected speaker reports the expected version. This does not verify its image hash or authenticity.',
        );
      } else {
        op.successResult = OtaTransferResult.versionMismatch;
        _emit(
          op,
          OtaTransferPhase.versionMismatch,
          message:
              'The reconnected speaker reports $reported; expected ${receipt.expected}. No rollback outcome can be inferred.',
          displayFailure: const _OtaFailure(
            OtaTransferErrorFamily.verification,
            'Reported version does not match.',
          ),
        );
      }
    });
  }

  OtaTransferResult _unavailable({bool policy = false}) {
    _state.value = _state.value.copyWith(
      phase: OtaTransferPhase.disabled,
      message: policy
          ? 'Device updates are unavailable in Demo or preview mode.'
          : 'Reconnect and synchronize the speaker before starting a new update.',
      requiresReconnect: !policy,
      errorFamily: policy
          ? OtaTransferErrorFamily.policy
          : OtaTransferErrorFamily.connection,
      clearErrorCode: true,
    );
    return OtaTransferResult.disabled;
  }

  Future<OtaTransferResult> _run(
    _OtaOperation op,
    Future<void> Function(SessionWriter) action,
  ) async {
    _active = op;
    op.deadline = Timer(
      overallTimeout,
      () => _stop(
        op,
        const _OtaFailure(
          OtaTransferErrorFamily.timeout,
          'The update operation exceeded its time limit.',
        ),
      ),
    );
    try {
      await _session.withExclusiveWriter((writer) async {
        _check(op);
        op.subscription = _session.responses.listen(
          (event) => _response(op, event),
          onError: (Object error) => _stop(
            op,
            _OtaFailure(
              OtaTransferErrorFamily.connection,
              'Update responses stopped: $error',
            ),
          ),
          onDone: () => _stop(
            op,
            const _OtaFailure(
              OtaTransferErrorFamily.connection,
              'Speaker session closed.',
            ),
          ),
        );
        try {
          await action(writer);
        } catch (error) {
          if (op.tryAbort) {
            if (!_disposed && _sameConnection(op)) {
              await _abortLeased(op, writer);
            }
            _disconnect(op);
          }
          rethrow;
        }
      });
      if (op.succeeded) return op.successResult!;
      _check(op);
      throw StateError('Update action did not reach a terminal result.');
    } catch (error) {
      if (op.succeeded) return op.successResult!;
      final failure =
          op.failure ??
          (error is _OtaFailure
              ? error
              : _OtaFailure(
                  _session.state.value.connected
                      ? OtaTransferErrorFamily.transport
                      : OtaTransferErrorFamily.connection,
                  'Update operation failed: $error',
                ));
      _stop(op, failure);
      _disconnect(op);
      await op.disconnect;
      _emit(
        op,
        failure.family == OtaTransferErrorFamily.cancelled
            ? OtaTransferPhase.cancelled
            : OtaTransferPhase.failed,
      );
      return failure.family == OtaTransferErrorFamily.cancelled
          ? OtaTransferResult.cancelled
          : OtaTransferResult.failed;
    } finally {
      op.deadline?.cancel();
      await op.subscription?.cancel();
      op.window = null;
      if (identical(_active, op)) _active = null;
      op.finished.complete();
    }
  }

  Future<ProtocolEvent?> _exchange(
    _OtaOperation op,
    SessionWriter writer,
    Uint8List packet,
    bool Function(ProtocolEvent)? accepts, {
    Duration? timeout,
  }) async {
    _check(op);
    final window = op.window = _OtaWindow(packet.first, accepts);
    final cancelled = Completer<ProtocolEvent?>();
    void onCancelled(_OtaFailure failure) => cancelled.completeError(failure);
    op.cancelListeners.add(onCancelled);
    final timer = Timer(
      timeout ?? packetTimeout,
      () => _stop(
        op,
        _OtaFailure(
          OtaTransferErrorFamily.timeout,
          'Speaker did not confirm update command 0x${packet.first.toRadixString(16)}. Reconnect before trying again.',
        ),
      ),
    );
    try {
      op.wrote = true;
      op.attPending = true;
      if (packet.first == 0x20) _receipt = null;
      op.issuedCommands.add(packet.first);
      final att = writer
          .write(packet, withResponse: true)
          .whenComplete(() => op.attPending = false);
      final exchange = accepts == null
          ? att.then<ProtocolEvent?>((_) => null)
          : Future.wait<Object?>(
              [att, window.reply.future],
              eagerError: true,
            ).then<ProtocolEvent?>((results) => results[1] as ProtocolEvent);
      final event = await Future.any<ProtocolEvent?>([
        exchange,
        cancelled.future,
      ]);
      _check(op);
      return event;
    } finally {
      timer.cancel();
      op.cancelListeners.remove(onCancelled);
      if (identical(op.window, window)) op.window = null;
    }
  }

  void _response(_OtaOperation op, ProtocolEvent event) {
    if (_disposed ||
        !identical(_active, op) ||
        op.epoch != _epoch ||
        op.succeeded ||
        !op.wrote) {
      return;
    }
    final window = op.window;
    if (window?.isAbort ?? false) {
      if (!window!.reply.isCompleted && window.accepts!(event)) {
        window.reply.complete(event);
      }
      return;
    }
    if (op.failure != null) return;
    if (!op.verifying && event.id == 0x23) {
      _stop(
        op,
        _OtaFailure(
          OtaTransferErrorFamily.worker,
          'Speaker update worker failed. Its boot/update state is not verified.',
          code: event.error,
        ),
      );
      return;
    }
    if (event.id == 0x11 &&
        (op.verifying
            ? event.commandId == window?.command
            : op.issuedCommands.contains(event.commandId))) {
      _stop(
        op,
        _OtaFailure(
          OtaTransferErrorFamily.command,
          'Speaker rejected the update command.',
          code: event.error,
        ),
      );
      return;
    }
    if (window == null) return;
    if (!op.verifying && event.id == 0x20) {
      op.reportedProgress = event.progress;
      _emit(op, _state.value.phase);
    }
    if (window.accepts != null &&
        !window.reply.isCompleted &&
        window.accepts!(event)) {
      window.reply.complete(event);
    }
  }

  Future<void> _abortLeased(_OtaOperation op, SessionWriter writer) async {
    if (op.attPending || !_sameConnection(op) || _disposed) return;
    final window = op.window = _OtaWindow(
      0x23,
      (event) =>
          (event.id == 0x10 || event.id == 0x11) && event.commandId == 0x23,
      isAbort: true,
    );
    _emit(
      op,
      OtaTransferPhase.aborting,
      message:
          'Requesting cancellation, then disconnecting speaker controls. An abort ACK does not prove rollback.',
    );
    if (!_sameConnection(op) || _disposed) {
      op.window = null;
      return;
    }
    try {
      op.attPending = true;
      final att = writer
          .write(OtaTransferPackets.abort(), withResponse: true)
          .whenComplete(() => op.attPending = false);
      final replies = await Future.wait<Object?>([
        att,
        window.reply.future,
      ], eagerError: true).timeout(abortTimeout);
      op.abortConfirmed = (replies[1] as ProtocolEvent).id == 0x10;
    } catch (_) {
      op.abortConfirmed = false;
    } finally {
      if (identical(op.window, window)) op.window = null;
    }
  }

  bool _sameConnection(_OtaOperation op) =>
      op.epoch == _epoch &&
      _session.state.value.connected &&
      _session.state.value.deviceId == op.id;
  void _check(_OtaOperation op) {
    if (op.failure != null) throw op.failure!;
    if (_disposed || !identical(_active, op)) {
      throw const _OtaFailure(
        OtaTransferErrorFamily.cancelled,
        'Update cancelled.',
      );
    }
    if (!_sameConnection(op)) {
      throw const _OtaFailure(
        OtaTransferErrorFamily.connection,
        'Speaker connection changed.',
      );
    }
  }

  void _stop(_OtaOperation op, _OtaFailure failure, {bool allowAbort = false}) {
    if (!identical(_active, op) || op.failure != null || op.succeeded) return;
    op.failure = failure;
    op.tryAbort =
        allowAbort &&
        op.wrote &&
        !op.verifying &&
        !op.attPending &&
        _sameConnection(op);
    for (final listener in List.of(op.cancelListeners)) {
      listener(failure);
    }
    if (!op.tryAbort) _disconnect(op);
  }

  void _disconnect(_OtaOperation op) {
    if (!op.wrote || op.succeeded || op.disconnect != null) return;
    _blockedEpoch = op.epoch;
    // Scope cleanup to the original ready epoch, never a newly selected device.
    op.disconnect = _sameConnection(op)
        ? _session.disconnect().catchError((_) {})
        : Future<void>.value();
  }

  void _sessionChanged() {
    if (_disposed) return;
    final current = _session.state.value;
    if (current.connected == _connected && current.deviceId == _deviceId) {
      return;
    }
    _epoch++;
    _connected = current.connected;
    _deviceId = current.deviceId;
    if (_receipt != null &&
        (!current.connected || current.deviceId != _receipt!.id)) {
      _receipt!.lostConnection = true;
    }
    final op = _active;
    if (op != null) {
      _stop(
        op,
        const _OtaFailure(
          OtaTransferErrorFamily.connection,
          'Speaker connection was lost or changed.',
        ),
      );
    }
    if (current.connected && _blockedEpoch != _epoch) _blockedEpoch = null;
    if (op == null && _receipt != null) {
      _state.value = _state.value.copyWith(
        message: canVerify
            ? 'Speaker reconnected. Read back its reported version.'
            : 'Transfer completion is recorded. Reconnect the original speaker for a reported-version check.',
      );
    }
  }

  void _emit(
    _OtaOperation op,
    OtaTransferPhase phase, {
    String? message,
    _OtaFailure? displayFailure,
  }) {
    if (_disposed || !identical(_active, op)) return;
    final failure = op.failure ?? displayFailure;
    _state.value = OtaTransferState(
      phase: phase,
      totalBytes: op.image.sizeBytes,
      attCompletedBytes: op.attCompletedBytes,
      targetDeviceId: op.id,
      expectedVersion: op.expected,
      reportedVersion: op.reportedVersion,
      imageSha256: op.image.sha256Hex,
      reportedProgress: op.reportedProgress,
      message: message ?? failure?.message,
      errorFamily: failure?.family,
      errorCode: failure?.code,
      requiresReconnect: op.failure != null && op.wrote,
      abortConfirmed: op.abortConfirmed,
      transferConfirmed:
          op.verifying ||
          (op.succeeded && op.successResult == OtaTransferResult.transferred),
    );
  }

  Future<void> cancel() async {
    final op = _active;
    if (op == null) return;
    if (!op.succeeded) {
      _stop(
        op,
        const _OtaFailure(
          OtaTransferErrorFamily.cancelled,
          'Update cancelled. Reconnect before trying again. Cancellation does not verify rollback.',
        ),
        allowAbort: true,
      );
    }
    await op.finished.future;
  }

  Future<void> onAudioDisconnected() => cancel();
  void dispose() {
    if (_disposed) return;
    final op = _active;
    if (op != null) {
      _stop(
        op,
        const _OtaFailure(
          OtaTransferErrorFamily.cancelled,
          'Update operation cancelled.',
        ),
      );
      op.tryAbort = false;
      _disconnect(op);
    }
    _disposed = true;
    _session.state.removeListener(_sessionChanged);
    _state.dispose();
  }
}

class _OtaOperation {
  _OtaOperation(
    this.epoch,
    this.id,
    this.image,
    this.expected, {
    this.verifying = false,
  });
  final int epoch;
  final String id, expected;
  final FirmwareImage image;
  final bool verifying;
  // Exactly one cancellable packet listener; completed packets do not build up
  // Future.any listeners across a multi-megabyte transfer.
  final cancelListeners = <void Function(_OtaFailure)>{};
  final issuedCommands = <int>{};
  final finished = Completer<void>();
  int attCompletedBytes = 0;
  int? reportedProgress;
  String? reportedVersion;
  bool wrote = false,
      attPending = false,
      tryAbort = false,
      abortConfirmed = false,
      succeeded = false;
  _OtaFailure? failure;
  OtaTransferResult? successResult;
  _OtaWindow? window;
  Future<void>? disconnect;
  Timer? deadline;
  StreamSubscription<ProtocolEvent>? subscription;
}

class _OtaReceipt {
  _OtaReceipt(this.epoch, this.id, this.image, this.expected);
  final int epoch;
  final String id, expected;
  final FirmwareImage image;
  bool lostConnection = false;
  String? reportedVersion;
}

class _OtaWindow {
  _OtaWindow(this.command, this.accepts, {this.isAbort = false});
  final int command;
  final bool Function(ProtocolEvent)? accepts;
  final bool isAbort;
  final reply = Completer<ProtocolEvent>();
}

class _OtaFailure implements Exception {
  const _OtaFailure(this.family, this.message, {this.code});
  final OtaTransferErrorFamily family;
  final String message;
  final int? code;
  @override
  String toString() => message;
}
