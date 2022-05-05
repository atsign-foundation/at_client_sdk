import 'dart:io';
import 'package:uuid/uuid.dart';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  var currentAtSign, sharedWithAtSign;
  AtClientManager? currentAtSignClientManager, sharedWithAtSignClientManager;
  var namespace = 'wavi';

  Future<void> refresh(AtClientManager? clientManager) async {
    var isSyncInProgress = true;
    clientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  }

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    // Create atClient instance for currentAtSign
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // Set Encryption Keys for currentAtSign
    await TestUtils.setEncryptionKeys(currentAtSign);
    await refresh(currentAtSignClientManager);

    // Create atClient instance for atSign2
    sharedWithAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestUtils.getPreference(sharedWithAtSign));
    // Set Encryption Keys for sharedWithAtSign
    await TestUtils.setEncryptionKeys(sharedWithAtSign);
    await refresh(sharedWithAtSignClientManager);
  });

  /// The purpose of this test verify the following:
  /// 1. Put method
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb
  test('Share a key to sharedWith atSign and lookup from sharedWith atSign',
      () async {
    var uuid = Uuid();
    // Generate a uuid
    var randomValue = uuid.v4();
    var mobileNumberKey = AtKey()
      ..key = 'mobileNum$randomValue'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata()..ttl = 120000);

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+1 100 200 30';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(mobileNumberKey, value);
    expect(putResult, true);
    await refresh(currentAtSignClientManager);
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    await refresh(sharedWithAtSignClientManager);
    var getResult = await sharedWithAtSignClientManager?.atClient.get(AtKey()
      ..key = 'mobileNum$randomValue'
      ..sharedBy = currentAtSign);
    expect(getResult?.value, value);
    expect(getResult?.metadata?.sharedKeyEnc != null, true);
    expect(getResult?.metadata?.pubKeyCS != null, true);
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 5)));

  /// The purpose of this test verify the following:
  /// 1. Put method with caching of key
  /// 2. Sync to cloud secondary
  /// 3. Cached key sync to local secondary on the receiver atSign.
  test(
      'Create a key to sharedWith atSign with ttr and verify sharedWith atSign has a cached_key',
      () async {
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var uuid = Uuid();
    // Generate uuid
    var randomValue = uuid.v4();
    var verificationKey = AtKey()
      ..key = 'verify-code$randomValue'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ccd = true
        ..ttl = 300000);
    var value = '0873';
    var putResult =
        await currentAtSignClientManager?.atClient.put(verificationKey, value);
    expect(putResult, true);
    await refresh(currentAtSignClientManager);
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    await refresh(sharedWithAtSignClientManager);
    // adding a wait till the cached key gets created
    await Future.delayed(Duration(seconds: 4));
    var getResult = await sharedWithAtSignClientManager?.atClient.getKeys(
        regex:
            'cached:$sharedWithAtSign:${verificationKey.key}.$namespace$currentAtSign');
    print('get result is $getResult');
    expect(
        getResult?.contains(
            'cached:$sharedWithAtSign:${verificationKey.key}.$namespace$currentAtSign'),
        true);
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 5)));

  /// The purpose of this test verify the following:
  /// 1. Backward compatibility for [metadata.sharedKeyEnc] and [metadata?.pubKeyCS]
  /// The encrypted value does not have new metadata but decrypt value successfully.
  test(
      'verify backward compatibility for sharedKey and checksum in metadata for sharedkey',
      () async {
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var locationKey = AtKey()
      ..key = 'location'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = Metadata();
    var value = 'New Jersey';
    var encryptionService =
        AtKeyEncryptionManager.get(locationKey, currentAtSign);
    var encryptedValue = await encryptionService.encrypt(locationKey, value);
    var result = await currentAtSignClientManager?.atClient
        .getRemoteSecondary()!
        .executeCommand(
            'update:ttl:300000$sharedWithAtSign:location.$namespace$currentAtSign $encryptedValue\n',
            auth: true);
    expect(result != null, true);
    await refresh(currentAtSignClientManager);
    sharedWithAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestUtils.getPreference(sharedWithAtSign));
    await refresh(sharedWithAtSignClientManager);
    var getResult = await sharedWithAtSignClientManager?.atClient.get(AtKey()
      ..key = 'location'
      ..sharedBy = currentAtSign);
    expect(getResult?.value, value);
  }, timeout: Timeout(Duration(minutes: 5)));

  tearDownAll(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}
