import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Represents an authentication request of an atSign.
class AtAuthRequest {
  /// The atSign for authentication
  String atSign;

  /// Constructor that takes an @sign as a parameter
  AtAuthRequest(this.atSign);

  // Controls how the authentication is performed
  AtKeysIo? atKeysIo;

  /// The default domain of the root server (e.g. root.atsign.org, 64)
  AtRootDomain rootDomain = AtRootDomain('root.atsign.org', 64);

  /// The enrollmentId for APKAM authentication
  String? enrollmentId;

  /// The keys for authentication of an atSign.
  AtKeys? atAuthKeys;

  /// The contents of .atKeys file which contains the encrypted atKeys.
  Map<String, dynamic>? encryptedKeysMap;

  /// public key id from secure element if [authMode] is [PkamAuthMode.sim]
  String? publicKeyId;

  /// Signing algorithm to use for pkam authentication
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Hashing algorithm to use for pkam authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;

  /// The pass phrase to password protect the AtKeys file.
  String? passPhrase;
}
