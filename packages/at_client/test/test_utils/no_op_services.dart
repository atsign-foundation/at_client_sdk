import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/service/sync_service.dart';

class ServiceFactoryWithNoOpServices extends DefaultAtServiceFactory {
  @override
  Future<SyncService> syncService(AtClient atClient, AtClientManager atClientManager, NotificationService notificationService) async {
    return NoOpSyncService();
  }
  @override
  Future<NotificationService> notificationService(
      AtClient atClient, AtClientManager atClientManager) async {
    return NoOpNotificationService();
  }
}

class NoOpNotificationService implements NotificationService {
  @override
  Future<AtNotification> fetch(String notificationId) {
    // TODO: implement fetch
    throw UnimplementedError();
  }

  @override
  Future<NotificationResult> getStatus(String notificationId) {
    // TODO: implement getStatus
    throw UnimplementedError();
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams, {bool waitForFinalDeliveryStatus = true, bool checkForFinalDeliveryStatus = true, Function(NotificationResult p1)? onSuccess, Function(NotificationResult p1)? onError, Function(NotificationResult p1)? onSentToSecondary}) {
    // TODO: implement notify
    throw UnimplementedError();
  }

  @override
  void stopAllSubscriptions() {
    // TODO: implement stopAllSubscriptions
  }

  @override
  Stream<AtNotification> subscribe({String? regex, bool shouldDecrypt = true}) {
    // TODO: implement subscribe
    throw UnimplementedError();
  }

}

class NoOpSyncService implements SyncService {
  @override
  void addProgressListener(SyncProgressListener listener) {}

  @override
  Future<bool> isInSync() async => false;

  @override
  bool get isSyncInProgress => false;

  @override
  void removeAllProgressListeners() {}

  @override
  void removeProgressListener(SyncProgressListener listener) {}

  @override
  void setOnDone(Function onDone) {}

  @override
  void sync({Function? onDone, Function? onError}) {}

}