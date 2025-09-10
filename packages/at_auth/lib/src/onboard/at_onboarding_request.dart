import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

class AtOnboardingRequest {
  String atSign;
  AtOnboardingRequest(this.atSign);
  PkamAuthMode authMode = PkamAuthMode.keysFile;

  // Default root domain and port
  AtRootDomain rootDomain = AtRootDomain('root.atsign.org', 64);
  String? appName;
  String? deviceName;

  /// Signing algorithm to use for cram authentication
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Hashing algorithm to use for cram authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;
}
