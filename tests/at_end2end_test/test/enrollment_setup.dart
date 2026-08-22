/// The default 30-second budget is far too small here. These atSigns are
/// long-lived CI atSigns whose commit logs reach hundreds of thousands of
/// entries, and a fresh runner replays from commit id -1 while the enrollment
/// verbs share the same connection. Measured 2026-08-20: every one of the four
/// approvals timed out at exactly 30 seconds, and the failure then surfaced
/// three minutes later as eight missing-keyfile errors in a different step.
///
/// Measured 2026-08-20 with a five-minute budget: **all four approvals passed,
/// taking 4:59**. So this was slow rather than stuck — but 4:59 against 5:00 is
/// not a margin, it is a coin toss, and the backlog these atSigns carry only
/// grows. Fifteen minutes is chosen to be uninteresting rather than tight; a
/// run that genuinely hangs still fails, just later.
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
// Not in the barrel: `SyncService` exposes no way to stop syncing, and this
// script needs one. See [_stopSync].
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
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

/// Asks the current client's sync to stop. This script never needs it.
///
/// Enrollments are submitted and approved over the REMOTE secondary; nothing
/// here reads local storage. So syncing is pure cost — and on the long-lived
/// @ce2e atSigns the cost is large: their commit logs run to several hundred
/// thousand entries and a CI runner starts with empty local storage, so every
/// client replays from commit id -1.
///
/// ⚠️ **This helps less than it looks, and the measurement says so.** With it
/// in place the records pulled inside one 30-second budget went UP, 3928 to
/// 4940. Two reasons, both structural: `stop()` drains the queue and cancels
/// the periodic timer but does **not** interrupt a run already in flight, and
/// every `setCurrentAtSign` to a different atSign builds a brand-new
/// `SyncServiceImpl` with `warmStartSync: true`, which syncs immediately. So
/// stopping after the client exists is always too late for the run that has
/// already started.
///
/// It is kept because it does stop the periodic timer and any later run, and
/// removing it would restore load rather than remove a false claim. What it
/// cannot do is make this script fast.
///
/// `SyncService` declares no way to stop, which is why this reaches for the
/// implementation.
Future<void> _stopSync() async {
  final syncService = AtClientManager.getInstance().atClient.syncService;
  if (syncService is SyncServiceImpl) {
    await syncService.stop();
  }
}

