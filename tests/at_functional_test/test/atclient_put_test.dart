import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

/// The tests verify the put and get functionality where key is created using AtKey concrete
/// class
void main() {
  late AtClientManager atClientManager;
  late String atSign;
  final namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final preference = TestUtils.getPreference(atSign)
      ..crypto = CryptoConfig(
        defaultProviderId: 'legacy',
        providers: [
          (_) => TestProvider('test'),
        ],
      );
    atClientManager = await TestUtils.initAtClient(
      atSign,
      namespace,
      preference: preference,
    );
    atClientManager.atClient.syncService.sync();
  });

  test(
      'put method - create a key sharing to other atSign and verify metadata isEncrypted from server',
      () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠'
      ..sharedBy = atSign;
    var value = '+1 100 200 300';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
    expect(getResult.metadata?.isEncrypted, true);
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: AtClientManager.getInstance().atClient.syncService);
    // fetch the key from remote and verify isEncrypted
    var getResultRemote = await atClientManager.atClient.get(phoneKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(getResultRemote.metadata?.isEncrypted, true);
  });

  test(
      'put method - create a key sharing to other atSign with isEncrypted set to false',
      () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠'
      ..sharedBy = atSign;
    var value = '+1 100 200 300';
    final putRequestOptions = PutRequestOptions()..shouldEncrypt = false;
    var putResult = await atClientManager.atClient
        .put(phoneKey, value, putRequestOptions: putRequestOptions);
    expect(putResult, true);
    // get the value from local keystore to check whether it is not encrypted
    var getKeyStoreResult = await atClientManager.atClient
        .getLocalSecondary()!
        .keyStore!
        .get(phoneKey.toString());
    expect(getKeyStoreResult.data, value);
    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
    expect(getResult.metadata?.isEncrypted, false);
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: AtClientManager.getInstance().atClient.syncService);
    // fetch the key from remote and verify isEncrypted
    var getResultRemote = await atClientManager.atClient.get(phoneKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(getResultRemote.metadata?.isEncrypted, false);
  });

  test('put method - create a public key', () async {
    var phoneKey = AtKey()
      ..key = 'location'
      ..metadata = (Metadata()..isPublic = true);
    var value = 'California';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with sharedWith populated', () async {
    var phoneKey = AtKey()
      ..key = 'country'
      ..sharedWith = atSign;
    var value = 'US';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with sharedWith not populated',
      () async {
    var phoneKey = AtKey()..key = 'mobile';
    var value = '+1 100 200 300';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a key with binary data', () async {
    var phoneKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()..isBinary = true);
    var value = _getBinaryData("/test/testData/dev.png");
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);
    var getKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()..isBinary = true);

    var getResult = await atClientManager.atClient.get(getKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key with binary data', () async {
    var phoneKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()
        ..isBinary = true
        ..isPublic = true);
    var value = _getBinaryData("/test/testData/dev.png");
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()
        ..isBinary = true
        ..isPublic = true);
    var getResult = await atClientManager.atClient.get(getKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key', () async {
    var phoneKey = AtKey()
      ..key = 'city'
      ..metadata = (Metadata()..isPublic = true);
    var value = 'copenhagen';
    var putResult = await atClientManager.atClient.put(phoneKey, value);
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - using pluggable encryption', () async {
    var phoneKey = AtKey()
      ..key = 'city.${DateTime.now().microsecondsSinceEpoch}'
      ..sharedBy = atSign;
    var value = 'copenhagen';
    PutRequestOptions options = PutRequestOptions()
      ..cryptoProviderId = 'test'
      ..shouldEncrypt = true;
    var putResult = await atClientManager.atClient.put(
      phoneKey,
      value,
      putRequestOptions: options,
    );
    expect(putResult, true);

    var getResult = await atClientManager.atClient.get(phoneKey);
    expect(getResult.value, 'decrypted');
    expect(getResult.metadata?.appMetadata?.providerId, 'test');
  });

  test('put method - using pluggable encryption: failure', () async {
    var phoneKey = AtKey()..key = 'city';
    var value = 'copenhagen';
    PutRequestOptions options = PutRequestOptions()
      ..cryptoProviderId = 'testfail'
      ..shouldEncrypt = true;

    expect(
      () async => await atClientManager.atClient.put(
        phoneKey,
        value,
        putRequestOptions: options,
      ),
      throwsA(isA<CryptoProviderNotRegistered>()),
    );
  });
}

Uint8List _getBinaryData(dynamic filePath) {
  var dir = Directory.current.path;
  var pathToFile = '$dir$filePath';
  return File(pathToFile).readAsBytesSync();
}

class TestProvider extends CryptoProvider {
  @override
  final String id;

  TestProvider(this.id);

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    return const CryptoDecryptResult(plaintext: 'decrypted');
  }

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    return CryptoEncryptResult(
      ciphertext: 'encrypted',
      metadata: AppMetadata(id),
    );
  }
}
