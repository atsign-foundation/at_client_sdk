import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:meta/meta.dart';

class NotificationResponseTransformer
    implements
        Transformer<Tuple<AtNotification, NotificationConfig>, AtNotification> {
  @visibleForTesting
  AtKeyDecryption? atKeyDecryption;

  @override
  Future<AtNotification> transform(
      Tuple<AtNotification, NotificationConfig> tuple) async {
    // prepare the atKey from the atNotification object.
    var atNotification = tuple.one;
    AtKey atKey = AtKey()
      ..key = tuple.one.key
      ..sharedWith = tuple.one.to
      ..sharedBy = tuple.one.from;
    if (tuple.one.messageType.isNotNull &&
        tuple.one.messageType!.toLowerCase().contains('text') &&
        (tuple.one.isEncrypted != null && tuple.one.isEncrypted!)) {
      //decrypt the text message;
      var encryptedValue = atKey.key!.split(':')[1];
      var decryptedValue = await _getDecryptedValue(atKey, encryptedValue);
      atNotification.key = '${tuple.one.to}:$decryptedValue';
      return atNotification;
    } else if ((tuple.one.value.isNotNull) &&
        (tuple.two.shouldDecrypt && tuple.one.id != '-1')) {
      // decrypt the value
      atNotification.value = await _getDecryptedValue(atKey, tuple.one.value!);
      return atNotification;
    }
    return atNotification;
  }

  Future<String> _getDecryptedValue(AtKey atKey, String encryptedValue) async {
    atKeyDecryption ??= AtKeyDecryptionManager.get(atKey, atKey.sharedWith!);
    var decryptedValue = await atKeyDecryption?.decrypt(atKey, encryptedValue);
    // Return decrypted value
    return decryptedValue.toString().trim();
  }
}
