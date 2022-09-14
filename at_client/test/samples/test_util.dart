import 'dart:convert';
import 'dart:typed_data';
// import 'package:at_client/src/preference/at_client_preference.dart';
import 'dart:io';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:crypto/crypto.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demo;
import 'package:hive/hive.dart';

class TestUtil {
  static AtClientPreference getPreferenceRemote() {
    var preference = AtClientPreference();
    preference.isLocalStoreRequired = false;
    preference.rootDomain = 'vip.ve.atsign.zone';
    preference.outboundConnectionTimeout = 60000;
    return preference;
  }

  static AtClientPreference getPreferenceLocal() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'test/hive/client';
    preference.commitLogPath = 'test/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'test.do-sf2.atsign.zone';
    preference.keyStoreSecret =
        _getKeyStoreSecret(''); // path of hive encryption key filefor client
    return preference;
  }

  static AtClientPreference getAlicePreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'test/hive/client';
    preference.commitLogPath = 'test/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign('@alice🛠');
    preference.keyStoreSecret =
        _getKeyStoreSecret('test/hive/client/$hashFile.hash');
    return preference;
  }

  static AtClientPreference getPreference(String atSign) {
    var preference = AtClientPreference();
    final storageBasePath = 'test/hive/client';
    final storagePathExists = Directory(storageBasePath).existsSync();
    if(!storagePathExists) {
      Directory(storageBasePath).createSync(recursive: true);
    }
    preference.hiveStoragePath = storageBasePath;
    preference.commitLogPath = '$storageBasePath/commit';
    final commitLogPathExists = Directory(preference.commitLogPath!).existsSync();
    if(!commitLogPathExists) {
      Directory(preference.commitLogPath!).createSync();
    }
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign(atSign);
    final secretFilePath = '$storageBasePath/$hashFile.hash';
    if(!File(secretFilePath).existsSync()) {
      File(secretFilePath).createSync();
      final hiveSecretString = String.fromCharCodes(Hive.generateSecureKey());
      File(secretFilePath).writeAsStringSync(hiveSecretString);
    }
    preference.keyStoreSecret =
        _getKeyStoreSecret(secretFilePath);
    return preference;
  }

  static Future<void> setUpKeys(String atSign) async {
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', getPreference(atSign));
    final atClient = atClientManager.atClient;
    final localSecondary = atClient.getLocalSecondary()!;
    final pkamPrivateKey = await localSecondary.getPrivateKey();
    if (pkamPrivateKey == null || pkamPrivateKey.isEmpty) {
      await localSecondary.putValue(
          AT_PKAM_PRIVATE_KEY, at_demo.pkamPrivateKeyMap[atSign]!);
    }
    final pkamPublicKey = await localSecondary.getPublicKey();
    if (pkamPublicKey == null || pkamPublicKey.isEmpty) {
      await localSecondary.putValue(
          AT_PKAM_PUBLIC_KEY, at_demo.pkamPublicKeyMap[atSign]!);
    }
    final encryptionPrivateKey = await localSecondary.getEncryptionPrivateKey();
    if (encryptionPrivateKey == null || encryptionPrivateKey.isEmpty) {
      await localSecondary.putValue(
          AT_ENCRYPTION_PRIVATE_KEY, at_demo.encryptionPrivateKeyMap[atSign]!);
    }

    final encryptionPublicKey =
        await localSecondary.getEncryptionPublicKey(atSign);
    if (encryptionPublicKey == null || encryptionPublicKey.isEmpty) {
      await localSecondary.putValue('$AT_ENCRYPTION_PUBLIC_KEY$atSign',
          at_demo.encryptionPublicKeyMap[atSign]!);
    }
    final selfEncryptionKey = await localSecondary.getEncryptionSelfKey();
    if (selfEncryptionKey == null || selfEncryptionKey.isEmpty) {
      await localSecondary.putValue(
          AT_ENCRYPTION_SELF_KEY, at_demo.aesKeyMap[atSign]!);
    }
  }

  static String? getPrivateKey(String atSign) {
    return at_demo.pkamPrivateKeyMap[atSign];
  }

  static AtClientPreference getBobPreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = '/home/murali/work/2020/hive/client';
    preference.commitLogPath = '/home/murali/work/2020/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign('@bob🛠');
    preference.keyStoreSecret =
        _getKeyStoreSecret('/home/murali/work/2020/hive/client/$hashFile.hash');
    return preference;
  }

  static List<int> _getKeyStoreSecret(String filePath) {
    var hiveSecretString = File(filePath).readAsStringSync();
    var secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
    return secretAsUint8List;
  }

  static String _getShaForAtSign(String atsign) {
    var bytes = utf8.encode(atsign);
    return sha256.convert(bytes).toString();
  }
}
