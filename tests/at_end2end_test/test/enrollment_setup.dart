import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// Intentionally did not prefix/suffix the file name with test to refrain from running this in the test suite.

const String pkamPublicKey = 'aesPkamPublicKey';
const String pkamPrivateKey = 'aesPkamPrivateKey';
const String encryptionPublicKey = 'aesEncryptPublicKey';
const String encryptionPrivateKey = 'aesEncryptPrivateKey';
const String selfEncryptionKey = 'selfEncryptionKey';
const String apkamSymmetricKey = 'apkamSymmetricKey';
const String enrollmentId = 'enrollmentId';

void main() {
  var atSignList = ConfigUtil.getYaml()['enrollment']['atsignList'];

  for (var atSign in atSignList) {
    String currentAtSign = atSign;
    String namespace = 'wavi';

    test('A test to submit and approve an enrollment for $atSign', () async {
      // Set SPP at the start of enrollment tests to pass as OTP.
      await TestSuiteInitializer.getInstance()
          .testInitializer(currentAtSign, namespace, authType: 'pkam');
      // Set SPP into the Remote Secondary
      var atResponse =
          await AtClientManager.getInstance().atClient.setSPP('ABC123');
      expect(atResponse.response, 'ok');

      // Submit an enrollment request with at_auth package
      AtEnrollmentBase atEnrollmentBase =
          atAuthBase.atEnrollment(currentAtSign);
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          currentAtSign,
          AtClientManager.getInstance().atClient.getPreferences()!.rootDomain,
          AtClientManager.getInstance().atClient.getPreferences()!.rootPort);

      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: 'ABC123',
          namespaces: {'wavi': 'rw', 'buzz': 'rw'});
      AtEnrollmentResponse? atEnrollmentResponse =
          await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

      // Use enroll fetch to get the encryptedAPKAMSymmetricKey
      String? enrollmentFetchResponse = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()
          ?.executeCommand(
              'enroll:fetch:{"enrollmentId":"${atEnrollmentResponse.enrollmentId}"}\n',
              auth: true);
      enrollmentFetchResponse =
          enrollmentFetchResponse?.replaceAll('data:', '');
      Enrollment enrollment =
          Enrollment.fromJSON(jsonDecode(enrollmentFetchResponse!));

      // Approve enrollment
      AtEnrollmentResponse? approveEnrollmentResponse =
          await AtClientManager.getInstance()
              .atClient
              .enrollmentService
              .approve(EnrollmentRequestDecision.approved(
                  ApprovedRequestDecisionBuilder(
                      enrollmentId: atEnrollmentResponse.enrollmentId,
                      encryptedAPKAMSymmetricKey:
                          enrollment.encryptedAPKAMSymmetricKey!)));
      expect(approveEnrollmentResponse.enrollStatus, EnrollmentStatus.approved);

      // Get AtChops from the AtAuthKeys
      AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!, '');

      AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!,
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!);

      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);

      AtChops atChops = AtChopsImpl(atChopsKeys);
      atChops.atChopsKeys.apkamSymmetricKey =
          AESKey(atEnrollmentResponse.atAuthKeys!.apkamSymmetricKey!);
      atLookUp.atChops = atChops;
      atLookUp.enrollmentId = atEnrollmentResponse.enrollmentId;

      // Fetch the encryption private key and self encryption key from the remote secondary.
      atChops.atChopsKeys.atEncryptionKeyPair = AtEncryptionKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!,
          await getDefaultEncryptionPrivateKey(
              currentAtSign, atEnrollmentResponse.enrollmentId, atLookUp));

      String selfEncryptionKey = await getDefaultSelfEncryptionKey(
          currentAtSign, atEnrollmentResponse.enrollmentId, atLookUp);
      atChops.atChopsKeys.selfEncryptionKey = AESKey(selfEncryptionKey);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      AtClientManager.getInstance().removeAllChangeListeners();
      AtClientImpl.atClientInstanceMap.clear();

      // Authenticate the atSign
      AtAuth atAuth = atAuthBase.atAuth(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(currentAtSign);
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          atChops.atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey;
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey =
          atChops.atChopsKeys.selfEncryptionKey?.key;
      atAuthRequest.rootDomain =
          AtClientManager.getInstance().atClient.getPreferences()!.rootDomain;

      AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
      expect(atAuthResponse.isSuccessful, true);
      writeAtKeysToFile(currentAtSign, atAuthResponse.atAuthKeys!);
      print('Completed writing keys file for $currentAtSign');
    });
  }

  tearDownAll(() async {
    AtClientManager.getInstance().removeAllChangeListeners();
    AtClientManager.getInstance()
        .atClient
        .notificationService
        .stopAllSubscriptions();
    await AtClientManager.getInstance().atClient.stopCompactionJob();
    exit(0);
  });
}

