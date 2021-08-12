import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';

import '../test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice🛠', 'wavi', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient('@alice🛠'));
    atClient!.getSyncManager()!.init('@alice🛠', TestUtil.getAlicePreference(),
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    if (atClient == null) {
      print('unable to create at client instance');
      return;
    }
    final notificationService = NotificationServiceImpl(atClient);
    notificationService.listen(_notificationCallback);
    print('closing monitor socket');
    notificationService.stop();
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('notification received: ${notification.toString()}');
}
