import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class PkamAuthenticator {
  PkamAuthenticator();

  Future<bool> authenticate(String atSign, AtLookUp atLookup) async {
    try {
      return await atLookup.pkamAuthenticate();
    } catch (e, s) {
      throw UnAuthenticatedException(
          'pkam auth failed for $atSign - ${e.toString()} \n $s');
    }
  }
}
