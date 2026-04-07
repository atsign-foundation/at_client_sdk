import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/decryption_service/shared_by_me_decryption.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_with_me_decryption.dart';

///The manager class for [AtKeyDecryption]
class AtKeyDecryptionManager {
  final AtClient _atClient;

  AtKeyDecryptionManager(this._atClient);

  /// Return the relevant instance of [AtKeyDecryption] for the given [AtKey]
  AtKeyDecryption get(AtKey atKey) {
    Atsign myAtsign = _atClient.getCurrentAtSign()!.toAtsign();

    // Shared by others with me
    if (atKey.sharedBy != myAtsign) {
      return SharedWithMeDecryption(_atClient);
    }

    // Shared by me with others
    if (atKey.sharedWith != null && atKey.sharedWith != myAtsign) {
      return SharedByMeDecryption(_atClient);
    }

    // Shared by me with myself
    // Eg: currentAtSign is @bob and _phone.wavi@bob (or) phone@bob (or) @bob:phone@bob
    if (((atKey.sharedWith == null || atKey.sharedWith == myAtsign) &&
            atKey.sharedBy == myAtsign) ||
        atKey.key.startsWith('_')) {
      return SelfKeyDecryption(_atClient);
    }

    throw Exception('$atKey is neither sharedByMe, sharedWithMe nor self');
  }
}
