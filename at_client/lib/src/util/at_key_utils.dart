import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

class KeyUtil {
  // 1. phone.buzz@
  // 2. phone.buzz.pqr - AtKey supply ..namespace
  // 3. phone.buzz <pref namespace>Pref namespace

  static void setNamespace(AtKey atKey, AtClientPreference atClientPreference) {
    // Do not append namespace for encryption keys.
    if (!(atKey.metadata!.namespaceAware)) {
      return;
    }
    //Do not append namespace if already appended
    if (atKey.key?.substring(atKey.key!.lastIndexOf('.') + 1) ==
        atClientPreference.namespace) {
      return;
    }
    // If key is fully qualified, remove the '@' and return the atKey.
    if (KeyUtil.isFullyQualified(atKey.key!)) {
      atKey.key = KeyUtil.getQualified(atKey.key!);
      return;
    }
    // If key does not have any namespace, append the namespace to the key.
    if (atKey.namespace != null && atKey.namespace!.isNotEmpty) {
      atKey.key = '${atKey.key}.${atKey.namespace!}';
      return;
    }
    if (atClientPreference.namespace != null &&
        atClientPreference.namespace!.isNotEmpty) {
      atKey.key = '${atKey.key}.${atKey.namespace!}';
    }
  }

  static bool isFullyQualified(String key) {
    return key.endsWith("@");
  }

  static String getQualified(String key) {
    return key.substring(0, key.length - 1);
  }

  /// Sets the default values for the AtKey.
  static void prepareAtKey(AtKey atKey) {
    if (atKey.sharedWith != null) {
      atKey.sharedWith = AtUtils.formatAtSign(atKey.sharedWith);
    }
    atKey.sharedBy ??=
        AtClientManager.getInstance().atClient.getCurrentAtSign();
    // For the PKAM private keys, sharedBy is set to null.
    if (atKey.key!.startsWith(AT_PKAM_PRIVATE_KEY) ||
        atKey.key!.startsWith(AT_PKAM_PUBLIC_KEY)) {
      atKey.sharedBy = null;
    }
    // If metadata is null for atKey, add a new instance.
    atKey.metadata ??= Metadata();
    // If key is hidden key, prefix '_'
    if (AtKey is PrivateKey || atKey.metadata!.isHidden) {
      atKey.key = '_' + atKey.key!;
    }
  }
}
