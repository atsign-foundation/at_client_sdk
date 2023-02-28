import 'package:at_chops/src/at_chops_base.dart';
import 'package:at_client_mobile/src/at_client_service_v2.dart';

class AtClientServiceImpl implements AtClientServiceV2 {
  @override
  AtChops? atChops;

  @override
  bool isOnboarded() {
    // TODO: implement isOnboarded
    // 1. check state in biometric / local storage
    throw UnimplementedError();
  }

  @override
  Future<AtLoginResponse> login(AtLoginRequest atLoginRequest) {
    // TODO: implement login
    if (isOnboarded()) {
      // pkamAuthenticator.authenticate(..);
      // return loginResponse;
    }
    // read keysfile data
    // pkamAuthenticator.authenticate(..) calls internal signing or delegates to secure element based on at_chops
    // persist keys to biometric/local secondary
    // return loginResponse;
    throw UnimplementedError();
  }

  @override
  bool onboard() {
    if (isOnboarded()) {
      // pkamAuthenticator.authenticate(atSign);
    }
    _activateNewAtSign();

    // if exception return false;
    return true;
  }

  Future<void> _activateNewAtSign() async {
    // 1. cram auth
    // 2. pkamAuthenticator.authenticate(atSign);
    // 3. persist keys to biometric/local secondary
    // 4. delete cram if pkam is successful - calls internal signing or delegates to secure element based on at_chops
  }
}
