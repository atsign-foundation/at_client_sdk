import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:meta/meta.dart';

/// Class is responsible for decrypting the notification value/text-message data
class NotificationResponseTransformer
    implements
        Transformer<Tuple<AtNotification, NotificationConfig>, AtNotification> {
  late final AtClient _atClient;

  @visibleForTesting
  AtKeyDecryption? atKeyDecryption;

  NotificationResponseTransformer(this._atClient);

  @override
  Future<AtNotification> transform(
      Tuple<AtNotification, NotificationConfig> tuple) async {
    // prepare the atKey from the atNotification object.
    AtNotification atNotification = tuple.one;
    NotificationConfig config = tuple.two;
    String sharedBy = atNotification.from;
    String sharedWith = atNotification.to;
    var key = atNotification.key;
    // AtKeys when sharedBy and sharedWith are populated look like
    // @alice:something.something.namespace@bob
    // where @bob is sharedBy and @alice is sharedWith

    // Because of history, the 'key' here sometimes (always?) also contains
    // the sharedBy and sharedWith and we will end up creating AtKeys which look like
    // '@alice@alice:something.something.namespace@bob@bob' unless we prevent it here.

    // If we've already got sharedBy in the 'key' part, then strip it off
    // before creating the AtKey
    // e.g. ends with '@bob' (note no colon preceding)
    if (sharedBy.trim().isNotEmpty && key.endsWith(sharedBy)) {
      key = key.substring(0, key.length - sharedBy.length);
    }
    // If we've already got sharedWith in the 'key' part, then strip it off
    // before creating the AtKey
    // e.g. starts with '@alice:' (note the colon)
    if (sharedWith.trim().isNotEmpty && key.startsWith(sharedWith)) {
      key = key.substring(
          sharedWith.length + 1); // substring from just after '@alice:'
    }
    AtKey atKey = AtKey()
      ..key = key
      ..sharedWith = atNotification.to
      ..sharedBy = atNotification.from
      ..metadata = atNotification.metadata;

    if (atNotification.messageType.isNotNull &&
        atNotification.messageType!.toLowerCase().contains('text') &&
        (atNotification.isEncrypted != null && atNotification.isEncrypted!)) {
      // decrypt the text message;
      var decryptedValue = await _getDecryptedValue(atKey, atKey.key);
      atNotification.key = '${atNotification.to}:$decryptedValue';
      return atNotification;
    } else if ((atNotification.value.isNotNull) &&
        (config.shouldDecrypt && atNotification.id != '-1') &&
        // The shared_key (which is a reserved key) has different decryption process
        // and is not a user created key.
        // Hence do not decrypt if key's are reserved keys
        AtKey.getKeyType(atKey.toString()) != KeyType.reservedKey) {
      // decrypt the value
      atNotification.value =
          await _getDecryptedValue(atKey, atNotification.value!);
      return atNotification;
    }
    return atNotification;
  }

  Future<String> _getDecryptedValue(AtKey atKey, String? encryptedValue) async {
    atKeyDecryption ??=
        AtKeyDecryptionManager(_atClient).get(atKey, atKey.sharedWith!);
    var decryptedValue =
        await atKeyDecryption?.decrypt(atKey, encryptedValue?.trim());
    // Return decrypted value
    return decryptedValue.toString().trim();
  }
}
