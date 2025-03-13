import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:encrypt/encrypt.dart';

/// Perform initial onboarding for an atsign
/// 1. CRAM authentication
/// 2. PKAM authentication with privilege to approve/deny future enrollment requests
/// 3. Generate .atKeys file in the path passed as arg
/// Usage: `dart onboard.dart -a <atsign> -c <cram_secret> -k <path_to_save_atkeys_file> -r <root_server_domain>`
void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption('cramsecret', abbr: 'c', help: 'CRAM secret', mandatory: true)
      ..addOption('keysFilePath',
          abbr: 'k', help: 'Path to store .atKeys file', mandatory: true)
      ..addOption('rootDomain',
          abbr: 'r',
          help: 'root server domain',
          mandatory: false,
          defaultsTo: 'root.atsign.org');
    final argResults = parser.parse(args);

    final atAuth = AtAuthImpl();
    final atSign = argResults['atsign'];
    final atOnboardingRequest = AtOnboardingRequest(atSign)
      ..rootDomain = argResults['rootDomain']
      ..appName = 'wavi'
      ..deviceName = 'iphone';
    final atOnboardingResponse =
        await atAuth.onboard(atOnboardingRequest, argResults['cramsecret']);
    print('atOnboardingResponse: $atOnboardingResponse');
    if (atOnboardingResponse.isSuccessful) {
      await _generateAtKeysFile(atOnboardingResponse.enrollmentId,
          atOnboardingResponse.atAuthKeys!, atSign, argResults['keysFilePath']);
    }
  } on Exception catch (e, trace) {
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  } finally {
    exit(0);
  }
}

Future<void> _generateAtKeysFile(String? currentEnrollmentId,
    AtAuthKeys atAuthKeys, String atSign, String keysFilePath) async {
  final atKeysMap = <String, String>{
    'aesPkamPublicKey': _encryptValue(
      atAuthKeys.apkamPublicKey!,
      atAuthKeys.defaultSelfEncryptionKey!,
    ),
    'aesPkamPrivateKey': _encryptValue(
      atAuthKeys.apkamPrivateKey!,
      atAuthKeys.defaultSelfEncryptionKey!,
    ),
    'aesEncryptPublicKey': _encryptValue(
      atAuthKeys.defaultEncryptionPublicKey!,
      atAuthKeys.defaultSelfEncryptionKey!,
    ),
    'aesEncryptPrivateKey': _encryptValue(
      atAuthKeys.defaultEncryptionPrivateKey!,
      atAuthKeys.defaultSelfEncryptionKey!,
    ),
    'selfEncryptionKey': atAuthKeys.defaultSelfEncryptionKey!,
    atSign: atAuthKeys.defaultSelfEncryptionKey!,
    'apkamSymmetricKey': atAuthKeys.apkamSymmetricKey!
  };

  if (currentEnrollmentId != null) {
    atKeysMap['enrollmentId'] = currentEnrollmentId;
  }

  File atKeysFile = File(keysFilePath);

  if (!atKeysFile.existsSync()) {
    atKeysFile.createSync(recursive: true);
  }
  IOSink fileWriter = atKeysFile.openWrite();

  //generating .atKeys file
  fileWriter.write(jsonEncode(atKeysMap));
  await fileWriter.flush();
  await fileWriter.close();
  stdout.writeln('[Success] Your .atKeys file saved at $keysFilePath\n');
}

String _encryptValue(String value, String encryptionKey) {
  var aesEncrypter = Encrypter(AES(Key.fromBase64(encryptionKey)));
  var encryptedValue = aesEncrypter.encrypt(value, iv: IV(Uint8List(16)));
  return encryptedValue.base64;
}
