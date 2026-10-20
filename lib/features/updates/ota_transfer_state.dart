enum OtaTransferPhase {
  idle,
  starting,
  uploading,
  finishing,
  aborting,
  awaitingRestart,
  verifying,
  versionMatched,
  versionMismatch,
  verificationUnavailable,
  cancelled,
  failed,
  disabled,
}

enum OtaTransferResult {
  transferred,
  versionMatched,
  versionMismatch,
  verificationUnavailable,
  cancelled,
  failed,
  disabled,
  busy,
}

enum OtaTransferErrorFamily {
  validation,
  worker,
  command,
  timeout,
  connection,
  transport,
  cancelled,
  policy,
  verification,
}

class OtaTransferState {
  const OtaTransferState({
    this.phase = OtaTransferPhase.idle,
    this.totalBytes = 0,
    this.attCompletedBytes = 0,
    this.reportedProgress,
    this.targetDeviceId,
    this.expectedVersion,
    this.reportedVersion,
    this.imageSha256,
    this.message,
    this.errorFamily,
    this.errorCode,
    this.requiresReconnect = false,
    this.abortConfirmed = false,
    this.transferConfirmed = false,
  });
  final OtaTransferPhase phase;
  final int totalBytes, attCompletedBytes;
  final int? reportedProgress, errorCode;
  final String? targetDeviceId,
      expectedVersion,
      reportedVersion,
      imageSha256,
      message;
  final OtaTransferErrorFamily? errorFamily;
  final bool requiresReconnect, abortConfirmed, transferConfirmed;
  bool get busy => const [
    OtaTransferPhase.starting,
    OtaTransferPhase.uploading,
    OtaTransferPhase.finishing,
    OtaTransferPhase.aborting,
    OtaTransferPhase.verifying,
  ].contains(phase);
  double get progress => totalBytes == 0 ? 0 : attCompletedBytes / totalBytes;
  OtaTransferState copyWith({
    OtaTransferPhase? phase,
    String? message,
    bool? requiresReconnect,
    OtaTransferErrorFamily? errorFamily,
    bool clearErrorCode = false,
  }) => OtaTransferState(
    phase: phase ?? this.phase,
    totalBytes: totalBytes,
    attCompletedBytes: attCompletedBytes,
    reportedProgress: reportedProgress,
    targetDeviceId: targetDeviceId,
    expectedVersion: expectedVersion,
    reportedVersion: reportedVersion,
    imageSha256: imageSha256,
    message: message ?? this.message,
    errorFamily: errorFamily ?? this.errorFamily,
    errorCode: clearErrorCode ? null : errorCode,
    requiresReconnect: requiresReconnect ?? this.requiresReconnect,
    abortConfirmed: abortConfirmed,
    transferConfirmed: transferConfirmed,
  );
}
