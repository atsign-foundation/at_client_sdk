import 'dart:async';

sealed class AtOnboardingStatusEvent {
  AtOnboardingStatus status;
  AtOnboardingStatusEvent(this.status);
}

/// The status of onboard's result
///
/// Values include: authSuccess, authFailed, activate, restoreBackup, syncToServer, serverNotReached, timeOut, pkamKeyNotFound, encryptionKeyNotFound, selfEncryptionKeyNotFound
///
enum AtOnboardingStatus {
  authSuccess,
  authFailed,
  activate,
  restoreBackup,
  syncToServer,
  serverNotReached, //implies teapot or atsign not found
  timeOut, // implies activated but stopped or unavailable
  pkamKeyNotFound,
  encryptionKeyNotFound,
  selfEncryptionKeyNotFound,
}

final class AtOnboardingStatusSuccess extends AtOnboardingStatusEvent {
  AtOnboardingStatusSuccess() : super(AtOnboardingStatus.authSuccess);
}

final class AtOnboardingStatusError extends AtOnboardingStatusEvent {
  String? message;
  String? errorCode;
  AtOnboardingStatusError(
      this.message,  AtOnboardingStatus status, {this.errorCode})
      : super(status);
}

final class AtOnboardingStatusCancelled extends AtOnboardingStatusEvent {
  AtOnboardingStatusCancelled() : super(AtOnboardingStatus.authFailed);
}

class AtOnboardingStatusStream {
  final _statusStreamController =
      StreamController<AtOnboardingStatusEvent>.broadcast();

  Stream<AtOnboardingStatusEvent> get stream => _statusStreamController.stream;

  void add(AtOnboardingStatusEvent event) {
    _statusStreamController.add(event);
  }

  void dispose() {
    _statusStreamController.close();
  }
}
