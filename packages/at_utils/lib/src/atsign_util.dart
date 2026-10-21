import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:crypto/crypto.dart';

/// Utility class for atSign operations
class AtUtils {
  static final AtUtils _singleton = AtUtils._internal();

  factory AtUtils() {
    return _singleton;
  }

  AtUtils._internal();

//  static void logPrint(String s) {
//    // ignore: omit_local_variable_types
//    DateTime now = DateTime.now();
//    var t = now.toUtc();
//    print('$t : $s');
//  }

  /// [atSign] normalised and validated exactly as [AtsignString.toAtsign]
  /// does, throwing [InvalidAtSignException] when it is not an atSign.
  static String fixAtSign(String atSign) => atSign.toAtsign();

  static String getShaForAtSign(String atsign) {
    // encode the given atsign
    var bytes = utf8.encode(atsign);
    return sha256.convert(bytes).toString();
  }
}
