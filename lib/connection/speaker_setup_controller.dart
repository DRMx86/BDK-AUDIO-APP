import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/speaker_state.dart';
import '../platform/audio_connection_adapter.dart';
import '../protocol/speaker_protocol.dart';
import '../persistence/saved_speaker_store.dart';
import 'ble_transport.dart';
import 'speaker_session.dart';

/// Audio-first discovery. Codec permission/association is independent of this
/// gate; only the actual connected A2DP identity permits Android BLE candidates.
class SpeakerSetupController extends ChangeNotifier {
  SpeakerSetupController(
    this.session,
    this.adapter, {
    this.pollInterval = const Duration(seconds: 2),
    this.autoConnectEnabled = false,
    this.autoDiscoverEnabled = false,
    this.minimumDiscoveryTime = const Duration(seconds: 5),
    this.savedSpeakerStore,
    String? preferredAudioId,
    DateTime Function()? now,
  }) : selectedAudioId = preferredAudioId,
       _now = now ?? DateTime.now {
    session.state.addListener(_sessionChanged);
    session.devices.addListener(_devicesChanged);
  }
  final SpeakerSession session;
  final AudioConnectionAdapter adapter;
  final Duration pollInterval;
  final bool autoConnectEnabled;
  final bool autoDiscoverEnabled;
  final Duration minimumDiscoveryTime;
  final SavedSpeakerStore? savedSpeakerStore;
  final DateTime Function() _now;
  AudioConnectionSnapshot audio = const AudioConnectionSnapshot();
  String? selectedAudioId, message;
  String? _connectingAudioId;
  String? rememberWarning;
  SavedSpeaker? _savedSpeaker;
  bool _savedLoaded = false;
  Future<void>? _savedLoading;
  Timer? _autoTimer;
  Timer? _audioDiscoveryTimer, _discoveryWindowTimer;
  String? _completedDiscoveryCandidate;
  int _audioDiscoveryEpoch = 0;
  bool _audioDiscoveryActive = false,
      _audioDiscoveryCompleted = false,
      _readOnlyDiscoveryStarted = false,
      _discoveryWindowElapsed = false,
      _closingDiscovery = false;
  String? _autoCandidate, _autoAudioId;
  bool _autoSuppressed = false, _autoDriving = false, _autoStarted = false;
  int _autoRetries = 0;
  int? _searchRequest;
  bool _searchAutomatic = false, _connectionAutomatic = false;
  DateTime? _readyAt;
  Future<void>? _autoCleanup;
  bool loading = false,
      connecting = false,
      searchCompleted = false,
      manualAudioConfirmed = false;
  bool _disposed = false,
      _active = false,
      _wasSearching = false,
      _initialized = false;
  int _generation = 0;
  Timer? _poll;
  Future<void>? _refreshing;
  bool get searching => session.state.value.phase == ConnectionPhase.scanning;
  bool get checkingAudio => _active && (loading || _audioDiscoveryActive);
  bool get audioSearchCompleted => _audioDiscoveryCompleted;
  bool get preparingControls => _searchRequest != null;
  bool get audioReady =>
      !audio.permissionRequired &&
      (audio.canVerifyIdentity
          ? audio.devices.any((d) => _same(d.id, selectedAudioId))
          : manualAudioConfirmed);
  AudioDeviceIdentity? get selectedAudioDevice =>
      audio.devices.where((d) => _same(d.id, selectedAudioId)).firstOrNull;
  List<DiscoveredSpeaker> get controlDevices => !audioReady
      ? const []
      : session.devices.value
            .where(
              (d) =>
                  d.services.any(
                    (s) => s.toLowerCase() == SpeakerProtocol.service,
                  ) &&
                  (!audio.canVerifyIdentity || _same(d.id, selectedAudioId)),
            )
            .toList();
  bool _same(String? a, String? b) =>
      a != null && b != null && a.toLowerCase() == b.toLowerCase();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    _poll?.cancel();
    if (value) {
      _readOnlyDiscoveryStarted = false;
      if (autoDiscoverEnabled && !audioReady && !_autoSuppressed) {
        _beginAudioDiscovery();
      }
      unawaited(refresh());
      if (pollInterval > Duration.zero) {
        _poll = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
      }
    } else {
      _endAudioDiscovery();
      _clearDiscoveryWindow();
      _clearAutoTimer();
      _autoStarted = false;
      _autoRetries = 0;
      _readyAt = null;
      if (_autoDriving || searching || preparingControls || connecting) {
        ++_generation;
        _searchRequest = null;
        _searchAutomatic = false;
        final wasConnecting = connecting;
        final wasSearching = searching;
        if (wasConnecting) {
          connecting = false;
          _connectionAutomatic = false;
          _connectingAudioId = null;
        }
        unawaited(
          _queueCleanup(() async {
            if (wasConnecting) {
              await session.disconnect();
            } else if (wasSearching) {
              await session.stopScan();
            }
          }),
        );
      }
    }
  }

  /// A deliberate entry from Pair/Demo can restart discovery. Ordinary resume
  /// does not revoke the user's previous cancellation.
  void beginDiscovery() {
    if (_disposed) return;
    _resumeAutomatic();
    _readOnlyDiscoveryStarted = false;
    if (autoDiscoverEnabled && _active && !audioReady) {
      _beginAudioDiscovery();
    }
    _notify();
    if (_active) unawaited(refresh());
    _evaluateAuto();
  }

  void _beginAudioDiscovery() {
    _endAudioDiscovery();
    _audioDiscoveryCompleted = false;
    if (audio.permissionRequired || !audio.canVerifyIdentity) return;
    _audioDiscoveryActive = true;
    final epoch = _audioDiscoveryEpoch;
    _audioDiscoveryTimer = Timer(minimumDiscoveryTime, () {
      unawaited(() async {
        if (_disposed || !_active || epoch != _audioDiscoveryEpoch) return;
        // A fresh OS query ends the initial window; a cached empty snapshot is
        // insufficient to report that no audio speaker is available.
        final pending = _refreshing;
        if (pending != null) await pending;
        if (_disposed || !_active || epoch != _audioDiscoveryEpoch) return;
        await refresh();
        if (_disposed || !_active || epoch != _audioDiscoveryEpoch) return;
        _audioDiscoveryCompleted =
            !audioReady && audio.canVerifyIdentity && !audio.permissionRequired;
        // The first window reveals connection help; foreground OS polling
        // continues so connecting audio later needs no manual retry.
        _audioDiscoveryTimer = null;
        _notify();
      }());
    });
  }

  void _endAudioDiscovery() {
    ++_audioDiscoveryEpoch;
    _audioDiscoveryTimer?.cancel();
    _audioDiscoveryTimer = null;
    _audioDiscoveryActive = false;
  }

  void _clearDiscoveryWindow({bool clearCandidate = true}) {
    _discoveryWindowTimer?.cancel();
    _discoveryWindowTimer = null;
    _discoveryWindowElapsed = false;
    _closingDiscovery = false;
    if (clearCandidate) _completedDiscoveryCandidate = null;
  }

  void _armDiscoveryWindow(int generation) {
    if (!autoDiscoverEnabled || !searching) return;
    _discoveryWindowTimer = Timer(minimumDiscoveryTime, () {
      if (_disposed || !_active || generation != _generation || !searching) {
        return;
      }
      _discoveryWindowElapsed = true;
      _finishDiscoveryWindow();
    });
  }

  void _finishDiscoveryWindow() {
    if (!autoDiscoverEnabled ||
        !_active ||
        _disposed ||
        !searching ||
        _closingDiscovery ||
        !audioReady) {
      return;
    }
    final candidates = controlDevices;
    // A sole advertised-service candidate already matches the OS-verified
    // selected audio identity. The help timer adds no identity evidence here.
    // Empty/read-only/ambiguous discovery retains its existing exposure window.
    final verifiedCandidate = _canAuto && candidates.length == 1;
    if (!_discoveryWindowElapsed && !verifiedCandidate) return;
    if (candidates.isEmpty) {
      // Keep the real native scan running. The deadline now means that useful
      // connection help may appear, not that the speaker search has ended.
      if (!searchCompleted) {
        searchCompleted = true;
        _notify();
      }
      return;
    }
    _closingDiscovery = true;
    _clearAutoTimer();
    _completedDiscoveryCandidate = autoConnectEnabled && candidates.length == 1
        ? candidates.single.id
        : null;
    final generation = _generation;
    unawaited(
      _queueCleanup(() async {
        if (!_disposed && _active && generation == _generation && searching) {
          await session.stopScan();
        }
      }),
    );
  }

  void _evaluateReadOnlyDiscovery() {
    if (!autoDiscoverEnabled ||
        autoConnectEnabled ||
        !_active ||
        _disposed ||
        _autoSuppressed ||
        _readOnlyDiscoveryStarted ||
        session.cleanupUncertain ||
        !audio.canVerifyIdentity ||
        !audioReady ||
        loading ||
        searching ||
        connecting ||
        preparingControls ||
        session.state.value.connected ||
        _autoCleanup != null) {
      return;
    }
    _readOnlyDiscoveryStarted = true;
    unawaited(_searchControls(automatic: false));
  }

  Future<void> _loadSaved() {
    if (_savedLoaded) return Future<void>.value();
    return _savedLoading ??= () async {
      try {
        _savedSpeaker = await savedSpeakerStore?.load().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        rememberWarning =
            'Your saved speaker could not be read. Choose it again.';
      } finally {
        _savedLoaded = true;
      }
    }();
  }

  bool get _canAuto =>
      autoConnectEnabled &&
      _active &&
      !_disposed &&
      !_autoSuppressed &&
      !session.cleanupUncertain &&
      audio.canVerifyIdentity &&
      audioReady;

  void _clearAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoCandidate = null;
  }

  void _resumeAutomatic() {
    _clearAutoTimer();
    _autoSuppressed = false;
    _autoStarted = false;
    _autoRetries = 0;
  }

  void _evaluateAuto() {
    if (autoDiscoverEnabled && !autoConnectEnabled) {
      _evaluateReadOnlyDiscovery();
      return;
    }
    if (autoConnectEnabled &&
        _active &&
        !_autoSuppressed &&
        audioReady &&
        session.cleanupUncertain) {
      _clearAutoTimer();
      if (!connecting && !preparingControls) {
        const warning =
            'Bluetooth did not confirm disconnection. Choose your speaker to reconnect.';
        if (message != warning) {
          message = warning;
          _notify();
        }
      }
      return;
    }
    if (!_canAuto) {
      _clearAutoTimer();
      if (!audioReady) {
        _autoAudioId = null;
        _autoStarted = false;
        _autoRetries = 0;
      }
      return;
    }
    if (!_same(_autoAudioId, selectedAudioId)) {
      _clearAutoTimer();
      _autoAudioId = selectedAudioId;
      _autoRetries = 0;
      _autoStarted = false;
    }
    if (session.state.value.connected ||
        connecting ||
        _autoDriving ||
        _searchRequest != null ||
        _autoCleanup != null ||
        loading) {
      return;
    }
    if (_autoCandidate != null &&
        !controlDevices.any((d) => _same(d.id, _autoCandidate))) {
      _clearAutoTimer();
    }
    if (_autoTimer != null) return;
    final candidate =
        controlDevices.length == 1 &&
            (searching ||
                (autoDiscoverEnabled &&
                    _same(
                      _completedDiscoveryCandidate,
                      controlDevices.single.id,
                    )))
        ? controlDevices.single.id
        : null;
    if (searching && candidate == null) return;
    Duration delay;
    if (candidate != null) {
      delay = !autoDiscoverEnabled ? const Duration(seconds: 2) : Duration.zero;
    } else if (!_autoStarted) {
      delay = Duration.zero;
    } else {
      if (_autoRetries == 3) {
        message =
            'We couldn’t reconnect. Search again when your speaker is ready.';
        _notify();
        return;
      }
      delay = Duration(seconds: 2 << _autoRetries++);
    }
    final generation = _generation;
    final audioId = selectedAudioId;
    _autoCandidate = candidate;
    _autoTimer = Timer(delay, () {
      _autoTimer = null;
      _autoCandidate = null;
      if (!_canAuto ||
          generation != _generation ||
          !_same(audioId, selectedAudioId)) {
        return;
      }
      unawaited(_runAuto(candidate));
    });
  }

  Future<void> _runAuto(String? candidate) async {
    if (!_canAuto || _autoDriving || connecting || _autoCleanup != null) return;
    _autoDriving = true;
    _autoStarted = true;
    try {
      if (candidate == null) {
        await _searchControls(automatic: true);
      } else if (controlDevices.any((d) => _same(d.id, candidate))) {
        _completedDiscoveryCandidate = null;
        await _connectControls(candidate, automatic: true);
      }
    } finally {
      _autoDriving = false;
      _evaluateAuto();
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _queueCleanup(Future<void> Function() cleanup) {
    final previous = _autoCleanup ?? Future<void>.value();
    late final Future<void> tracked;
    tracked = previous
        .then((_) => cleanup())
        .catchError((_) {
          if (!_disposed) {
            _autoSuppressed = true;
            message =
                'We couldn’t finish disconnecting. Check Bluetooth and try again.';
            _notify();
          }
        })
        .whenComplete(() {
          if (identical(_autoCleanup, tracked)) {
            _autoCleanup = null;
            _evaluateAuto();
          }
        });
    _autoCleanup = tracked;
    return tracked;
  }

  Future<void> _recheckAudio(int generation) async {
    final cleanup = _autoCleanup;
    if (cleanup != null) await cleanup;
    if (_disposed || generation != _generation) return;
    // A poll already in flight can describe audio before this operation or
    // before FULL_STATUS. Drain it, then obtain a new OS snapshot.
    final pending = _refreshing;
    if (pending != null) await pending;
    if (_disposed || generation != _generation) return;
    await refresh();
  }

  Future<void> _refresh() async {
    if (!_initialized) {
      loading = true;
      _notify();
    }
    final wasReady = audioReady;
    try {
      await _loadSaved();
      if (_disposed) return;
      final next = await adapter.snapshot();
      if (_disposed) return;
      audio = next;
      if (audio.canVerifyIdentity) {
        if (!audio.devices.any((d) => _same(d.id, selectedAudioId))) {
          selectedAudioId = null;
        }
        if (selectedAudioId == null &&
            _savedSpeaker != null &&
            audio.devices.any((d) => _same(d.id, _savedSpeaker!.id))) {
          selectedAudioId = audio.devices
              .firstWhere((d) => _same(d.id, _savedSpeaker!.id))
              .id;
        }
        if (selectedAudioId == null &&
            audio.devices.length == 1 &&
            RegExp(
              r'^BDK(?:[\s_-]|$)',
              caseSensitive: false,
            ).hasMatch(audio.devices.single.name.trim())) {
          selectedAudioId = audio.devices.single.id;
        }
      }
      if (audioReady ||
          audio.permissionRequired ||
          !audio.canVerifyIdentity ||
          audio.devices.isNotEmpty) {
        // Polling continues, but verified choices must remain selectable when
        // several audio devices (or an unnamed device) need explicit selection.
        _audioDiscoveryCompleted = false;
        _endAudioDiscovery();
      }
      final changedAttempt =
          connecting &&
          audio.canVerifyIdentity &&
          (!_same(selectedAudioId, _connectingAudioId) ||
              !audio.devices.any((d) => _same(d.id, _connectingAudioId)));
      final changedReady =
          session.state.value.connected &&
          audio.canVerifyIdentity &&
          (!audioReady ||
              !_same(session.state.value.deviceId, selectedAudioId));
      if (changedAttempt || changedReady) {
        ++_generation;
        connecting = false;
        _connectingAudioId = null;
        await session.disconnect();
        message = 'The audio connection changed. Choose your speaker again.';
      }
      if (!audioReady) {
        _readOnlyDiscoveryStarted = false;
        _clearDiscoveryWindow();
        if (searching) await session.stopScan();
        if (connecting) {
          ++_generation;
          await session.disconnect();
          connecting = false;
          _connectingAudioId = null;
        }
        searchCompleted = false;
        message = audio.message;
        if (wasReady && autoDiscoverEnabled && _active && !_autoSuppressed) {
          _beginAudioDiscovery();
        }
      } else if (!wasReady && !searching && !connecting) {
        message = null;
      }
    } catch (_) {
      if (!_disposed) {
        _endAudioDiscovery();
        _clearDiscoveryWindow();
        // A failed OS check cannot authorize discovery or retain controls using
        // the last successful audio identity.
        audio = const AudioConnectionSnapshot();
        selectedAudioId = null;
        manualAudioConfirmed = false;
        ++_generation;
        final hadControls = connecting || session.state.value.connected;
        connecting = false;
        _connectingAudioId = null;
        if (hadControls) {
          await session.disconnect();
        } else if (searching) {
          await session.stopScan();
        }
        searchCompleted = false;
        message = 'We couldn’t check the audio connection. Try again.';
      }
    } finally {
      if (!_disposed) {
        _initialized = true;
        loading = false;
        _notify();
        _evaluateAuto();
      }
    }
  }

  void selectAudioDevice(String id) {
    if (_disposed || !audio.devices.any((d) => _same(d.id, id))) return;
    selectedAudioId = id;
    _clearAutoTimer();
    searchCompleted = false;
    message = null;
    _notify();
    _evaluateAuto();
  }

  void confirmManagedAudio() {
    if (_disposed || audio.canVerifyIdentity) return;
    manualAudioConfirmed = true;
    message = null;
    _notify();
  }

  Future<void> requestPermission() async {
    final generation = _generation;
    try {
      await adapter.requestPermission();
      if (_disposed || generation != _generation) return;
      await refresh();
      if (_disposed || generation != _generation) return;
      if (autoDiscoverEnabled && _active && !audio.permissionRequired) {
        beginDiscovery();
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      message =
          'Bluetooth access was not granted. You can try again in Settings.';
      _notify();
    }
  }

  Future<void> openBluetoothSettings() async {
    try {
      await adapter.openBluetoothSettings();
    } catch (error) {
      message = error is AudioConnectionException
          ? error.message
          : 'Open Bluetooth settings and connect your speaker for audio.';
      _notify();
    }
  }

  Future<void> searchControls() => _searchControls(automatic: false);

  Future<void> _searchControls({required bool automatic}) async {
    if (_disposed || _searchRequest != null || connecting) return;
    if (!automatic) _resumeAutomatic();
    _endAudioDiscovery();
    _clearDiscoveryWindow();
    _readOnlyDiscoveryStarted = true;
    final generation = ++_generation;
    _searchRequest = generation;
    _searchAutomatic = automatic;
    _notify();
    try {
      await _recheckAudio(generation);
      if (_disposed || generation != _generation || (automatic && !_canAuto)) {
        return;
      }
      _clearAutoTimer();
      if (!audioReady) {
        message =
            'Connect your speaker for Bluetooth audio first, then search for controls.';
        return;
      }
      if (session.state.value.connected) {
        message = 'Your speaker controls are already connected.';
        return;
      }
      searchCompleted = false;
      message = null;
      _autoStarted = true;
      await session.scan(continuous: autoDiscoverEnabled);
      if (!_disposed && generation == _generation && searching) {
        _armDiscoveryWindow(generation);
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        message =
            'We couldn’t search for speaker controls. Check Bluetooth access and try again.';
      }
    } finally {
      if (_searchRequest == generation) {
        _searchRequest = null;
        _searchAutomatic = false;
      }
      _notify();
      _evaluateAuto();
    }
  }

  Future<void> connectControls(String id) =>
      _connectControls(id, automatic: false);

  Future<void> _connectControls(String id, {required bool automatic}) async {
    if (_disposed || connecting) return;
    if (!automatic) _resumeAutomatic();
    _endAudioDiscovery();
    _clearDiscoveryWindow();
    _clearAutoTimer();
    final generation = ++_generation;
    _connectingAudioId = selectedAudioId;
    connecting = true;
    _connectionAutomatic = automatic;
    message = null;
    _notify();
    try {
      await _recheckAudio(generation);
      if (_disposed || generation != _generation || (automatic && !_canAuto)) {
        return;
      }
      if (!audioReady || !controlDevices.any((d) => _same(d.id, id))) {
        message =
            'Connect this speaker for Bluetooth audio first, then search again.';
        return;
      }
      await session.connect(id);
      // Audio may change while subscriptions/status synchronization are pending.
      // Keep the connecting screen until this final OS identity check completes.
      if (!_disposed && generation == _generation) {
        await _recheckAudio(generation);
      }
      if (!_disposed &&
          generation == _generation &&
          session.state.value.connected &&
          audioReady &&
          (!audio.canVerifyIdentity || _same(id, selectedAudioId))) {
        _autoStarted = true;
        _readyAt = _now();
        // Persistence is separate from synchronized controls and the final OS
        // audio-identity check. A slow preference write must not hold readiness.
        unawaited(
          _rememberSpeaker(
            generation,
            SavedSpeaker(
              session.state.value.deviceId!,
              session.state.value.name,
            ),
          ),
        );
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        message =
            session.state.value.message ??
            'We couldn’t connect to your speaker. Try again.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        connecting = false;
        _connectionAutomatic = false;
        _connectingAudioId = null;
        _notify();
        _evaluateAuto();
      }
    }
  }

  Future<void> _rememberSpeaker(int generation, SavedSpeaker remembered) async {
    try {
      await savedSpeakerStore
          ?.save(remembered)
          .timeout(const Duration(seconds: 3));
      if (!_disposed && generation == _generation) {
        _savedSpeaker = remembered;
        rememberWarning = null;
        _notify();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        rememberWarning =
            'Connected, but this speaker could not be remembered on this device.';
        _notify();
      }
    }
  }

  Future<void> cancel() async {
    _endAudioDiscovery();
    _clearDiscoveryWindow();
    _autoSuppressed = true;
    _clearAutoTimer();
    ++_generation;
    _searchRequest = null;
    _searchAutomatic = false;
    final wasSearching = searching, wasConnecting = connecting;
    connecting = false;
    _connectionAutomatic = false;
    _connectingAudioId = null;
    _notify();
    if (wasConnecting || wasSearching) {
      await _queueCleanup(() async {
        if (wasConnecting) {
          await session.disconnect();
        } else {
          await session.stopScan();
        }
      });
    } else {
      await _autoCleanup;
    }
  }

  Future<void> disconnectControls() async {
    await cancel();
    if (!_disposed && session.state.value.connected) {
      await _queueCleanup(session.disconnect);
    }
  }

  void _devicesChanged() {
    _finishDiscoveryWindow();
    _notify();
    _evaluateAuto();
  }

  void _sessionChanged() {
    if (!session.state.value.connected && _readyAt != null) {
      final age = _now().difference(_readyAt!);
      if (!age.isNegative && age >= const Duration(seconds: 30)) {
        _autoRetries = 0;
      }
      _readyAt = null;
    }
    if (session.cleanupUncertain &&
        ((_searchRequest != null && _searchAutomatic) ||
            (connecting && _connectionAutomatic))) {
      ++_generation;
      _searchRequest = null;
      _searchAutomatic = false;
      connecting = false;
      _connectionAutomatic = false;
      _connectingAudioId = null;
      _clearAutoTimer();
      // Invalidate Session's waiting operation synchronously, before its old
      // cleanup future releases. A timeout cannot admit an automatic retry.
      final stopped = session.disconnect();
      unawaited(_queueCleanup(() => stopped));
    }
    if (_wasSearching && !searching) {
      searchCompleted = true;
      _clearDiscoveryWindow(clearCandidate: false);
    }
    _wasSearching = searching;
    _notify();
    _evaluateAuto();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    _endAudioDiscovery();
    _clearDiscoveryWindow();
    _clearAutoTimer();
    session.state.removeListener(_sessionChanged);
    session.devices.removeListener(_devicesChanged);
    super.dispose();
  }
}
