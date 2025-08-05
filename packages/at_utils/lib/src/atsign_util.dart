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

  /// Apply all the rules on the provided atSign and return fixedAtSign
  static String fixAtSign(String atSign) {
    // @signs are always lowercase Latin
    if (atSign == '' || atSign.isEmpty) {
      throw InvalidAtSignException(AtMessage.noAtSign.text);
    }
    atSign = atSign.toLowerCase();
    // if atsign does not start with '@' prepend an '@'
    if (!atSign.startsWith('@')) {
      atSign = '@$atSign';
    }
    // @signs can only have one @ character in them
    var noAT = atSign.replaceFirst('@', '');
    if (noAT.contains(RegExp(r'@'))) {
      throw InvalidAtSignException(AtMessage.moreThanOneAt.text);
    }
    // The dot "." can be used in an @sign but it is removed so @colinconstable is the same as @colin.constable
    // home.phone@colin stays home.phone@colin
    // but home.phone@colin.constable gets translated to home.phone@colinconstable
    // This is for clarity for humans
    var split = atSign.split('@');
    var left = split[0].toString();
    var right = split[1].toString();
    right = right.replaceAll(r'.', '');
    if (right.isEmpty) {
      throw InvalidAtSignException(AtMessage.noAtSign.text);
    }
    // reconstruct @sign
    atSign = '$left@$right';
    // Some Characters are reserved
    // If found the @sign should be rejected
    if (atSign.contains(RegExp(r"[\!\*\'`\(\)\;\:\&\=\+\$\,\/\?\#\[\]\{\}]"))) {
      throw InvalidAtSignException(AtMessage.reservedCharacterUsed.text);
    }
    // White spaces are not allowed in @signs
    // If found the @sign should be rejected
    // SPACE,TAB,LINEFEED etc
    // Ref https://en.wikipedia.org/wiki/Whitespace_character
    if (atSign.contains(RegExp(
        r'[\u0020\u0009\u000A\u000B\u000C\u000D\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000]'))) {
      throw InvalidAtSignException(AtMessage.whiteSpaceNotAllowed.text);
    }
    // ASCII control Characters are not allowed in @signs!
    if (atSign.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      throw InvalidAtSignException(AtMessage.controlCharacter.text);
    }
    // Unicode control Characters are not allowed in @signs
    if (atSign.contains(RegExp(r'[\u2400-\u241F\u2400\u2421\u2424\u2425]'))) {
      throw InvalidAtSignException(AtMessage.controlCharacter.text);
    }
    return atSign;
  }

  /// Return AtSign by appending '@' at the beginning if not present
  @Deprecated('Use fixAtSign()')
  static String? formatAtSign(String? atSign) {
    // verify whether atSign started with '@' or not
    if ((atSign != null && atSign.isNotEmpty) && !atSign.startsWith('@')) {
      atSign = '@$atSign';
    }
    return atSign;
  }

  static String getShaForAtSign(String atsign) {
    // encode the given atsign
    var bytes = utf8.encode(atsign);
    return sha256.convert(bytes).toString();
  }
}
