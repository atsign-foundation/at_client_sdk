import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/auth/at_security_keys.dart';
import 'package:at_client_mobile/src/auth/cram_authenticator.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_chops/at_chops.dart';

import 'package:at_client_mobile/src/auth/at_authenticator.dart';
import 'package:at_client_mobile/src/auth/pkam_authenticator.dart';

import 'at_auth_service.dart';
import 'package:at_utils/at_logger.dart';

class AtAuthServiceImpl implements AtAuthService {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  PkamAuthenticator? pkamAuthenticator;
  CramAuthenticator? cramAuthenticator;
  AtLookUp? _atLookup;
  final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  @override
  AtChops? atChops;

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) {
    // TODO: implement authenticate
    throw UnimplementedError();
  }

  @override
  Future<AtEnrollmentResponse> enroll(AtEnrollmentRequest atEnrollmentRequest) {
    // TODO: implement enroll
    throw UnimplementedError();
  }

  @override
  Future<bool> isOnboarded({String? atSign}) {
    // TODO: implement isOnboarded
    throw UnimplementedError();
  }

  @override
  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest atOnboardingRequest) async {
    var atSign = atOnboardingRequest.atSign;
    var onboardingResponse = AtOnboardingResponse(atSign);

    try {
      _atLookup ??= AtLookupImpl(
          atSign,
          atOnboardingRequest.preference.rootDomain,
          atOnboardingRequest.preference.rootPort);
      cramAuthenticator ??= CramAuthenticator(
          atOnboardingRequest.preference.cramSecret!,
          atOnboardingRequest.preference)
        ..atLookup = _atLookup;
      final cramAuthResult =
          await cramAuthenticator!.authenticate(atOnboardingRequest.atSign);
      _logger.finer('cram auth result for $atSign : $cramAuthResult');
      if (cramAuthResult.isSuccessful) {
        await _activateNewAtSign(atOnboardingRequest);
      }
      throw AtClientException(
          error_codes['UnAuthenticatedException'], 'cram auth failed');
    } on AtClientException catch (e) {
      _logger
          .severe('exception in onboard -_activateNewAtSign : ${e.toString()}');
      rethrow;
    }
  }

  Future<void> _activateNewAtSign(AtOnboardingRequest onboardingRequest) async {
    try {
      // 1. generate pkam keypair/read public key from secure element using atChops
      var atSecurityKeys = AtSecurityKeys();
      if (onboardingRequest.authMode == PkamAuthMode.sim) {
        if (atChops == null) {
          throw AtClientException(error_codes['AtClientException'],
              'atChops instance not set when auth mode is sim');
        }
        if (onboardingRequest.publicKeyId == null) {
          throw AtClientException(error_codes['AtClientException'],
              'publicKeyId from secure element has to be set when auth mode is sim');
        }
        atSecurityKeys.apkamPublicKey =
            atChops!.readPublicKey(onboardingRequest.publicKeyId!);
      } else {
        var pkamKeypair = _keyChainManager.generateKeyPair();
        atSecurityKeys.apkamPublicKey = pkamKeypair.publicKey.toString();
        atSecurityKeys.apkamPrivateKey = pkamKeypair.privateKey.toString();
        atChops ??= _createAtChops(
            null,
            AtPkamKeyPair.create(
                atSecurityKeys.apkamPublicKey!,
                atSecurityKeys
                    .apkamPrivateKey!)); // set encryption key pair after generation
      }
      //1.1 generate encryption key pair, self encryption key and AES key
      var encryptionKeyPair = _keyChainManager.generateKeyPair();
      atSecurityKeys.defaultEncryptionPublicKey =
          encryptionKeyPair.publicKey.toString();
      atSecurityKeys.defaultEncryptionPrivateKey =
          encryptionKeyPair.privateKey.toString();
      // var selfEncryptionKey = _keyChainManager.getSelfEncryptionAESKey(atSign);
      // var apkamSymmetricKey = generateAESKey();
      //2.Send enroll request
      var enrollBuilder = EnrollVerbBuilder()
        ..appName = onboardingRequest.preference.appName
        ..deviceName = onboardingRequest.preference.deviceName;

      enrollBuilder.encryptedDefaultEncryptedPrivateKey =
          EncryptionUtil.encryptValue(
              atSecurityKeys.defaultEncryptionPrivateKey!,
              atSecurityKeys.apkamSymmetricKey!);
      enrollBuilder.encryptedDefaultSelfEncryptionKey =
          EncryptionUtil.encryptValue(atSecurityKeys.defaultSelfEncryptionKey!,
              atSecurityKeys.apkamSymmetricKey!);
      enrollBuilder.apkamPublicKey = atSecurityKeys.apkamPublicKey;
    } on AtClientException {
      rethrow;
    }
  }

  AtChops _createAtChops(
      AtEncryptionKeyPair? atEncryptionKeyPair, AtPkamKeyPair atPkamKeyPair) {
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    final atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }
}
