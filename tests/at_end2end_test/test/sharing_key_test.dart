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

    // Defensive: ensure auto-notify is on for the publisher atServer
    // before any TTR-using test runs. A prior CI run's
    // bypasscache_test may have left `autoNotify=false` persisted on
    // the server (its `finally`-based reset is unreliable on test
    // timeouts).
    await acm.setCurrentAtSign(currentAtSign, namespace,
        TestPreferences.getInstance().getPreference(currentAtSign));
    await acm.atClient
        .getRemoteSecondary()!
        .executeCommand('config:set:autoNotify=true\n', auth: true);
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
    final cachedVerificationKeyStr = cachedVerificationKey.toString();

    // Poll for the cached entry to appear via getKeys. The cross-
    // server notify (publisher atServer -> receiver atServer creating
    // the `cached:@<sharedWith>:...@<sharedBy>` entry) is async and
    // can take several seconds on long-running real atServers.
    final pollDeadline = DateTime.now().add(Duration(seconds: 60));
    List<String> getResult = [];
    while (true) {
      await E2ESyncService.getInstance().syncData(acm.atClient.syncService);
      getResult = await acm.atClient.getKeys(regex: cachedVerificationKeyStr);
      if (getResult.contains(cachedVerificationKeyStr)) break;
      if (!DateTime.now().isBefore(pollDeadline)) break;
      await Future.delayed(Duration(seconds: 1));
    }
    expect(getResult.contains(cachedVerificationKeyStr), true,
        reason: 'cached key never appeared in receiver local hive within '
            'the propagation window');

    AtValue getCachedKeyResponse =
        await acm.atClient.get(AtKey.fromString(getResult.first));
    expect(getCachedKeyResponse.value, '0873');
    expect(getCachedKeyResponse.metadata!.isCached, true);
  }, timeout: Timeout(Duration(minutes: 2)));

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
