/// Objective:
/// --------------
/// The objective is to quantify the latency encountered by each "atClient" when subjecting the server to different
/// loads through the simultaneous involvement of "M" instances of parallel atClients  to put a specified number of keys ('n')and
/// complete synchronization, as sent from multiple clients

/// Measurement Criteria:
/// ---------------------
/// Duration it takes for an atClient to finish the sync of N keys created by each of the clients

/// Preconditions:
/// ---------------------
/// 1. SetUp required encryption keys
/// 2. Initialize atClientManager and set preferences
/// NOTE : Atsign, HiveStoragePath and commitLog path are passed a arguments

/// Input Parameters:
/// ---------------------
/// - noOfKeys - The number of keys that needs to be sent to the server
///  NOTE:  Keys being updated are unique self keys for each client
/// - atSign - atSign against which the tests will be performed
/// - hiveStorageDir - path for hive storage
/// - commitLogStorageDir - path for commitLog storage
///  NOTE: The [commitLogStorageDir] and [hiveStorageDir] varies for each client

/// Expected Server Conditions:
/// ---------------------------
/// Resource Allocation: The server is expected to allocate its entire resource capacity exclusively to the
/// designated operation under scrutiny. server is not expected to be running any other operations.

import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class InputParameters {
  static const noOfKeys = 100;
  late String atSign;
  late String hiveStorageDir;
  late String commitLogStorageDir;
}

Future<void> main(List<String> arguments) async {
  late AtClientManager atClientManager;
  InputParameters inputParameters = InputParameters();
  inputParameters.atSign = arguments[0];
  String namespace = 'wavi';
  AtClientPreference? preference;
  // picks the storage path from the command line args
  inputParameters.hiveStorageDir = arguments[1];
  inputParameters.commitLogStorageDir = arguments[2];

  var uuid = Uuid();

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

  test('parallel put test ', () async {
    for (var i = 1; i <= InputParameters.noOfKeys; i++) {
      // Generate  uuid
      var uniqueId = uuid.v4().hashCode;
      var usernameKey = AtKey()
        ..key = 'username$uniqueId'
        ..sharedWith = inputParameters.atSign
        ..namespace = namespace;
      var value = 'user123$i';

      var putResult = await atClientManager.atClient.put(usernameKey, value);
      expect(putResult, true);
    }
    // diff Test-  remove sync
    //Test2 -  directly to write to remote secondary
    // wait for all the keys to be synced
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
  tearDown(() async {
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
