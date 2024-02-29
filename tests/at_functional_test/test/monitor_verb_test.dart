/// Objective:
/// --------------
/// The objective is to quantify the latency encountered by each "atClient" when subjecting the server to different
/// loads through the simultaneous involvement of "M" instances of parallel atClients listening to "N" notifications.

/// Measurement Criteria:
/// ---------------------
/// Duration it takes for an atClient to receive expected number of notifications from the server

/// Preconditions:
/// --------------
/// 1. SetUp required encryption keys
/// 2. Initialize atClientManager and set preferences
/// NOTE : Atsign, HiveStoragePath and commitLog path are passed a arguments
/// 3. Setup server with configured number of notifications
/// NOTE: Here notifications being setUp are selfNotifications of notificationType key

/// Input Parameters:
/// ------------
/// - atSign - atSign against which the tests will be performed
/// - hiveStorageDir - path for hive storage
/// - commitLogStorageDir - path for commitLog storage
///  NOTE: The [commitLogStorageDir] and [hiveStorageDir] varies for each client

/// Expected Server Conditions:
/// ---------------------------
/// Resource Allocation: The server is expected to allocate its entire resource capacity exclusively to the
/// designated operation under scrutiny. server is not expected to be running any other operations
/// Monitor:
/// The server is expected to have monitors running from each connected client.

// Expected AtClient Conditions:
// -----------------------------
// - Test code will be creating an instance of notitificationService by virtue of atClientManager and use it to subscrive and listen to 'N' number of notitifications
// - atClient will be running a monitor that will be subscribed to listen to the incoming notifications matching the regex

import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:test/test.dart';

class InputParameters {
  late String atSign;
  late String hiveStorageDir;
  late String commitLogStorageDir;
}

Future<void> main(List<String> arguments) async {
  late AtClientManager atClientManager;
  var inputParameters = InputParameters();
  inputParameters.atSign = arguments[0];
// picks the storage path from the command line args
  inputParameters.hiveStorageDir = arguments[1];
  inputParameters.commitLogStorageDir = arguments[2];
  String namespace = 'loadtest';
  AtClientPreference? preference;

  preference =
      getPreference(inputParameters.atSign, arguments[1], arguments[2]);

// sets up the required encryption keys
  setUp(() async {
    final encryptionKeysLoader = AtEncryptionKeysLoader.getInstance();
    atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        inputParameters.atSign, namespace, preference!,
        atChops: encryptionKeysLoader
            .createAtChopsFromDemoKeys(inputParameters.atSign));
// To setup encryption keys
    await encryptionKeysLoader.setEncryptionKeys(
        atClientManager.atClient, inputParameters.atSign);
  });

  test('monitor listening to notification', () async {
    var startTime = DateTime.now().millisecondsSinceEpoch;
    int i = 0;
    // wait for listen method till all the 100 notifications are received
    atClientManager.atClient.notificationService
        .subscribe(regex: namespace)
        .listen(expectAsync1((loadTestNotification) {
          i++;
          if (i == 99) {
            var endTime = DateTime.now().millisecondsSinceEpoch;
            var timeDifferenceValue =
                DateTime.fromMillisecondsSinceEpoch(endTime)
                    .difference(DateTime.fromMillisecondsSinceEpoch(startTime));
            Map<String, dynamic> resultsList = {
              "startTime": startTime,
              "endTime": endTime,
              "timeDifference": timeDifferenceValue.inMilliseconds
            };
            var jsonData = jsonEncode(resultsList);
            print(jsonData);
          }
        }, count: 100, max: 0));
  }, timeout: Timeout(Duration(minutes: 10)));

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
