import 'at_authenticator.dart';

class CramAuthenticator implements AtAuthenticator {
  String _cramSecret;
  CramAuthenticator(this._cramSecret);

  @override
  Future<AtAuthResult> authenticate(String atSign) {
    // TODO: implement authenticate
    throw UnimplementedError();
  }
}