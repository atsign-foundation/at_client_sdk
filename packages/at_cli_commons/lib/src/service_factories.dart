import 'package:at_client/at_client.dart';

class ServiceFactoryWithNoOpSyncService extends DefaultAtServiceFactory {
  @override
  Future<SyncService> syncService(
      AtClient atClient,
      AtClientManager atClientManager,
      NotificationService notificationService) async {
    return NoOpSyncService();
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
