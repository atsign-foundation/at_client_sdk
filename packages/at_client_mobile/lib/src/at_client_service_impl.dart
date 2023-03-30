import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/at_chops_base.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_service_v2.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_client_mobile/src/auth/at_authenticator.dart';
import 'package:at_client_mobile/src/auth/cram_authenticator.dart';
import 'package:at_client_mobile/src/auth/pkam_authenticator.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class AtClientServiceImpl implements AtClientServiceV2 {
  final AtSignLogger _logger = AtSignLogger('AtClientServiceImpl');

  @override
  AtChops? atChops;

  final _keyChainManager = KeyChainManager.getInstance();

  late final PkamAuthenticator _pkamAuthenticator;

  late final CramAuthenticator _cramAuthenticator;

  final _atClientManager = AtClientManager.getInstance();

  @override
  Future<bool> isOnboarded({String? atSign}) async {
    // if atSign is not passed, read from keychain manager
    atSign ??= await _keyChainManager.getAtSign();
    if (atSign == null) {
      return false;
    }
    AtsignKey? atSignKey = await _keyChainManager.readAtsign(name: atSign);
    if (atSignKey == null) {
      return false;
    }
    // not checking pkam private key since it can be present in a secure element like a sim card
    if (_isNotEmpty(atSignKey.pkamPublicKey) &&
        _isNotEmpty(atSignKey.encryptionPrivateKey) &&
        _isNotEmpty(atSignKey.encryptionPublicKey) &&
        _isNotEmpty(atSignKey.selfEncryptionKey)) {
      return true;
    }
    return false;
  }

  @override
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    final atAuthResponse = AtAuthResponse(atAuthRequest.atSign);
    _pkamAuthenticator = PkamAuthenticator(AtLookupImpl(
        atAuthRequest.atSign,
        atAuthRequest.preference.rootDomain,
        atAuthRequest.preference.rootPort));
    if (await isOnboarded(atSign: atAuthRequest.atSign)) {
      try {
        final pkamAuthResult =
            await _pkamAuthenticator.authenticate(atAuthRequest.atSign);
        atAuthResponse.isSuccessful = pkamAuthResult.isSuccessful;
      } on AtClientException catch (e) {
        atAuthResponse.isSuccessful = false;
        atAuthResponse.atClientException = e;
      }
      return atAuthResponse;
    }
    // read keysfile data
    // pkamAuthenticator.authenticate(..) calls internal signing or delegates to secure element based on at_chops
    // persist keys to biometric/local secondary
    // return loginResponse;
    throw UnimplementedError();
  }

  @override
  Future<AtOnboardingResponse> onboard(
      AtOnboardingRequest atOnboardingRequest) async {
    var atSign = atOnboardingRequest.atSign;
    _pkamAuthenticator = PkamAuthenticator(AtLookupImpl(
        atOnboardingRequest.atSign,
        atOnboardingRequest.preference.rootDomain,
        atOnboardingRequest.preference.rootPort));
    var onboardingResponse = AtOnboardingResponse(atSign);
    if (await isOnboarded(atSign: atSign)) {
      final pkamAuthResult = await _pkamAuthenticator.authenticate(atSign);
      onboardingResponse.isSuccessful = pkamAuthResult.isSuccessful;
      return onboardingResponse;
    }
    try {
      await _activateNewAtSign(atOnboardingRequest);
    } on AtClientException catch (e) {
      _logger
          .severe('exception in onboard -_activateNewAtSign : ${e.toString()}');
      onboardingResponse.isSuccessful = false;
      return onboardingResponse;
    }

    return onboardingResponse;
  }

  Future<void> _activateNewAtSign(AtOnboardingRequest onboardingRequest) async {
    final atSign = onboardingRequest.atSign;
    try {
      // 1. cram auth
      final cramAuthResult =
          await _cramAuthenticator.authenticate(onboardingRequest.atSign);
      _logger.finer('cram auth result for $atSign : $cramAuthResult');

      // 2. generate pkam keypair and update pkam public key to server
      var pkamKeypair, pkamPublicKey, pkamPrivateKey;
      if (onboardingRequest.authMode == PkamAuthMode.sim) {
        if (atChops == null) {
          throw AtClientException(error_codes['AtClientException'],
              'atChops instance not set when auth mode is sim');
        }
        if (onboardingRequest.publicKeyId == null) {
          throw AtClientException(error_codes['AtClientException'],
              'publicKeyId from secure element has to be set when auth mode is sim');
        }
        pkamPublicKey = atChops!.readPublicKey(onboardingRequest.publicKeyId!);
      } else {
        pkamKeypair = _keyChainManager.generateKeyPair();
        pkamPublicKey = pkamKeypair.publicKey.toString();
        pkamPrivateKey = pkamKeypair.privateKey.toString();
        atChops ??= _createAtChops(
            null,
            AtPkamKeyPair.create(pkamPublicKey,
                pkamPrivateKey)); // set encryption key pair after generation
      }
      //#TODO test whether this update verb builder will generate the desired command
      var updatePkamPublicKeyResult =
          await _cramAuthenticator.atLookup!.executeVerb(UpdateVerbBuilder()
            ..atKey = AT_PKAM_PUBLIC_KEY
            ..value = pkamPublicKey);
      _logger.finer('updatePkamPublicKeyResult:  $updatePkamPublicKeyResult');

      // 3. pkam auth
      final pkamAuthResult = await _pkamAuthenticator.authenticate(atSign);
      _logger.finer('pkam auth result for $atSign: $pkamAuthResult');
      if (pkamAuthResult.isSuccessful == false) {
        throw AtClientException(error_codes['UnAuthenticatedException'],
            '_activateNewAtSign - initial pkam failed');
      }
      // 4. Generate encryption and self encryption key pair if pkam auth is successful and keysfile is not passed
      final encryptionKeyPair = _keyChainManager.generateKeyPair();
      final selfEncryptionKey = _keyChainManager.generateSelfEncryptionKey();
      atChops!.atChopsKeys.atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionKeyPair.publicKey.toString(),
          encryptionKeyPair.privateKey.toString());
      atChops!.atChopsKeys.symmetricKey = AESKey(selfEncryptionKey);
      await _init(atSign, onboardingRequest.preference);
      await _persistKeysToKeyChain(
          atSign,
          pkamPrivateKey,
          pkamPublicKey,
          encryptionKeyPair.privateKey.toString(),
          encryptionKeyPair.publicKey.toString(),
          selfEncryptionKey);
      // 5. persist keys to local secondary
      await _atClientManager.atClient.persistKeys(
          pkamPrivateKey,
          pkamPublicKey,
          encryptionKeyPair.privateKey.toString(),
          encryptionKeyPair.publicKey.toString(),
          selfEncryptionKey);

      //6. delete cram secret from server
      var deleteBuilder = DeleteVerbBuilder()..atKey = AT_CRAM_SECRET;
      var deleteResponse =
          await _cramAuthenticator.atLookup!.executeVerb(deleteBuilder);
      _logger.finer('delete cram secret response : $deleteResponse');
    } on AtClientException {
      rethrow;
    }
  }

  Future<void> _persistKeysToKeyChain(
      String atSign,
      String? pkamPrivateKey,
      String pkamPublicKey,
      String encryptionPrivateKey,
      String encryptionPublicKey,
      String selfEncryptionKey) async {
    var atSignItem = await _keyChainManager.readAtsign(name: atSign) ??
        AtsignKey(atSign: atSign);
    atSignItem = atSignItem.copyWith(
      pkamPrivateKey: pkamPrivateKey,
      pkamPublicKey: pkamPublicKey,
      encryptionPrivateKey: encryptionPrivateKey,
      encryptionPublicKey: encryptionPublicKey,
      selfEncryptionKey: selfEncryptionKey,
    );
    await _keyChainManager.storeAtSign(atSign: atSignItem);
  }

  bool _isNotEmpty(String? key) {
    return key != null && key.isNotEmpty;
  }

  Future<bool> _init(String atSign, AtClientPreference preference) async {
    preference.useAtChops = true;
    await _atClientManager.setCurrentAtSign(
        atSign, preference.namespace, preference,
        atChops: atChops);
    if (preference.outboundConnectionTimeout > 0) {
      _atClientManager.atClient
          .getRemoteSecondary()!
          .atLookUp
          .outboundConnectionTimeout = preference.outboundConnectionTimeout;
    }
    return true;
  }

  AtChops _createAtChops(
      AtEncryptionKeyPair? atEncryptionKeyPair, AtPkamKeyPair atPkamKeyPair) {
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    final atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }
}
