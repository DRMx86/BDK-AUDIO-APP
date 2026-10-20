import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/speaker_state.dart';
import '../protocol/speaker_protocol.dart';
import 'ble_transport.dart';

class SpeakerSession {
  SpeakerSession(
    this.transport, {
    this.operationTimeout = const Duration(seconds: 12),
    this.syncTimeout = const Duration(seconds: 5),
    this.ackTimeout = const Duration(seconds: 3),
  }) {
    _scanSubscription = transport.scanResults.listen(
      _onDiscovered,
      onError: _scanFailed,
    );
  }
  final BleTransport transport;
  final Duration operationTimeout, syncTimeout, ackTimeout;
  final state = ValueNotifier(const SpeakerState());
  final devices = ValueNotifier<List<DiscoveredSpeaker>>([]);
  final _responses = StreamController<ProtocolEvent>.broadcast(sync: true);
  Stream<ProtocolEvent> get responses => _responses.stream;
  late final StreamSubscription<DiscoveredSpeaker> _scanSubscription;
  StreamSubscription<BleNotification>? _notifications;
  StreamSubscription<BleDisconnect>? _disconnects;
  BleLink? _link;
  Future<void>? _cleanup;
  bool _cleanupUncertain = false;

  /// A bounded native close failed or timed out. A fresh synchronized connection
  /// clears this flag; closing the logical session alone proves no native state.
  bool get cleanupUncertain => _cleanupUncertain;

  Completer<void>? _sync;
  Completer<ProtocolEvent>? _ack;
  _QueuedCommand? _active;
  final _queue = <_QueuedCommand>[];
  final _revisions = <String, int>{};
  final _acceptedFields = <String>{};
  int _generation = 0;
  int _scanGeneration = 0;
  bool _disposed = false, _pumping = false;
  bool _statusRequested = false;
  Object? _exclusiveToken;
  Completer<void>? _exclusiveCancellation;
  Timer? _scanDeadline;

  bool _current(int generation) => !_disposed && generation == _generation;
  void _checkAlive() {
    if (_disposed) throw StateError('Speaker session is disposed.');
  }

  void _onDiscovered(DiscoveredSpeaker device) {
    if (_disposed || state.value.phase != ConnectionPhase.scanning) return;
    final matchesService = device.services.any(
      (s) => s.toLowerCase() == SpeakerProtocol.service,
    );
    final matchesName = RegExp(
      r'^BDK(?:[\s_-]|$)',
      caseSensitive: false,
    ).hasMatch(device.name.trim());
    if (!matchesService && !matchesName) return;
    final next = [...devices.value];
    final index = next.indexWhere((d) => d.id == device.id);
    if (index < 0) {
      next.add(device);
    } else {
      next[index] = device;
    }
    devices.value = List.unmodifiable(next);
  }

  void _scanFailed(Object error) {
    if (_disposed || state.value.phase != ConnectionPhase.scanning) return;
    final generation = ++_scanGeneration;
    _scanDeadline?.cancel();
    _scanDeadline = null;
    final previous = _cleanup;
    final cleanup = () async {
      // Publish this cleanup tail before the error state. A replacement scan or
      // connection must not race a late stop of this continuous native scan.
      try {
        await previous;
      } catch (_) {
        // Still attempt to stop scanning if an earlier link cleanup failed.
      }
      try {
        await transport.stopScan().timeout(operationTimeout);
      } catch (stopError) {
        _cleanupUncertain = true;
        if (!_disposed && generation == _scanGeneration) {
          state.value = state.value.copyWith(
            message:
                'Speaker scan failed: $error. Stopping discovery failed: $stopError',
          );
        }
        rethrow;
      }
    }();
    _cleanup = cleanup;
    cleanup.whenComplete(() {
      if (identical(_cleanup, cleanup)) _cleanup = null;
    }).ignore();
    state.value = state.value.copyWith(
      phase: ConnectionPhase.error,
      message: 'Speaker scan failed: $error. Check Bluetooth and permissions.',
    );
  }

