import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

class AtOnboardingRequest {
  String atSign;

  AtOnboardingRequest(
    this.atSign, {
    this.rootDomain = const AtRootDomain('root.atsign.org', 64),
    this.appName = "system",
    this.deviceName = "default-device",
    this.atKeysIo,
    this.atKeys,
  });

  // Default root domain and port
  AtRootDomain rootDomain;
  String? appName;
  String? deviceName;

  AtKeysIo? atKeysIo;

  AtKeys? atKeys;

  /// Signing algorithm to use for cram authentication
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Hashing algorithm to use for cram authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;
}
