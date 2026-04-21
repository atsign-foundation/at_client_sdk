import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/decryption_service/generic_key_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_by_me_decryption.dart';
import 'package:at_client/src/decryption_service/shared_with_me_decryption.dart';
import 'package:at_commons/at_commons.dart';

class AtKeyDecryptionBuilder {
  static AtKeyDecryption build(AtKey key, AtClient atClient) {
    AppMetadata? meta = key.metadata.appMetadata;
    if (meta == null) {
      //legacy implementation
      Atsign myAtsign = atClient.getCurrentAtSign()!.toAtsign();
      if (key.sharedBy != myAtsign) {
        return SharedWithMeDecryption(atClient);
      }
      // Shared by me with others
      if (key.sharedWith != null && key.sharedWith != myAtsign) {
        return SharedByMeDecryption(atClient);
      }
      // Shared by me with myself
      // Eg: currentAtSign is @bob and _phone.wavi@bob (or) phone@bob (or) @bob:phone@bob
      if (((key.sharedWith == null || key.sharedWith == myAtsign) &&
              key.sharedBy == myAtsign) ||
          key.key.startsWith('_')) {
        return SelfKeyDecryption(atClient);
      }
      throw Exception(
          'Legacy $key is neither sharedByMe, sharedWithMe nor self');
    } else {
      return GenericKeyDecryption(atClient);
    }
  }
}
