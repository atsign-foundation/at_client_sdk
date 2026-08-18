import 'dart:core';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/util/registrar_api_constants.dart';

class AtOnboardingPreference extends AtClientPreference {
  /// Forwards every flag `AtClientPreference` fixes at construction.
  ///
  /// Without this the class inherited the implicit no-arg constructor, and
  /// since `posture`, `disallowLegacyEncryption`, `signingRollout` and
  /// `dataSigningKeyAlgorithms` are all final in the superclass, **no CLI
  /// application could set any of them** — not by assignment afterwards, which
  /// the finality forbids, and not at construction, which took no arguments.
  /// They are final for a reason worth keeping: what a client writes must not
  /// change meaning mid-run. The mutable fields beside them (`crypto`,
  /// `seedNamespaceKeys`, and this class's own) are unaffected and are
  /// deliberately not repeated here.
  ///
  /// It reached every `at_cli_commons` consumer, because `CLIBase` accepts a
  /// preference and falls back to `AtOnboardingPreference()`: an app could
  /// hand one in, and the one it handed in could not differ from the default.
  ///
  /// Every parameter is optional and the superclass supplies each default, so
  /// `AtOnboardingPreference()` means exactly what it always did.
  AtOnboardingPreference({
    super.posture,
    super.disallowLegacyEncryption,
    super.signingRollout,
    super.dataSigningKeyAlgorithms,
  });

  /// specify path of .atKeysFile containing encryption keys
  String? atKeysFilePath;

  /// specify path of qr code containing cram secret
  @Deprecated('qr_code based cram authentication not supported anymore')
  String? qrCodePath;

  PkamAuthMode authMode = PkamAuthMode.keysFile;

  /// if [authMode] is sim, specify publicKeyId to be read from sim
  String? publicKeyId;

  bool skipSync = false;

  /// the hostName of the registrar which will be used to activate the atsign
  String registrarUrl = RegistrarApiConstants.apiHostProd;

  String? appName;

  String? deviceName;

  @Deprecated("No longer used")
  int apkamAuthRetryDurationMins = 30;

  /// Flag to indicate if we're using a proxy server for connection
  bool get isUsingProxy => rootDomain.startsWith("proxy:");

  /// The password (or pass-phrase) with which the atKeys file is encrypted/decrypted.
  String? passPhrase;
}
