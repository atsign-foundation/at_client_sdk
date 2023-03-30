import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/auth/at_authenticator.dart';
import 'package:at_client_mobile/src/auth/at_keys_source.dart';

abstract class AtClientServiceV2 {
  AtChops? atChops;
  //#TODO add documentation
  Future<AtAuthResponse> authenticate(AtAuthRequest atLoginRequest);
  Future<bool> isOnboarded({String? atSign});

  /// Onboard method is called when an atsign is activated for the first time in an app.
  /// Step 1. perform cram auth
  /// Step 2. generate pkam key pair (if pkam auth mode is [PkamAuthMode.keysFile])
  /// Step 3. read public key from secure element (if pkam auth mode is [PkamAuthMode.sim]) or use pkam public key from Step 2 and update to secondary server
  /// Step 4. perform pkam auth
  /// Step 5. Generate encryption keypair and self encryption key
  /// Step 6. Save key data to keychain and local secondary
  /// Step 7. delete cram secret from secondary server
  /// Set [atOnboardingRequest.publicKeyId] if pkam auth mode is [PkamAuthMode.sim]
  /// Set the AtClient preferences in [atOnboardingRequest.preference]
  Future<AtOnboardingResponse> onboard(AtOnboardingRequest atOnboardingRequest);
}

class AtOnboardingRequest {
  String atSign;
  AtOnboardingRequest(this.atSign, this.preference);
  AtClientPreference preference;
  PkamAuthMode authMode = PkamAuthMode.keysFile;

  /// public key id if [authMode] is [PkamAuthMode.sim]
  String? publicKeyId;
}

class AtOnboardingResponse {
  String atSign;
  AtOnboardingResponse(this.atSign);
  bool? isSuccessful;
  AtKeysFileData? atKeysData;
}

enum PkamAuthMode { keysFile, sim }
