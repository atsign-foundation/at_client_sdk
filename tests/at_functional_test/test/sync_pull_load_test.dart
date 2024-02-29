/// Objective:
/// --------------
/// The objective of this test is to measure the time taken by the server to complete the initial sync process,
/// as initiated by multiple clients. The test aims to evaluate the performance of the server under varying loads by
/// progressively increasing the number of clients.

/// Measurement Criteria:
/// ---------------------
/// Duration it takes for the client to finish initial sync(pull) of keys pre-loaded into the server as part of the setup

/// Preconditions:
/// --------------
/// 1. SetUp required encryption keys
/// 2. Initialize atClientManager and set preferences
/// NOTE : Atsign, HiveStoragePath and commitLog path are passed a arguments
/// 3. setup 1000 self keys in the server before starting the test

/// Input Parameters:
/// -----------------
/// - atSign - atSign against which the tests will be performed
/// - hiveStorageDir - path for hive storage
/// - commitLogStorageDir - path for commitLog storage
///
///  NOTE: The [commitLogStorageDir] and [hiveStorageDir] varies for each client

/// Expected Server Conditions:
/// ---------------------------
/// Resource Allocation: The server is expected to allocate its entire resource capacity exclusively to the
/// designated operation under scrutiny. server is not expected to be running any other operations.

// Expected AtClient Conditions:
// -----------------------------
// - Test code will be creating an instance of syncService by virtue of atClientManager and use it to sync 'N' number of keys

import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

class InputParameters {
  late String atSign;
  late String hiveStorageDir;
  late String commitLogStorageDir;
}

Future<void> main(List<String> arguments) async {
  InputParameters inputParameters = InputParameters();
  late AtClientManager atClientManager;
  // picks the atsign from the command line arguments, Which is passed as part of the process program
  inputParameters.atSign = arguments[0];
  String namespace = 'wavi';
  AtClientPreference? preference;
  // picks the storage path from the command line args
  inputParameters.hiveStorageDir = arguments[1];
  inputParameters.commitLogStorageDir = arguments[2];

  // arguments[1] - hiveStorage path passed as commandline argument
  // arguments[2]- commitLog path passed as a commandLine argument
  preference =
      getPreference(inputParameters.atSign, arguments[1], arguments[2]);

  // sets up the required encryption keys
  setUpAll(() async {
    final encryptionKeysLoader = AtEncryptionKeysLoader.getInstance();
    atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        inputParameters.atSign, namespace, preference!,
        atChops: encryptionKeysLoader
            .createAtChopsFromDemoKeys(inputParameters.atSign));
    // To setup encryption keys
    await encryptionKeysLoader.setEncryptionKeys(
        atClientManager.atClient, inputParameters.atSign);
  });

  var startTime = DateTime.now().millisecondsSinceEpoch;

  test('sync pull load test', () async {
    await FunctionalTestSyncService.getInstance()
        .syncData(atClientManager.atClient.syncService);
    var endTime = DateTime.now().millisecondsSinceEpoch;
    var timeDifferenceValue = DateTime.fromMillisecondsSinceEpoch(endTime)
        .difference(DateTime.fromMillisecondsSinceEpoch(startTime));
    Map<String, dynamic> resultsList = {
      "startTime": startTime,
      "endTime": endTime,
      "timeDifference": timeDifferenceValue.inMilliseconds
    };
    var jsonData = jsonEncode(resultsList);
    print(jsonData);
  }, timeout: Timeout(Duration(minutes: 10)));

  // clears the storage created after the test is completed
  tearDownAll(() async {
    await deleteStoragePath(inputParameters.hiveStorageDir);
    await deleteStoragePath(inputParameters.commitLogStorageDir);
    exit(1);
  });
}

Future<void> deleteStoragePath(String path) async {
  try {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
      print('Deleted $path');
    }
  } catch (e) {
    print('Error deleting $path: $e');
  }
}

AtClientPreference getPreference(
    String atsign, String hiveStoragePath, String commitLogPath) {
  var preference = AtClientPreference();
  preference.isLocalStoreRequired = true;
  preference.hiveStoragePath = hiveStoragePath;
  preference.commitLogPath = commitLogPath;
  preference.rootDomain = 'vip.ve.atsign.zone';
  preference.decryptPackets = false;
  preference.pathToCerts = 'test/testData/cert.pem';
  preference.tlsKeysSavePath = 'test/tlsKeysFile';
  return preference;
}
