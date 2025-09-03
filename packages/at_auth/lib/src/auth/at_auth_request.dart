import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Represents an authentication request of an atSign.
class AtAuthRequest {
  /// The atSign for authentication
  String atSign;

  /// Constructor that takes an @sign as a parameter
  AtAuthRequest(this.atSign);

  PkamAuthMode authMode = PkamAuthMode.keysFile;

  /// The default host of the root server
  String rootDomain = 'root.atsign.org';

  /// The default port of the root server
  int rootPort = 64;

  /// The enrollmentId for APKAM authentication
  String? enrollmentId;

  /// The keys for authentication of an atSign.
  AtKeys? atKeys;

  /// The file path which contains the .atKeys file for authentication.
  String? atKeysFilePath;

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
