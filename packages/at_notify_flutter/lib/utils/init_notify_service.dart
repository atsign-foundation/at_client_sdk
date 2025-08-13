import 'package:at_client/at_client.dart';
import 'package:at_notify_flutter/services/notify_service.dart';
// ignore: import_of_legacy_library_into_null_safe

/// The notify service needs to be initialised.
/// It is expected that the app will first create an AtClientService instance using the preferences
/// and then use it to initialise the notify service.
void initializeNotifyService(AtClientManager atClientManager,
    String currentAtSign, AtClientPreference atClientPreference,
    {rootDomain = 'root.atsign.wtf', rootPort = 64}) {
  NotifyService().initNotifyService(
      atClientPreference, currentAtSign, rootDomain, rootPort);
}

void disposeNotifyControllers() {
  NotifyService().disposeControllers();
}
