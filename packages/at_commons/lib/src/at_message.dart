// ignore_for_file: unnecessary_string_escapes
enum AtMessage {
  wrongVerb,
  closingConnection,
  cleanExit,
  moreThanOneAt,
  whiteSpaceNotAllowed,
  reservedCharacterUsed,
  noAtSign,
  controlCharacter,
}

extension AtMessageExtension on AtMessage {
  String get text {
    const notFoundMsg = 'No message found';
    const wrongVerbMsg =
        'Available verbs are: lookup:, from:, pol:, llookup:, plookup:, update:, delete:, scan and exit. ';
    const closingConnectionMsg = 'Closing the connection. ';
    const cleanExitMsg = 'Exited cleanly, closing the connection. ';
    const moreThanOneAt =
        'invalid @sign: Cannot Contain more than one @ character';
    const whiteSpaceNotAllowed =
        'invalid @sign: Cannot Contain whitespace characters';
    const reservedCharacterUsed =
        'invalid @sign: Cannot contain \!\*\'`\(\)\;\:\&\=\+\$\,\/\?\#\[\]\{\} characters';
    const noAtSign =
        'invalid @sign: must include one @ character and at least one character on the right';
    const controlCharacter =
        'invalid @sign: must not include control characters';

    switch (this) {
      case AtMessage.wrongVerb:
        return wrongVerbMsg;
      case AtMessage.closingConnection:
        return closingConnectionMsg;
      case AtMessage.cleanExit:
        return cleanExitMsg;
      case AtMessage.moreThanOneAt:
        return moreThanOneAt;
      case AtMessage.whiteSpaceNotAllowed:
        return whiteSpaceNotAllowed;
      case AtMessage.reservedCharacterUsed:
        return reservedCharacterUsed;
      case AtMessage.noAtSign:
        return noAtSign;
      case AtMessage.controlCharacter:
        return controlCharacter;
      // ignore: unreachable_switch_default
      default:
        return notFoundMsg;
    }
  }
}