  /// Continuous scans are owned by foreground setup and must be stopped by its
  /// cancellation/lifecycle gates. Other callers retain the bounded default.
  Future<void> scan({bool continuous = false}) async {
    _checkAlive();
    if (_link != null || state.value.phase == ConnectionPhase.connecting) {
      throw const SpeakerSessionException(
        'Disconnect the current speaker before scanning.',
      );
    }
    _scanDeadline?.cancel();
    _scanDeadline = null;
    devices.value = [];
    final scanGeneration = ++_scanGeneration;
    state.value = state.value.copyWith(
      phase: ConnectionPhase.scanning,
      clearMessage: true,
      clearMeter: true,
    );
    try {
      final cleanup = _cleanup;
      if (cleanup != null) {
        await cleanup;
        if (_disposed ||
            scanGeneration != _scanGeneration ||
            state.value.phase != ConnectionPhase.scanning) {
          return;
        }
      }
      final start = transport.startScan();
      unawaited(
        start
            .then((_) {
              // Some native scan starts finish after a stop/timeout. Stop that late
              // operation without reviving the UI or interfering with a newer scan.
              if (_disposed || state.value.phase != ConnectionPhase.scanning) {
                unawaited(
                  transport
                      .stopScan()
                      .timeout(operationTimeout)
                      .catchError((_) {}),
                );
              }
            })
            .catchError((_) {}),
      );
      await start.timeout(operationTimeout);
      if (_disposed ||
          scanGeneration != _scanGeneration ||
          state.value.phase != ConnectionPhase.scanning) {
        return;
      }
      _scanDeadline?.cancel();
      if (!continuous) {
        _scanDeadline = Timer(const Duration(seconds: 15), () {
          unawaited(stopScan().catchError((_) {}));
        });
      }
    } catch (error) {
      if (!_disposed &&
          scanGeneration == _scanGeneration &&
          state.value.phase == ConnectionPhase.scanning) {
        state.value = state.value.copyWith(
          phase: ConnectionPhase.error,
          message:
              'Speaker scan failed: $error. Check Bluetooth and permissions.',
        );
      }
      rethrow;
    }
  }

  Future<void> stopScan() async {
    _checkAlive();
    ++_scanGeneration;
    _scanDeadline?.cancel();
    if (!_disposed && state.value.phase == ConnectionPhase.scanning) {
      state.value = state.value.copyWith(
        phase: ConnectionPhase.disconnected,
        clearMessage: true,
      );
    }
    await transport.stopScan().timeout(operationTimeout);
  }

