// ignore_for_file: omit_local_variable_types, unused_local_variable
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:csv/csv.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

// Class contains configuration params that are used to run the assertions
class LatencyTestConfigParameters {
  // Configuration parameters used to assert the latency
  static const int maxExpectedLatencyInMillis = 1000;
  static const int maxAllowedOutliersCount = 4;
  static const int maxAllowedOutlierLatencyInMillis = 5000;
}

void main() {
  var firstAtsign, secondAtsign;
  AtSignLogger.root_level = 'finer';
  late AtClientManager firstAtsignClientManager;
  var namespace = 'wavi';

  setUpAll(() async {
    firstAtsign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    secondAtsign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    // Create atClient instance for firstAtsign
    firstAtsignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            firstAtsign, namespace, TestUtils.getPreference(firstAtsign));
    // Set Encryption Keys for firstAtsign
    await TestUtils.setEncryptionKeys(firstAtsign);
    var isSyncInProgress = true;
    firstAtsignClientManager.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });

  test('Listen to notification from sharedWith atSign', () async {
    int minLatency = 10000000;
    int maxLatency = 0;
    int cumulativeLatency = 0;
    int counter = 1;
    int networkRoundTripInMillis = 100;
    int outlierCount = 0;
    List<List<dynamic>> entriesList = [];
    List<dynamic> entry = [];
    File file = File(
        '/home/shaikirfan/Desktop/client_trunk/at_client_sdk/at_end2end_test/test/latencyWithoutSync.csv');
    // Setting firstAtsign atClient instance to context.
    // firstAtsign will listen the notification from the first atsign
    await AtClientManager.getInstance().setCurrentAtSign(
        firstAtsign, namespace, TestUtils.getPreference(firstAtsign));
    // Listening to the notification from the sender
    firstAtsignClientManager.notificationService
        .subscribe(regex: '##')
        .listen((notification) async {
      _notificationCallBack(notification);
      int nowTime = DateTime.now().millisecondsSinceEpoch;
      var sentKey = notification.key;
      var sentTimeFromKey = sentKey.substring(sentKey.indexOf('##') + 2);
      int sentTime = int.parse(sentTimeFromKey);
      int latency = (nowTime - sentTime) - networkRoundTripInMillis;
      print('latency $latency');
      minLatency = min(minLatency, latency);
      maxLatency = max(maxLatency, latency);
      cumulativeLatency = cumulativeLatency + latency;
      counter++;
      print('counter is $counter');
      entry = [counter, latency];
      entriesList.add(entry);
      if (latency > LatencyTestConfigParameters.maxExpectedLatencyInMillis &&
          latency <
              LatencyTestConfigParameters.maxAllowedOutlierLatencyInMillis) {
        outlierCount++;
        print('outlier count in if condition $outlierCount');
      }
      if (latency >
          LatencyTestConfigParameters.maxAllowedOutlierLatencyInMillis) {
        outlierCount = LatencyTestConfigParameters.maxAllowedOutliersCount;
        print('latency is greater than maxAllowedOutlierLatencyInMillis');
      }
      print(latency < LatencyTestConfigParameters.maxExpectedLatencyInMillis &&
          outlierCount < LatencyTestConfigParameters.maxAllowedOutliersCount);
      print('outlier count $outlierCount');
      //if outliers are not configured,
      //fail the test if atleast one of the notification exceeds LatencyTestConfigParameters.maxExpectedLatencyInMillis
      if (LatencyTestConfigParameters.maxAllowedOutliersCount <= 0) {
        assert(
            latency < LatencyTestConfigParameters.maxExpectedLatencyInMillis);
      }
      // If outliers are configured
      // fail the test when the outlierCount > LatencyTestConfigParameters.maxAllowedOutliersCount
      // and latency > LatencyTestConfigParameters.maxExpectedLatencyInMillis
      if (LatencyTestConfigParameters.maxAllowedOutliersCount > 0) {
        assert(latency <
                LatencyTestConfigParameters.maxExpectedLatencyInMillis ||
            outlierCount < LatencyTestConfigParameters.maxAllowedOutliersCount);
      }
      String csv = const ListToCsvConverter().convert(entriesList);
      file.openWrite();
      await file.writeAsString(csv);
    });
    await Future.delayed(Duration(minutes: 100));
  }, timeout: Timeout(Duration(days: 1)));

  tearDownAll(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}

void _notificationCallBack(AtNotification notification) {
  print('Notification received : $notification');
}
