import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'test_utils1.dart';

class LatencyTestConfigParameters {
  // Configuration parameters used to assert the latency
  static int MaxNoOfIterations = 300;
}

void main() {
  var firstAtsign, secondAtsign;
  AtSignLogger.root_level = 'finer';
  late AtClientManager secondAtsignClientManager;
  var namespace = 'wavi';

  setUpAll(() async {
    firstAtsign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    secondAtsign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    // Create atClient instance for atSign2
    secondAtsignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            secondAtsign, namespace, TestUtils.getPreference(secondAtsign));
    // Set Encryption Keys for secondAtsign
    await TestUtils.setEncryptionKeys(secondAtsign);
    var isSyncInProgress = true;
    secondAtsignClientManager.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });

  test(
      'Notify a text with Date and time as value to sharedWith atSign and listen for notification from sharedWith atSign',
      () async {
    for (var i = 1; i <= LatencyTestConfigParameters.MaxNoOfIterations; i++) {
      // Setting secondAtsign atClient instance to context.
      // Now the second atsign will send the notification to the first atsign
      secondAtsignClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(
              secondAtsign, namespace, TestUtils.getPreference(secondAtsign));
      var sentTimeInMilliS = DateTime.now().millisecondsSinceEpoch;
      final notificationResult =
          await secondAtsignClientManager.notificationService.notify(
              NotificationParams.forText(
                  'notification$i##$sentTimeInMilliS', firstAtsign),
              onSuccess: (successResult) {
        print('onSuccess Result : $successResult');
      });
      expect(notificationResult, isNotNull);
      expect(notificationResult.notificationStatusEnum,
          NotificationStatusEnum.delivered);
      await Future.delayed(Duration(milliseconds: 100));
    }
  }, timeout: Timeout(Duration(days: 1)));

  tearDownAll(() async {
    var isExists = await Directory('test1/hive').exists();
    if (isExists) {
      Directory('test1/hive/').deleteSync(recursive: true);
    }
  });
}