  Future<void> connect(String id) async {
    _checkAlive();
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Select a speaker first.');
    }
    final generation = ++_generation;
    await _detach(const SpeakerSessionException('Connection replaced.'));
    if (!_current(generation)) {
      throw const SpeakerSessionException('Connection replaced.');
    }
    BleLink? connected;
    try {
      await stopScan();
      if (!_current(generation)) {
        throw const SpeakerSessionException('Connection replaced.');
      }
      final names = devices.value.where((d) => d.id == id);
      state.value = SpeakerState(
        phase: ConnectionPhase.connecting,
        deviceId: id,
        name: names.isEmpty ? 'BDK speaker' : names.first.name,
        message: 'Connecting to speaker…',
      );
      final pending = transport.connect(id);
      // A timeout cannot cancel every native API; close a late result rather
      // than allowing it to become a second live controller.
      unawaited(
        pending
            .then((lateLink) {
              if (!_current(generation)) unawaited(_closeLink(lateLink));
            })
            .catchError((_) {}),
      );
      connected = await pending.timeout(operationTimeout);
      if (!_current(generation)) {
        throw const SpeakerSessionException('Connection replaced.');
      }
      if (connected.deviceId != id) {
        throw const SpeakerSessionException(
          'Bluetooth returned a different device; select the speaker again.',
        );
      }
      _link = connected;
      // The parser accepts at most 31 name + 64 firmware bytes. Legacy F0 has
      // no fragment envelope; its largest valid packet must fit one attribute.
      if (connected.writeCapacity < 113) {
        throw SpeakerSessionException(
          'BLE capacity ${connected.writeCapacity} bytes is too small for safe unframed status. Reconnect with a larger MTU or use firmware with negotiated framing.',
        );
      }
      _acceptedFields.clear();
      _revisions.clear();
      final sync = _sync = Completer<void>();
      sync.future.ignore();
      _statusRequested = false;
      _notifications = connected.notifications.listen(
        (event) {
          if (_current(generation)) _onNotification(event);
        },
        onError: (Object error) {
          if (_current(generation)) {
            unawaited(
              _failLink(
                'Bluetooth notification failed: $error. Reconnect the speaker.',
              ),
            );
          }
        },
      );
      _disconnects = connected.disconnects.listen(
        (event) {
          if (_current(generation)) {
            final raw = event.nativeCode == null
                ? ''
                : ' (native ${event.nativeCode})';
            unawaited(
              _failLink(
                'Speaker disconnected: ${event.reason ?? 'Bluetooth link lost'}$raw. Reconnect the speaker.',
              ),
            );
          }
        },
        onError: (Object error) {
          if (_current(generation)) {
            unawaited(
              _failLink(
                'Bluetooth connection failed: $error. Reconnect the speaker.',
              ),
            );
          }
        },
      );
      state.value = state.value.copyWith(
        phase: ConnectionPhase.synchronizing,
        writeCapacity: connected.writeCapacity,
        message: 'Reading speaker status…',
      );
      await connected
          .subscribe(SpeakerProtocol.status)
          .timeout(operationTimeout);
      if (!_current(generation)) {
        throw const SpeakerSessionException('Connection interrupted.');
      }
      await connected
          .subscribe(SpeakerProtocol.meterCharacteristic)
          .timeout(operationTimeout);
      if (!_current(generation)) {
        throw const SpeakerSessionException('Connection interrupted.');
      }
      _statusRequested = true;
      await connected
          .write(SpeakerProtocol.requestStatus())
          .timeout(operationTimeout);
      await sync.future.timeout(
        syncTimeout,
        onTimeout: () {
          throw const SpeakerSessionException(
            'Complete speaker status timed out. Reconnect; the firmware may need a framed-status update.',
          );
        },
      );
      if (!_current(generation)) {
        throw const SpeakerSessionException('Connection interrupted.');
      }
      _sync = null;
    } catch (error) {
      if (_current(generation)) {
        if (error is BleTransportException && error.cleanupUncertain) {
          _cleanupUncertain = true;
        }
        await _failLink('Could not synchronize speaker status: $error');
      } else if (connected != null && !identical(connected, _link)) {
        unawaited(_closeLink(connected));
      }
      rethrow;
    }
  }

  void _onNotification(BleNotification notification) {
    try {
      if (notification.characteristic.toLowerCase() ==
          SpeakerProtocol.meterCharacteristic) {
        if (state.value.phase == ConnectionPhase.ready) {
          state.value = state.value.copyWith(
            meter: SpeakerProtocol.meter(notification.value, DateTime.now()),
          );
        }
        return;
      }
      if (notification.characteristic.toLowerCase() != SpeakerProtocol.status) {
        return;
      }
      final event = SpeakerProtocol.parse(notification.value);
      _responses.add(event);
      if ((event.id == 0x10 || event.id == 0x11) &&
          event.commandId == _active?.bytes.first) {
        if (!(_ack?.isCompleted ?? true)) _ack!.complete(event);
        return;
      }
      if (event.fullStatus) {
        if (state.value.phase == ConnectionPhase.synchronizing &&
            _statusRequested) {
          _cleanupUncertain = false;
          state.value = event
              .apply(state.value)
              .copyWith(
                phase: ConnectionPhase.ready,
                message: 'Connected to your speaker.',
              );
          if (!(_sync?.isCompleted ?? true)) _sync!.complete();
        } else if (state.value.phase == ConnectionPhase.ready) {
          final previous = state.value;
          var updated = event.apply(previous);
          if (_acceptedFields.contains('eq')) {
            updated = updated.copyWith(eq: previous.eq);
          }
          if (_acceptedFields.contains('led')) {
            updated = updated.copyWith(led: previous.led);
          }
          if (_acceptedFields.contains('control')) {
            updated = updated.copyWith(controlFlags: previous.controlFlags);
          }
          if (_acceptedFields.contains('name')) {
            updated = updated.copyWith(name: previous.name);
          }
          state.value = updated;
        }
      } else if (state.value.phase == ConnectionPhase.ready) {
        final field = switch (event.id) {
          1 => 'eq',
          2 => 'control',
          3 => 'name',
          5 => 'led',
          _ => null,
        };
        if (field != null) {
          _revisions[field] = (_revisions[field] ?? 0) + 1;
          _acceptedFields.remove(field);
        }
        state.value = event.apply(state.value);
      }
    } on FormatException catch (error) {
      // Reject the entire notification. Never accumulate unframed fragments or
      // turn a truncated sync into a usable session.
      state.value = state.value.copyWith(
        message:
            'Ignored malformed speaker status: ${error.message}. Waiting for a complete valid packet.',
      );
    }
  }

  Future<void> setEq(EqGains eq) => _enqueue(
    'eq',
    'EQ',
    SpeakerProtocol.setEq(eq),
    (s) => s.copyWith(eq: eq),
  );
  Future<void> setLed(LedSettings led) {
    if (_exclusiveToken == null &&
        state.value.connected &&
        state.value.led == led &&
        _active?.key != 'led' &&
        !_queue.any((c) => c.key == 'led')) {
      return Future.value();
    }
    return _enqueue(
      'led',
      'lighting',
      SpeakerProtocol.setLed(led),
      (s) => s.copyWith(led: led),
    );
  }

  Future<void> setControl(int flags) {
    RangeError.checkValueInInterval(flags, 0, 255, 'flags');
    final preserved = (state.value.controlFlags & 0xf8) | (flags & 7);
    return _enqueue(
      'control',
      'sound options',
      SpeakerProtocol.setControl(preserved),
      (s) => s.copyWith(controlFlags: preserved),
    );
  }

  Future<void> rename(String name) => _enqueue(
    'name',
    'speaker name',
    SpeakerProtocol.rename(name),
    (s) => s.copyWith(name: name.trim()),
  );

  /// Reserve the command characteristic for a sound/OTA transaction. Raw writes
  /// report ATT completion only; the action owns its response-family state
  /// machine and deadlines. Packets are never retried here.
  Future<T> withExclusiveWriter<T>(
    Future<T> Function(SessionWriter) action,
  ) async {
    _checkAlive();
    if (!state.value.connected || _link == null) {
      throw const SpeakerSessionException(
        'Connect and synchronize the speaker before starting a transfer.',
      );
    }
    if (_exclusiveToken != null || _pumping || _queue.isNotEmpty) {
      throw const SpeakerSessionException(
        'Speaker writes are busy. Finish the current setting or transfer first.',
      );
    }
    final generation = _generation;
    final token = _exclusiveToken = Object();
    final cancelled = _exclusiveCancellation = Completer<void>();
    cancelled.future.ignore();
    final writer = SessionWriter._((packet, withResponse) async {
      if (!_current(generation) ||
          !identical(_exclusiveToken, token) ||
          _link == null ||
          !state.value.connected) {
        throw const SpeakerSessionException(
          'Transfer connection or writer lease is no longer active.',
        );
      }
      if (packet.isEmpty || packet.length > _link!.writeCapacity) {
        throw SpeakerSessionException(
          'Transfer packet needs ${packet.length} bytes; BLE capacity is ${_link!.writeCapacity}.',
        );
      }
      try {
        await Future.any<void>([
          _link!
              .write(packet, withResponse: withResponse)
              .timeout(operationTimeout),
          cancelled.future,
        ]);
        if (!_current(generation) || !identical(_exclusiveToken, token)) {
          throw const SpeakerSessionException(
            'Transfer connection interrupted.',
          );
        }
      } catch (error) {
        if (_current(generation)) {
          await _failLink(
            'Transfer write failed: $error. Reconnect and start a fresh transfer.',
          );
        }
        rethrow;
      }
    });
    try {
      return await Future.any<T>([
        Future<T>.sync(() => action(writer)),
        cancelled.future.then<T>(
          (_) => throw const SpeakerSessionException('Transfer cancelled.'),
        ),
      ]);
    } finally {
      await writer._finish();
      if (identical(_exclusiveToken, token)) {
        _exclusiveToken = null;
        _exclusiveCancellation = null;
      }
    }
  }

  Future<void> _enqueue(
    String key,
    String label,
    Uint8List bytes,
    SpeakerState Function(SpeakerState) apply,
  ) {
    _checkAlive();
    if (!state.value.connected || _link == null) {
      return Future.error(
        const SpeakerSessionException(
          'Connect and synchronize the speaker before changing settings.',
        ),
      );
    }
    if (_exclusiveToken != null) {
      return Future.error(
        const SpeakerSessionException(
          'A speaker transfer is active. Finish or cancel it before changing settings.',
        ),
      );
    }
    final waiter = Completer<void>();
    waiter.future.ignore();
    final pending = _queue.where((c) => c.key == key);
    if (pending.isEmpty) {
      _queue.add(_QueuedCommand(key, label, bytes, apply, [waiter]));
    } else {
      final existing = pending.first;
      existing.bytes = bytes;
      existing.apply = apply;
      existing.waiters.add(waiter);
    }
    if (!_pumping) unawaited(_pump(_generation));
    return waiter.future;
  }

  Future<void> _pump(int generation) async {
    _pumping = true;
    try {
      while (_current(generation) && _queue.isNotEmpty && _link != null) {
        final command = _queue.removeAt(0);
        _active = command;
        if (command.key == 'control') {
          final preserved =
              (state.value.controlFlags & 0xf8) | (command.bytes[1] & 7);
          command.bytes = SpeakerProtocol.setControl(preserved);
          command.apply = (s) => s.copyWith(controlFlags: preserved);
        }
        if (command.key == 'led') {
          // Compare at dispatch: a previous queued effect change may have been
          // accepted or refused. Brightness alone must not reset the effect.
          final desired = command.apply(state.value).led;
          if (state.value.led.copyWith(brightness: desired.brightness) ==
              desired) {
            command.bytes = SpeakerProtocol.setLedBrightness(
              desired.brightness,
            );
          }
        }
        final revision = _revisions[command.key] ?? 0;
        final ack = _ack = Completer<ProtocolEvent>();
        ack.future.ignore();
        state.value = state.value.copyWith(
          message: 'Updating ${command.label}…',
        );
        try {
          if (command.bytes.length > _link!.writeCapacity) {
            throw const SpeakerSessionException(
              'Command exceeds negotiated BLE capacity.',
            );
          }
          await _link!.write(command.bytes).timeout(operationTimeout);
          final response = await ack.future.timeout(
            ackTimeout,
            onTimeout: () {
              throw const SpeakerSessionException(
                'The speaker didn’t confirm the change. Reconnect and try again.',
              );
            },
          );
          if (!_current(generation)) {
            throw const SpeakerSessionException('Connection interrupted.');
          }
          if (response.id == 0x11) {
            final error = _CommandRefused(command.bytes.first, response.error!);
            state.value = state.value.copyWith(message: error.toString());
            command.fail(error);
          } else {
            if ((_revisions[command.key] ?? 0) == revision) {
              _acceptedFields.add(command.key);
              state.value = command
                  .apply(state.value)
                  .copyWith(message: 'Speaker accepted ${command.label}.');
            } else {
              state.value = state.value.copyWith(
                message: 'Speaker accepted ${command.label}.',
              );
            }
            command.complete();
          }
        } catch (error) {
          command.fail(error);
          if (_current(generation)) {
            await _failLink(
              'Speaker write failed: $error. Reconnect the speaker.',
            );
          }
        } finally {
          if (_current(generation)) {
            _active = null;
            _ack = null;
          }
        }
      }
    } finally {
      if (_current(generation)) _pumping = false;
    }
  }

  Future<void> _failLink(String message) async {
    if (_disposed) return;
    ++_generation;
    final cleanup = _detach(SpeakerSessionException(message));
    state.value = state.value.copyWith(
      phase: ConnectionPhase.error,
      message: message,
      clearMeter: true,
    );
    await cleanup;
  }

  Future<void> _closeLink(BleLink link) async {
    try {
      await link.disconnect().timeout(operationTimeout);
    } catch (error) {
      _cleanupUncertain = true;
      if (!_disposed) {
        state.value = state.value.copyWith(
          message:
              '${state.value.message ?? ''} BLE control session closed; native disconnect failed: $error. Check system Bluetooth settings before reconnecting.',
        );
      }
    }
    link.dispose();
  }

  Future<void> _detach(Object reason) {
    final link = _link;
    _link = null;
    final notifications = _notifications;
    final disconnects = _disconnects;
    _notifications = null;
    _disconnects = null;
    _statusRequested = false;
    if (!(_exclusiveCancellation?.isCompleted ?? true)) {
      _exclusiveCancellation!.completeError(reason);
    }
    if (!(_sync?.isCompleted ?? true)) _sync!.completeError(reason);
    _sync = null;
    if (!(_ack?.isCompleted ?? true)) _ack!.completeError(reason);
    _ack = null;
    _active?.fail(reason);
    _active = null;
    for (final command in _queue) {
      command.fail(reason);
    }
    _queue.clear();
    _pumping = false;
    // Publish the cleanup tail synchronously, before error/disconnected state
    // listeners can request another scan or connection. Even a detach with no
    // current link must wait for the previous owner's bounded native close.
    if (link != null || notifications != null || disconnects != null) {
      final cleanup = (_cleanup ?? Future<void>.value()).then((_) async {
        await notifications?.cancel();
        await disconnects?.cancel();
        if (link != null) await _closeLink(link);
      });
      _cleanup = cleanup;
      cleanup.whenComplete(() {
        if (identical(_cleanup, cleanup)) _cleanup = null;
      }).ignore();
    }
    return _cleanup ?? Future<void>.value();
  }

  Future<void> disconnect() async {
    _checkAlive();
    ++_generation;
    ++_scanGeneration;
    _scanDeadline?.cancel();
    final cleanup = _detach(
      const SpeakerSessionException('Speaker disconnected.'),
    );
    state.value = SpeakerState(
      name: state.value.name,
      firmware: state.value.firmware,
      eq: state.value.eq,
      led: state.value.led,
      controlFlags: state.value.controlFlags,
      soundFlags: state.value.soundFlags,
      message: 'Disconnected.',
    );
    await cleanup;
    try {
      await transport.stopScan().timeout(operationTimeout);
    } catch (error) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          message: 'Session disconnected; stopping discovery failed: $error',
        );
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    ++_scanGeneration;
    _scanDeadline?.cancel();
    unawaited(_scanSubscription.cancel());
    unawaited(
      _detach(const SpeakerSessionException('Speaker session closed.')),
    );
    unawaited(_responses.close());
    transport.dispose();
    state.dispose();
    devices.dispose();
  }
}

