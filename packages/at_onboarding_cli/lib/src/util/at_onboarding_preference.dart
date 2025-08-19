import 'dart:core';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/util/registrar_api_constants.dart';

class AtOnboardingPreference extends AtClientPreference {
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
