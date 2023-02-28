import 'package:at_client_mobile/at_client_mobile.dart';

abstract class AtAuthenticator {
  Future<AtAuthResult> authenticate(String atSign);
}


class AtAuthResult {
  bool authResult=false;
  AtClientException? atClientException;
}
