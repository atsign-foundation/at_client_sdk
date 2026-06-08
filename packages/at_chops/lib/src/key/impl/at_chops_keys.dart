import 'package:at_chops/src/key/at_key_pair.dart';
import 'package:at_chops/src/key/impl/at_encryption_key_pair.dart';
import 'package:at_chops/src/key/impl/at_ml_kem_768_key_pair.dart';
import 'package:at_chops/src/key/impl/at_pkam_key_pair.dart';
import 'package:at_chops/src/key/impl/at_signing_key_pair.dart';
import 'package:at_chops/src/key/impl/at_x25519_key_pair.dart';

class AtChopsKeys {
  /// Default encryption key pair
  AtEncryptionKeyPair? atEncryptionKeyPair;

  /// Key pair for pkam authentication. Can be legacy pkam keypair or apkam keypair for new enrollment
  AtPkamKeyPair? _atPkamKeyPair;

  /// Key pair for data signing and verification
  AtSigningKeyPair? atSigningKeyPair;

  /// X25519 key pair for Diffie–Hellman key agreement
  AtX25519KeyPair? atX25519KeyPair;

  /// ML-KEM-768 key pair for post-quantum key encapsulation
  AtMlKem768KeyPair? atMlKem768KeyPair;

  /// Default self encryption key
  SymmetricKey? selfEncryptionKey;

  /// APKAM symmetric key created during new enrollment
  SymmetricKey? apkamSymmetricKey;

  AtChopsKeys.create(this.atEncryptionKeyPair, this._atPkamKeyPair);

  AtChopsKeys();

  AtPkamKeyPair? get atPkamKeyPair => _atPkamKeyPair;
}
