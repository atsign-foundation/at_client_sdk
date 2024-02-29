/// Objective:
/// --------------
/// The objective is to quantify the latency encountered by each "atClient" when subjecting the server to different
/// loads through the simultaneous involvement of "M" instances of parallel atClients dispatching "N" notifications.

/// Measurement Criteria:
/// ---------------------
/// Duration it takes for an atClient to receive acknowledgement(notificationID) from the the server for the notifications sent

/// Preconditions:
/// 1. SetUp required encryption keys
/// 2. Initialize atClientManager and set preferences
/// NOTE : Atsign, HiveStoragePath and commitLog path are passed a arguments
/// NOTE: [noOfNotifications] defaults to 100 for this test. This can be changed to any desired value by Modifying the value

/// Input Parameters:
/// - noOfNotifications - The number of notifications that needs to be sent to the server
/// NOTE: Here the notifications are self notifications with the notificationType as key
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
// - Test code will be creating an instance of notitificationService by virtue of atClientManager and use it to send 'N' number of notitifications
// - atClient will be running a monitor but there will be no explicit subscriptions to listen to any notifications

import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class InputParameters {
  static const noOfNotifications = 100;
  late String atSign;
  late String hiveStorageDir;
  late String commitLogStorageDir;
}

Future<void> main(List<String> arguments) async {
  late AtClientManager atClientManager;
  InputParameters inputParameters = InputParameters();
  inputParameters.atSign = arguments[0];
  String namespace = 'parallel_notify';
  AtClientPreference? preference;
// picks the storage path from the command line args
  inputParameters.hiveStorageDir = arguments[1];
  inputParameters.commitLogStorageDir = arguments[2];
  var uuid = Uuid();

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

  var startTime = DateTime.now().millisecondsSinceEpoch;

  test('parallel notify test to the same atsign ', () async {
    for (var i = 1; i <= InputParameters.noOfNotifications; i++) {
      var uniqueId = uuid.v4().hashCode;
      var phoneKey = AtKey()
        ..key = 'phone$uniqueId'
        ..sharedWith = inputParameters.atSign
        ..namespace = namespace;
      var value = '+1 100 200 300';

      await atClientManager.atClient.notificationService.notify(
          NotificationParams.forUpdate(phoneKey, value: value),
          waitForFinalDeliveryStatus: false);
    }
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