/// Writes the atKeys to the file.
void writeAtKeysToFile(String atSign, AtAuthKeys atAuthKeys) {
  // Encrypt the keys
  Map<String, String> encryptedAtKeysMap = <String, String>{};

  String encryptedPkamPublicKey = EncryptionUtil.encryptValue(
      atAuthKeys.apkamPublicKey!, atAuthKeys.defaultSelfEncryptionKey!);
  encryptedAtKeysMap[pkamPublicKey] = encryptedPkamPublicKey;

  String encryptedPkamPrivateKey = EncryptionUtil.encryptValue(
      atAuthKeys.apkamPrivateKey!, atAuthKeys.defaultSelfEncryptionKey!);
  encryptedAtKeysMap[pkamPrivateKey] = encryptedPkamPrivateKey;

  String encryptedEncryptionPublicKey = EncryptionUtil.encryptValue(
      atAuthKeys.defaultEncryptionPublicKey!,
      atAuthKeys.defaultSelfEncryptionKey!);
  encryptedAtKeysMap[encryptionPublicKey] = encryptedEncryptionPublicKey;

  String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
      atAuthKeys.defaultEncryptionPrivateKey!,
      atAuthKeys.defaultSelfEncryptionKey!);
  encryptedAtKeysMap[encryptionPrivateKey] = encryptedEncryptionPrivateKey;

  encryptedAtKeysMap[selfEncryptionKey] = atAuthKeys.defaultSelfEncryptionKey!;
  encryptedAtKeysMap[apkamSymmetricKey] = atAuthKeys.apkamSymmetricKey!;
  encryptedAtKeysMap[enrollmentId] = atAuthKeys.enrollmentId!;

  // Write keys to file
  String keysString = jsonEncode(encryptedAtKeysMap);
  var file = File("${ConfigUtil.getYaml()['filePath']}/${atSign}_key.atKeys");
  file.createSync(recursive: true);
  file.writeAsStringSync(keysString);
}

/// Retrieves the encrypted "encryption private key" from the server and decrypts.
/// This process involves using the APKAM symmetric key for decryption.
/// Returns the original "encryption private key" after decryption.
Future<String> getDefaultEncryptionPrivateKey(
    String atSign, String enrollmentIdFromServer, AtLookUp atLookUp) async {
  var privateKeyCommand =
      'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultEncryptionPrivateKey}.__manage$atSign';
  String encryptionPrivateKeyFromServer;
  try {
    var getPrivateKeyResult =
        await atLookUp.executeCommand('$privateKeyCommand\n', auth: true);
    if (getPrivateKeyResult == null || getPrivateKeyResult.isEmpty) {
      throw AtEnrollmentException('$privateKeyCommand returned null/empty');
    }
    getPrivateKeyResult = getPrivateKeyResult.replaceFirst('data:', '');
    var privateKeyResultJson = jsonDecode(getPrivateKeyResult);
    encryptionPrivateKeyFromServer = privateKeyResultJson['value'];
  } on Exception catch (e) {
    throw AtEnrollmentException(
        'Exception while getting encrypted private key/self key from server: $e');
  }
  AtEncryptionResult? atEncryptionResult = atLookUp.atChops?.decryptString(
      encryptionPrivateKeyFromServer, EncryptionKeyType.aes256,
      keyName: 'apkamSymmetricKey', iv: AtChopsUtil.generateIVLegacy());
  return atEncryptionResult?.result;
}

/// Returns the decrypted selfEncryptionKey.
/// Fetches the encrypted selfEncryptionKey from the server and decrypts the
/// key with APKAM Symmetric key to get the original selfEncryptionKey.
Future<String> getDefaultSelfEncryptionKey(
    String atSign, String enrollmentIdFromServer, AtLookUp atLookUp) async {
  var selfEncryptionKeyCommand =
      'keys:get:keyName:$enrollmentIdFromServer.${AtConstants.defaultSelfEncryptionKey}.__manage$atSign';
  String selfEncryptionKeyFromServer;
  try {
    String? encryptedSelfEncryptionKey = await atLookUp
        .executeCommand('$selfEncryptionKeyCommand\n', auth: true);
    if (encryptedSelfEncryptionKey == null ||
        encryptedSelfEncryptionKey.isEmpty) {
      throw AtEnrollmentException(
          '$selfEncryptionKeyCommand returned null/empty');
    }
    encryptedSelfEncryptionKey =
        encryptedSelfEncryptionKey.replaceFirst('data:', '');
    var selfEncryptionKeyResultJson = jsonDecode(encryptedSelfEncryptionKey);
    selfEncryptionKeyFromServer = selfEncryptionKeyResultJson['value'];
  } on Exception catch (e) {
    throw AtEnrollmentException(
        'Exception while getting encrypted private key/self key from server: $e');
  }
  AtEncryptionResult? atEncryptionResult = atLookUp.atChops?.decryptString(
      selfEncryptionKeyFromServer, EncryptionKeyType.aes256,
      keyName: 'apkamSymmetricKey', iv: AtChopsUtil.generateIVLegacy());
  return atEncryptionResult?.result;
}
