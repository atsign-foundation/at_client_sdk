import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/response/at_notification.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/transformer/at_transformer.dart';

/// Decrypts a notification's value or text message.
///
/// The notification passed in is left unchanged and a transformed copy is
/// returned, so the notification can still be handed on as it arrived.
class NotificationResponseTransformer
    implements
        Transformer<Tuple<AtNotification, NotificationConfig>, AtNotification> {
  late final AtClient _atClient;

  NotificationResponseTransformer(this._atClient);

  @override
  Future<AtNotification> transform(
      Tuple<AtNotification, NotificationConfig> tuple) async {
    // prepare the atKey from the atNotification object.
    final atNotification = copyOf(tuple.one);
    NotificationConfig notificationConfig = tuple.two;
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
      ..sharedBy = atNotification.from;

    // NOTE: the key string still carries its namespace suffix. Crypto routing
    // is `(owner, namespace)` scoped and the nskey providers refuse a value
    // without a namespace, so leaving it null makes such a notification
    // unreadable. Splitting at the last dot matches AtKey.fromString, and
    // toString() recomposes the key unchanged.
    final namespaceIndex = atKey.key.lastIndexOf('.');
    if (namespaceIndex > -1) {
      atKey.namespace = atKey.key.substring(namespaceIndex + 1);
      atKey.key = atKey.key.substring(0, namespaceIndex);
    }

    if (atNotification.metadata != null) {
      atKey.metadata = atNotification.metadata!;
    }

    if (decryptsKey(atNotification)) {
      // decrypt the text message;
      var decryptedValue = await _getDecryptedValue(atKey, atKey.key);
      atNotification.key = '${atNotification.to}:$decryptedValue';
      return atNotification;
    }
    if (atNotification.value.isNotNull &&
        atNotification.id != '-1' &&
        // The shared_key (which is a reserved key) has different decryption process
        // and is not a user created key.
        // Hence do not decrypt if key's are reserved keys
        AtKey.getKeyType(atKey.toString()) != KeyType.reservedKey) {
      // decrypt the notification value only if isEncrypted is not set to false and shouldDecrypt is set to true
      if (atNotification.isEncrypted != false &&
          notificationConfig.shouldDecrypt) {
        atNotification.value =
            await _getDecryptedValue(atKey, atNotification.value!);
      }
      return atNotification;
    }
    return atNotification;
  }

  /// Whether [n] is an encrypted text message, whose key is the ciphertext
  /// and is decrypted whatever the subscriber asked for.
  static bool decryptsKey(AtNotification n) =>
      n.messageType.isNotNull &&
      n.messageType!.toLowerCase().contains('text') &&
      n.isEncrypted == true;

  /// A copy of [n]. Its [AtNotification.metadata] is the same instance.
  static AtNotification copyOf(AtNotification n) => AtNotification(
      n.id, n.key, n.from, n.to, n.epochMillis, n.messageType, n.isEncrypted,
      value: n.value,
      operation: n.operation,
      expiresAtInEpochMillis: n.expiresAtInEpochMillis,
      metadata: n.metadata)
    ..status = n.status;

  Future<String> _getDecryptedValue(AtKey atKey, String? encryptedValue) async {
    final decrypted = await CryptoRuntime(_atClient)
        .decryptForNotification(atKey, encryptedValue?.trim());
    return decrypted.toString().trim();
  }
}
