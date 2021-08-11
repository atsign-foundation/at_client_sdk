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
    await notificationService.init();
    notificationService.listen(_notificationCallback,regex: '.wavi');
//    Future.delayed(Duration(seconds: 5));
    print('stopping monitor');
    await notificationService.stop();
//    Future.delayed(Duration(seconds: 5));
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }

  print('end of test');
}

void _notificationCallback(AtNotification notification) {
  print('notification received: ${notification.toString()}');
}
