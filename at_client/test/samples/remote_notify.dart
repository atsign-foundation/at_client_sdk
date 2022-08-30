import 'dart:io';
import 'package:at_client/at_client.dart';
import 'test_util.dart';

void main() async {
  try {
    final atsign = '@alice';
    final preference = TestUtil.getAlicePreference();
    await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);

    var i = 0;
    while (true) {
      // Notifications sending from client-1
      var result = await AtClientManager.getInstance()
          .notificationService
          .notify(
              NotificationParams.forText('hello from client-1-$i', '@bob',
                  strategyEnum: StrategyEnum.latest, notifier: 'client-1'),
              checkForFinalDeliveryStatus: false);
      print(result);
      // Notifications sending from client-2
      var result1 = await AtClientManager.getInstance()
          .notificationService
          .notify(
              NotificationParams.forText('hi from client-2-$i', '@murali',
                  strategyEnum: StrategyEnum.all, notifier: 'client-2'),
              checkForFinalDeliveryStatus: false);

      i = i + 1;
      print(result1);
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
