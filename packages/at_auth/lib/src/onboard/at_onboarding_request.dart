import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

class AtOnboardingRequest {
  String atSign;
  AtOnboardingRequest(this.atSign);
  PkamAuthMode authMode = PkamAuthMode.keysFile;
  @Deprecated('no longer used')
  bool enableEnrollment = false;
  String rootDomain = 'root.atsign.org';
  int rootPort = 64;
  String? appName;
  String? deviceName;

  /// public key id if [authMode] is [PkamAuthMode.sim]
  String? publicKeyId;

  /// Signing algorithm to use for cram authentication
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Hashing algorithm to use for cram authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;
}
