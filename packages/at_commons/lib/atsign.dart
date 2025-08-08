import 'package:at_commons/at_commons.dart';

/// A fully qualified atSign (e.g. @alice)
typedef Atsign = String;

/// An atSign without the "@" (e.g. alice)
typedef AtsignWithoutAt = String;

extension AtsignString on String {
  /// Format and validate string to a fully qualified atSign
  /// throws [InvalidAtSignException] on failed validation
  Atsign toAtsign() {
    return _fixAtSign(this);
  }

  /// Format and validate string to an atSign without the "@" prefix
  /// throws [InvalidAtSignException] on failed validation
  AtsignWithoutAt withoutAt() {
    return toAtsign().substring(1);
  }
}

Atsign _fixAtSign(String atSign) {
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
