

import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/src/auth/at_keys_source.dart';

import 'at_authenticator.dart';

class PkamAuthenticator implements AtAuthenticator {
  PkamKeySource _pkamKeySource;
  AtChops? _atChops;
  PkamAuthenticator(this._pkamKeySource, this._atChops);

  @override
  Future<AtAuthResult> authenticate(String atSign) {
    // TODO: implement authenticate
    throw UnimplementedError();
  }

}