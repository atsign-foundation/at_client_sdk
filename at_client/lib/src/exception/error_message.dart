enum Intent { shareData, remoteLookup, localLookup, notify, sync }

///
class ErrorMessage {
  static String msgPublicKeyNotFound =
      'Public key not found for the atSign {receiverAtSign}';
  static String msgInvalidKey = 'Key {key} is not a valid key';
  static String msgValueExceedingBufferLimit = 'value exceeds max allowed size';
  static String nullKeyFormed =
      'Key {key} cannot be null or empty for {currentAtSign}';
}

class IntentMessage {
  static final Map<Intent, String> _intentMessage = {
    Intent.shareData: 'Data could not be shared to {receiverAtSign}',
    Intent.remoteLookup: 'Data cannot be fetched from {currentAtSign}',
    Intent.notify: 'Data cannot be notify to {receiverAtSign}'
  };

  static String getMessage(Intent intent) {
    return _intentMessage[intent]!;
  }
}
