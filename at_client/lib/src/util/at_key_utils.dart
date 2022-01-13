import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';

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
    if (atKey.key.substring(atKey.key.lastIndexOf('.') + 1) ==
        atClientPreference.namespace) {
      return;
    }
    // If key is fully qualified, remove the '@' and return the atKey.
    if (KeyUtil.isFullyQualified(atKey.key)) {
      atKey.key = KeyUtil.getQualified(atKey.key);
      return;
    }
    // If key does not have any namespace, append the namespace to the key.
    if (atKey.namespace != null && atKey.namespace!.isNotEmpty) {
      atKey.key += '.${atKey.namespace!}';
      return;
    }
    if (atClientPreference.namespace != null &&
        atClientPreference.namespace!.isNotEmpty) {
      atKey.key += '.${atClientPreference.namespace!}';
    }
  }

  static bool isFullyQualified(String key) {
    return key.endsWith("@");
  }

  static String getQualified(String key) {
    return key.substring(0, key.length - 1);
  }
}
