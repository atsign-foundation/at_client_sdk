import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/legacy/legacy_decryption.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:at_commons/at_commons.dart';

class LegacyCryptoScheme extends CryptoScheme {
  final AtClient _atClient;
  LegacyCryptoScheme(this._atClient);
  @override
  Future<dynamic> decrypt(AtKey atKey, value) {
    final legacy = LegacyDecryption.build(atKey, _atClient);
    return legacy.decrypt(atKey, value);
  }

  @override
  Future<dynamic> encrypt(AtKey atKey, value) {
    final legacy = LegacyEncryption.build(atKey, _atClient);
    return legacy.encrypt(atKey, value);
  }

  @override
  Future<void> register() async {
    // no need to register for legacy
    return;
  }
}
