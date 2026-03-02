import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class CramAuthenticator {
  CramAuthenticator();

  Future<bool> authenticate(
    String atSign,
    String cramSecret,
    AtLookUp atLookUp, {
    Duration retryInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 10,
  }) async {
    try {
      return await (atLookUp as AtLookupImpl).cramAuthenticate(cramSecret);
    } on UnAuthenticatedException catch (e) {
      throw UnAuthenticatedException(
          'cram auth failed for $atSign - ${e.toString()} with cramSecret $cramSecret');
    }
  }
}