void main() {
  List atSignList = ConfigUtil.getYaml()['enrollment']['atsignList'];
  String namespace = TestConstants.namespace;

  setUpAll(() async {
    for (var atSign in atSignList) {
      await TestSuiteInitializer.getInstance()
          .testInitializer(atSign, namespace, 'pkam', enableInitialSync: false);
      await _stopSync();
    }
  });

  for (var currentAtSign in atSignList) {
    test('A test to submit and approve an enrollment for $currentAtSign',
        () async {
      // Set SPP at the start of enrollment tests to pass as OTP.
      await TestSuiteInitializer.getInstance().testInitializer(
          currentAtSign, namespace, 'pkam',
          enableInitialSync: false);
      // Switching back to an atSign restarts its sync, so stop it again.
      await _stopSync();
      // Set SPP into the Remote Secondary
      var atClient = AtClientManager.getInstance().atClient;
      var otp = (await atClient.getOTP()).response;

      // Submit an enrollment request with at_auth package
      AtEnrollment atEnrollmentBase = AtEnrollment.create();
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          currentAtSign,
          atClient.getPreferences()!.rootDomain,
          atClient.getPreferences()!.rootPort);

      // Do an enrollment with access to the __config namespace
      AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
          atSign: currentAtSign,
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: otp,
          namespaces: {TestConstants.namespace: 'rw', '__config': 'rw'});
      AtEnrollmentResponse? atEnrollmentResponse =
          await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

      // Use enroll fetch to get the encryptedAPKAMSymmetricKey
      String? enrollmentFetchResponse = await atClient
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
          await atClient.enrollmentService?.approve(
        EnrollmentRequestDecision.approved(
            enrollmentId: atEnrollmentResponse.enrollmentId,
            apkamSymmetricKey:
                AtBytes.fromString(enrollment.encryptedAPKAMSymmetricKey!),
            atSign: currentAtSign),
      );
      expect(
          approveEnrollmentResponse?.enrollStatus, EnrollmentStatus.approved);

      // Get AtChops from the AtAuthKeys
      AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!
              .toString(),
          '');

      AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!.toString(),
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!.toString());

      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);

      AtChops atChops = AtChopsImpl(atChopsKeys);
      atChops.atChopsKeys.apkamSymmetricKey = AESKey(
          atEnrollmentResponse.atAuthKeys!.apkamSymmetricKey!.toString());
      atLookUp.atChops = atChops;
      atLookUp.enrollmentId = atEnrollmentResponse.enrollmentId;

      // Fetch the encryption private key and self encryption key from the remote secondary.
      atChops.atChopsKeys.atEncryptionKeyPair = AtEncryptionKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.defaultEncryptionPublicKey!
              .toString(),
          await getDefaultEncryptionPrivateKey(
              currentAtSign, atEnrollmentResponse.enrollmentId, atLookUp));

      String selfEncryptionKey = await getDefaultSelfEncryptionKey(
          currentAtSign, atEnrollmentResponse.enrollmentId, atLookUp);
      atChops.atChopsKeys.selfEncryptionKey = AESKey(selfEncryptionKey);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      AtClientManager.getInstance().removeAllChangeListeners();
      AtClientImpl.atClientInstanceMap.clear();

      // Authenticate the atSign
      AtAuth atAuth = AtAuth.create(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(currentAtSign,
          atKeysIo: FileAtKeysIo(
            filePath: (_) =>
                '${ConfigUtil.getYaml()['filePath']}/${currentAtSign}_key.atKeys',
          ));
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          AtBytes.fromString(
              atChops.atChopsKeys.atEncryptionKeyPair!.atPrivateKey.privateKey);
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey =
          AtBytes.fromString(atChops.atChopsKeys.selfEncryptionKey!.key);
      atAuthRequest.rootDomain = AtRootDomain(
          atClient.getPreferences()!.rootDomain,
          atClient.getPreferences()!.rootPort);

      AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
      expect(atAuthResponse.isSuccessful, true);
      writeAtKeysToFile(currentAtSign, atAuthResponse.atAuthKeys!);
      print(
          'Completed enrollment setup of the atSign: $currentAtSign with enrollment Id: ${atEnrollmentResponse.enrollmentId} with access to ${enrollmentRequest.namespaces}');
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
void writeAtKeysToFile(String atSign, AtKeys atAuthKeys) {
  // Encrypt the keys
  Map<String, String> encryptedAtKeysMap = <String, String>{};

  String encryptedPkamPublicKey = EncryptionUtil.encryptValue(
      atAuthKeys.apkamPublicKey!.toString(),
      atAuthKeys.defaultSelfEncryptionKey!.toString());
  encryptedAtKeysMap[pkamPublicKey] = encryptedPkamPublicKey;

  String encryptedPkamPrivateKey = EncryptionUtil.encryptValue(
      atAuthKeys.apkamPrivateKey!.toString(),
      atAuthKeys.defaultSelfEncryptionKey!.toString());
  encryptedAtKeysMap[pkamPrivateKey] = encryptedPkamPrivateKey;

  String encryptedEncryptionPublicKey = EncryptionUtil.encryptValue(
      atAuthKeys.defaultEncryptionPublicKey!.toString(),
      atAuthKeys.defaultSelfEncryptionKey!.toString());
  encryptedAtKeysMap[encryptionPublicKey] = encryptedEncryptionPublicKey;

  String encryptedEncryptionPrivateKey = EncryptionUtil.encryptValue(
      atAuthKeys.defaultEncryptionPrivateKey!.toString(),
      atAuthKeys.defaultSelfEncryptionKey!.toString());
  encryptedAtKeysMap[encryptionPrivateKey] = encryptedEncryptionPrivateKey;

  encryptedAtKeysMap[selfEncryptionKey] =
      atAuthKeys.defaultSelfEncryptionKey!.toString();
  encryptedAtKeysMap[apkamSymmetricKey] =
      atAuthKeys.apkamSymmetricKey!.toString();
  encryptedAtKeysMap[enrollmentId] = atAuthKeys.enrollmentId!.toString();

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
  String encryptionPrivateKeyIV;
  try {
    var getPrivateKeyResult =
        await atLookUp.executeCommand('$privateKeyCommand\n', auth: true);
    if (getPrivateKeyResult == null || getPrivateKeyResult.isEmpty) {
      throw AtEnrollmentException('$privateKeyCommand returned null/empty');
    }
    getPrivateKeyResult = getPrivateKeyResult.replaceFirst('data:', '');
    var privateKeyResultJson = jsonDecode(getPrivateKeyResult);
    encryptionPrivateKeyFromServer = privateKeyResultJson['value'];
    encryptionPrivateKeyIV = privateKeyResultJson['iv'];
  } on Exception catch (e) {
    throw AtEnrollmentException(
        'Exception while getting encrypted private key/self key from server: $e');
  }
  AtEncryptionResult? atEncryptionResult = await atLookUp.atChops
      ?.decryptString(encryptionPrivateKeyFromServer, EncryptionKeyType.aes256,
          keyName: 'apkamSymmetricKey',
          iv: AtChopsUtil.generateIVFromBase64String(encryptionPrivateKeyIV));
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
  String selfEncryptionKeyIV;
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
    selfEncryptionKeyIV = selfEncryptionKeyResultJson['iv'];
  } on Exception catch (e) {
    throw AtEnrollmentException(
        'Exception while getting encrypted private key/self key from server: $e');
  }
  AtEncryptionResult? atEncryptionResult = await atLookUp.atChops
      ?.decryptString(selfEncryptionKeyFromServer, EncryptionKeyType.aes256,
          keyName: 'apkamSymmetricKey',
          iv: AtChopsUtil.generateIVFromBase64String(selfEncryptionKeyIV));
  return atEncryptionResult?.result;
}
