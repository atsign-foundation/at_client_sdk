import 'dart:core';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/util/registrar_api_constants.dart';

class AtOnboardingPreference extends AtClientPreference {
  /// Forwards every flag `AtClientPreference` fixes at construction.
  ///
  /// These are final in the superclass — what a client writes must not change
  /// meaning mid-run — so construction is the only place to set them. Each is
  /// optional and defaulted by the superclass.
  AtOnboardingPreference({
    super.posture,
    super.authenticationKeyAlgorithm,
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

  /// Where to put the client's local storage when no [storage] is supplied.
  ///
  /// Defaults to a per-atSign directory under the user's home. The bundle
  /// built here is closed by the client when it stops, so a CLI has nothing to
  /// tear down.
  String? storagePath;

  /// The local storage the client should use, which decides the backend and
  /// the location and so leaves [storagePath] unread.
  ///
  /// Borrowed unless it was built with `closedByClient: true`: by default the
  /// client detaches from it when it stops and closing it is the caller's job.
  /// Leave it null and a Hive bundle is built under [storagePath], which the
  /// client closes itself.
  AtClientStorage? storage;

  /// The store a client for [atSign] opens: [storage] when set, else a fresh
  /// Hive store under [storagePath] that the client closes when it stops.
  ///
  /// Fresh each call, because a closed store cannot reopen and every client
  /// this package opens closes the store it was given.
  AtClientStorage storageFor(String atSign) =>
      storage ??
      HiveAtClientStorage(
          atSign: atSign, storagePath: storagePath!, closedByClient: true);
}
