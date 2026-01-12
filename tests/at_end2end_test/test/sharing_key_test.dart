import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() async {
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = TestConstants.namespace;
  var uuid = Uuid();

  final acm = AtClientManager.getInstance();

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace, authType);
  });

  /// The purpose of this test verify the following:
  /// 1. Put method
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb
  test('Share a key to sharedWith atSign and lookup from sharedWith atSign',
      () async {
    // Setting currentAtSign atClient instance to context.
    await acm.setCurrentAtSign(currentAtSign, namespace,
        TestPreferences.getInstance().getPreference(currentAtSign));
    // Generate  uuid
    var uniqueId = uuid.v4().hashCode;
    var phoneNumberKey = AtKey()
      ..key = 'phoneNumber-$uniqueId'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = (Metadata()..ttl = TestConstants.oneMinuteMillis);

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+91 901920192${Random().nextInt(9)}';
    var putResult = await acm.atClient.put(phoneNumberKey, value);
    expect(putResult, true);
    await E2ESyncService.getInstance().syncData(acm.atClient.syncService);

    // Setting sharedWithAtSign atClient instance to context.
    await acm.setCurrentAtSign(sharedWithAtSign, namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign));
    var getResult = await acm.atClient.get(AtKey()
      ..key = 'phoneNumber-$uniqueId'
      ..sharedBy = currentAtSign);
    expect(getResult.value, value);
    expect(getResult.metadata?.sharedKeyEnc != null, true);
    expect(getResult.metadata?.pubKeyCS != null, true);
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 1)));

  /// The purpose of this test verify the following:
  /// 1. Put method with caching of key
  /// 2. Sync to cloud secondary
  /// 3. Cached key sync to local secondary on the receiver atSign.
  test(
      'Create a key to sharedWith atSign with ttr and verify sharedWith atSign has a cached_key',
      () async {
    // Setting currentAtSign atClient instance to context.
    await acm.setCurrentAtSign(currentAtSign, namespace,
        TestPreferences.getInstance().getPreference(currentAtSign));
    var uniqueId = uuid.v4().hashCode;
    var verificationKey = AtKey()
      ..key = 'verificationnumber-$uniqueId'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..namespace = namespace
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ccd = true
        ..ttl = TestConstants.oneMinuteMillis);
    var value = '0873';
    var putResult = await acm.atClient.put(verificationKey, value);
    expect(putResult, true);
    await E2ESyncService.getInstance().syncData(acm.atClient.syncService);

    // Setting sharedWithAtSign atClient instance to context.
    await acm.setCurrentAtSign(sharedWithAtSign, namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign));
    var cachedVerificationKey = AtKey()
      ..key = 'verificationnumber-$uniqueId'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..namespace = namespace
      ..metadata = (Metadata()..isCached = true);
    await E2ESyncService.getInstance().syncData(acm.atClient.syncService);

    var getResult =
        await acm.atClient.getKeys(regex: cachedVerificationKey.toString());
    expect(getResult.contains(cachedVerificationKey.toString()), true);

    AtValue getCachedKeyResponse =
        await acm.atClient.get(AtKey.fromString(getResult.first));
    expect(getCachedKeyResponse.value, '0873');
    expect(getCachedKeyResponse.metadata!.isCached, true);
  }, timeout: Timeout(Duration(minutes: 1)));

  /// The purpose of this test verify the following:
  /// 1. Backward compatibility for [metadata.sharedKeyEnc] and [metadata?.pubKeyCS]
  /// The encrypted value does not have new metadata but decrypt value successfully.
  test('Basic encrypted sharing test', () async {
    var uniqueId = uuid.v4().hashCode;
    final value = 'New Jersey';

    await acm.setCurrentAtSign(currentAtSign, namespace,
        TestPreferences.getInstance().getPreference(currentAtSign));
    await acm.atClient.put(
        AtKey()
          ..key = 'location-$uniqueId'
          ..sharedWith = sharedWithAtSign
          ..sharedBy = currentAtSign
          ..namespace = namespace,
        value,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

    await acm.setCurrentAtSign(sharedWithAtSign, namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign));
    var getResult = await acm.atClient.get(AtKey()
      ..key = 'location-$uniqueId'
      ..sharedBy = currentAtSign);
    expect(getResult.value, value);
  });
}
