import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() async {
  late AtClientManager currentAtClientManager;
  late AtClientManager sharedWithAtClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';
  var uuid = Uuid();

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
  });

  /// The purpose of this test verify the following:
  /// 1. Put method
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb
  test('Share a key to sharedWith atSign and lookup from sharedWith atSign',
      () async {
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
    // Generate  uuid
    var uniqueId = uuid.v4().hashCode;
    var phoneNumberKey = AtKey()
      ..key = 'phoneNumber-$uniqueId'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = (Metadata()..ttl = 120000);

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+91 901920192${Random().nextInt(9)}';
    var putResult =
        await currentAtClientManager.atClient.put(phoneNumberKey, value);
    expect(putResult, true);
    await E2ESyncService.getInstance().syncData(
        currentAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()..key = phoneNumberKey.toString());

    // Setting sharedWithAtSign atClient instance to context.
    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));
    var getResult = await sharedWithAtClientManager.atClient.get(AtKey()
      ..key = 'phoneNumber-$uniqueId'
      ..sharedBy = currentAtSign);
    expect(getResult.value, value);
    expect(getResult.metadata?.sharedKeyEnc != null, true);
    expect(getResult.metadata?.pubKeyCS != null, true);
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
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
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
        ..ttl = 300000);
    var value = '0873';
    var putResult =
        await currentAtClientManager.atClient.put(verificationKey, value);
    expect(putResult, true);
    await E2ESyncService.getInstance().syncData(
        currentAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()..key = verificationKey.toString());

    // Setting sharedWithAtSign atClient instance to context.
    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));
    var cachedVerificationKey = AtKey()
      ..key = 'verificationnumber-$uniqueId'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..namespace = namespace
      ..metadata = (Metadata()..isCached = true);
    await E2ESyncService.getInstance().syncData(
        sharedWithAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()..key = cachedVerificationKey.toString());

    var getResult = await sharedWithAtClientManager.atClient
        .getKeys(regex: cachedVerificationKey.toString());
    expect(getResult.contains(cachedVerificationKey.toString()), true);

    AtValue getCachedKeyResponse = await sharedWithAtClientManager.atClient
        .get(AtKey.fromString(getResult.first));
    expect(getCachedKeyResponse.value, '0873');
    expect(getCachedKeyResponse.metadata!.isCached, true);
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 5)));

  /// The purpose of this test verify the following:
  /// 1. Backward compatibility for [metadata.sharedKeyEnc] and [metadata?.pubKeyCS]
  /// The encrypted value does not have new metadata but decrypt value successfully.
  test(
      'verify backward compatibility for sharedKey and checksum in metadata for sharedkey',
      () async {
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
    var uniqueId = uuid.v4().hashCode;

    var locationKey = AtKey()
      ..key = 'location-$uniqueId'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..namespace = namespace
      ..metadata = Metadata();

    var value = 'New Jersey';
    var encryptionService =
        AtKeyEncryptionManager(currentAtClientManager.atClient)
            .get(locationKey, currentAtSign);
    var encryptedValue = await encryptionService.encrypt(locationKey, value);
    var result = await currentAtClientManager.atClient
        .getRemoteSecondary()!
        .executeCommand(
            'update:ttl:300000:sharedKeyEnc:${locationKey.metadata.sharedKeyEnc}:pubKeyCS:${locationKey.metadata.pubKeyCS}:${locationKey.toString()} $encryptedValue\n',
            auth: true);
    expect(result != null, true);
    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));

    var getResult = await sharedWithAtClientManager.atClient.get(AtKey()
      ..key = 'location-$uniqueId'
      ..sharedBy = currentAtSign);
    expect(getResult.value, value);
  });
}
