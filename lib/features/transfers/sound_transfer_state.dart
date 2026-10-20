enum SoundTransferPhase {
  idle,
  starting,
  uploading,
  finishing,
  verifying,
  cancelling,
  completed,
  cancelled,
  failed,
  disabled,
}

enum SoundTransferOperation { upload, delete, mute }

enum SoundTransferResult { completed, cancelled, failed, disabled, busy }

enum SoundTransferErrorFamily {
  validation,
  worker,
  command,
  timeout,
  connection,
  transport,
  cancelled,
  policy,
}

class SoundTransferState {
  const SoundTransferState({
    this.phase = SoundTransferPhase.idle,
    this.operation,
    this.soundType,
    this.totalBytes = 0,
    this.acknowledgedBytes = 0,
    this.reportedProgress,
    this.message,
    this.errorFamily,
    this.errorCode,
    this.requiresReconnect = false,
    this.observedSoundFlags,
    this.uploadCompleted = false,
    this.presenceConfirmed = false,
    this.previousSoundMayBeLost = false,
  });
  final SoundTransferPhase phase;
  final SoundTransferOperation? operation;
  final int? soundType, reportedProgress, errorCode, observedSoundFlags;
  final int totalBytes, acknowledgedBytes;
  final String? message;
  final SoundTransferErrorFamily? errorFamily;
  final bool requiresReconnect, previousSoundMayBeLost;

  /// Worker COMPLETE and slot-presence readback are separate evidence.
  final bool uploadCompleted, presenceConfirmed;
  bool get busy => const [
    SoundTransferPhase.starting,
    SoundTransferPhase.uploading,
    SoundTransferPhase.finishing,
    SoundTransferPhase.verifying,
    SoundTransferPhase.cancelling,
  ].contains(phase);
  double get progress => totalBytes == 0 ? 0 : acknowledgedBytes / totalBytes;
}
