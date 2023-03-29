import 'package:at_chops/src/at_chops_base.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_service_v2.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_client_mobile/src/auth/cram_authenticator.dart';
import 'package:at_client_mobile/src/auth/pkam_authenticator.dart';
import 'package:at_utils/at_logger.dart';

class AtClientServiceImpl implements AtClientServiceV2 {
  final AtSignLogger _logger = AtSignLogger('AtClientServiceImpl');

  @override
  AtChops? atChops;

  final _keyChainManager = KeyChainManager.getInstance();

  late final PkamAuthenticator _pkamAuthenticator;

  late final CramAuthenticator _cramAuthenticator;

  // final _atClientManager = AtClientManager.getInstance();

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
  Future<AtLoginResponse> login(AtLoginRequest atLoginRequest) async {
    final atLoginResponse = AtLoginResponse(atLoginRequest.atSign);
    if (await isOnboarded(atSign: atLoginRequest.atSign)) {
      try {
        final pkamAuthResult =
            await _pkamAuthenticator.authenticate(atLoginRequest.atSign);
        atLoginResponse.isSuccessful = pkamAuthResult.authResult;
      } on AtClientException catch (e) {
        atLoginResponse.isSuccessful = false;
        atLoginResponse.atException = e;
        return atLoginResponse;
      }
      return atLoginResponse;
    }
    // read keysfile data
    // pkamAuthenticator.authenticate(..) calls internal signing or delegates to secure element based on at_chops
    // persist keys to biometric/local secondary
    // return loginResponse;
    throw UnimplementedError();
  }

  @override
  Future<bool> onboard(AtOnboardingRequest atOnboardingRequest) async {
    var atSign = atOnboardingRequest.atSign;
    if (await isOnboarded(atSign: atSign)) {
      final pkamAuthResult = await _pkamAuthenticator.authenticate(atSign!);
      return pkamAuthResult.authResult;
    }
    _activateNewAtSign(atOnboardingRequest);

    // if exception return false;
    return true;
  }

  Future<void> _activateNewAtSign(AtOnboardingRequest onboardingRequest) async {
    // 1. cram auth
    _cramAuthenticator.authenticate(onboardingRequest.atSign);
    // 2. pkamAuthenticator.authenticate(atSign);
    // 3. persist keys to biometric/local secondary
    // 4. delete cram if pkam is successful - calls internal signing or delegates to secure element based on at_chops
  }

  bool _isNotEmpty(String? key) {
    return key != null && key.isNotEmpty;
  }
}
