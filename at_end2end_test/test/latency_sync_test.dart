import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:csv/csv.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

class LatencyTestConfigParameters {
  // Configuration parameters used to assert the latency
  static int MaxNoOfIterations = 50;
}

void main() {
  var currentAtSign;
  AtClientManager? currentAtSignClientManager;
  var namespace = 'wavi';
  AtSignLogger.root_level = 'finer';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];

    // Create atClient instance for currentAtSign
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // Set Encryption Keys for currentAtSign
    await TestUtils.setEncryptionKeys(currentAtSign);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });

  /// The purpose of this test verify the following:
  /// 1. Put method
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb
  test('Share a key to sharedWith atSign and lookup from sharedWith atSign',
      () async {
    var entriesList = <List<dynamic>>[];
    var entry = <dynamic>[];
    var file = File(
        '/home/shaikirfan/Desktop/client_trunk/at_client_sdk/at_end2end_test/test/syncLatencyWithSyncCall.csv');
    for (var i = 1; i <= LatencyTestConfigParameters.MaxNoOfIterations; i++) {
      var key = 'sampleKey';
      var sampleKey = AtKey()
        ..key = key
        ..metadata = (Metadata()..isPublic = true);
      var value = 'value$i';
      // Setting currentAtSign atClient instance to context.
      await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
      var putResult =
          await currentAtSignClientManager?.atClient.put(sampleKey, value);
      expect(putResult, true);
      var isSyncInProgress = true;
      currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
        isSyncInProgress = false;
      });
      while (isSyncInProgress) {
        await Future.delayed(Duration(milliseconds: 10));
      }
      var getResultFromClient =
          await currentAtSignClientManager?.atClient.get(sampleKey);
      expect(getResultFromClient?.value, value);
      print('getResult from client $getResultFromClient');
      var clientUpdatedTime = getResultFromClient!.metadata!.updatedAt;
      var clientUpdatedTimeInMills = clientUpdatedTime?.millisecondsSinceEpoch;
      print('clientCreatedTimeInMills $clientUpdatedTimeInMills');
      var getResultFromServer = await currentAtSignClientManager?.atClient
          .getRemoteSecondary()!
          .executeCommand('llookup:all:public:$key.wavi$currentAtSign\n',
              auth: true);
      print('get result from the server $getResultFromServer');
      assert(getResultFromServer!.contains('$value'));
      getResultFromServer = getResultFromServer!.replaceFirst('data:', '');
      var atValueMap = jsonDecode(getResultFromServer);
      var serverUpdatedTime = (atValueMap['metaData']['updatedAt']);
      var serverUpdatedTimeInMills =
          DateTime.parse(serverUpdatedTime).millisecondsSinceEpoch;
      var latency = serverUpdatedTimeInMills - clientUpdatedTimeInMills!;
      print('latency $latency');
      entry = [latency];
      entriesList.add(entry);
      var csv = const ListToCsvConverter().convert(entriesList);
      file.openWrite();
      await file.writeAsString(csv);
    }

    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 500)));

  tearDownAll(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}