class SpeakerSessionException implements Exception {
  const SpeakerSessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SessionWriter {
  SessionWriter._(this._write);
  final Future<void> Function(Uint8List, bool) _write;
  bool _busy = false;
  Future<void>? _pending;
  Future<void> write(Uint8List packet, {bool withResponse = true}) async {
    if (_busy) {
      throw const SpeakerSessionException(
        'Await the current transfer packet before writing another.',
      );
    }
    _busy = true;
    try {
      final pending = _pending = _write(
        Uint8List.fromList(packet),
        withResponse,
      );
      await pending;
    } finally {
      _pending = null;
      _busy = false;
    }
  }

  Future<void> _finish() async {
    try {
      await _pending;
    } catch (_) {
      /* The action observes the write error. */
    }
  }
}

class _CommandRefused extends SpeakerSessionException {
  _CommandRefused(int command, int error)
    : super(
        'Speaker refused command 0x${command.toRadixString(16).padLeft(2, '0')} with error 0x${error.toRadixString(16).padLeft(2, '0')}.',
      );
}

class _QueuedCommand {
  _QueuedCommand(this.key, this.label, this.bytes, this.apply, this.waiters);
  final String key, label;
  Uint8List bytes;
  SpeakerState Function(SpeakerState) apply;
  final List<Completer<void>> waiters;
  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void fail(Object error) {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }
}
