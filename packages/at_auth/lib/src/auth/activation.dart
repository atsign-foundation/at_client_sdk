import 'dart:async';

import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

/// Activates [atSign] with its one-time CRAM secret and writes the keys it
/// mints into [keys]: the atSign's first enrollment, which the atServer
/// grants everything.
///
/// The steps, in order: wait for the atServer to be reachable and in its
/// unactivated state, authenticate with the secret, mint the key material,
/// submit the first enrollment (auto-approved on a CRAM connection),
/// authenticate again as that enrollment, write [keys], and unless
/// [completeActivation] is false publish the encryption public key and
/// delete the secret from the atServer. Returns the enrollment id.
///
/// [signingAlgo] is the APKAM algorithm the atSign authenticates with from
/// now on: `rsa2048` for a legacy activation, `mldsa65` for a post-quantum
/// one. [mintLegacyMaterial] cuts the RSA encryption keypair and the
/// self-encryption key; null means yes, since whether this atSign will ever
/// talk to a legacy peer is decided by the apps that adopt it.
/// [metadataBuilder] and [advertisedSigningKey] ride the first enrollment's
/// request; a post-quantum activation supplies both, and they must name the
/// same signing key.
///
/// [retryOptions] bounds the wait for a newly registered atSign to be
/// provisioned, minutes by default. [onProgress] hears each step.
/// [atLookUp] is a connection to activate over, for a caller that already
/// holds one; it is taken as already having reached the atServer, so the
/// provisioning wait is skipped, and it is left open. With none, a
/// connection is built, and closed when this returns.
Future<String> activateAtSign({
  required String atSign,
  required String cramSecret,
  required WrittenAtKeysIo keys,
  required SigningAlgoType signingAlgo,
  AtRootDomain rootDomain = AtRootDomain.atsignDomain,
  String appName = 'firstApp',
  String deviceName = 'firstDevice',
  bool? mintLegacyMaterial,
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? metadataBuilder,
  ({
    SigningAlgoType algorithm,
    String publicKey,
    String privateKey
  })? advertisedSigningKey,
  RetryOptions retryOptions = RetryOptions.defaultRetryOptions,
  bool completeActivation = true,
  void Function(ProgressEvent event)? onProgress,
  AtLookUp? atLookUp,
}) async {
  final request = AtOnboardingRequest(atSign,
      signingAlgoType: signingAlgo,
      rootDomain: rootDomain,
      retryOptions: retryOptions,
      atKeysIo: keys)
    ..appName = appName
    ..deviceName = deviceName
    ..mintLegacyMaterial = mintLegacyMaterial
    ..metadataBuilder = metadataBuilder
    ..advertisedSigningKey = advertisedSigningKey;

  final auth = atLookUp == null
      ? AtAuthImpl()
      : _ConnectedActivation(atLookUp: atLookUp);
  final forward =
      onProgress == null ? null : auth.progressStream.listen(onProgress);
  try {
    final response = await auth.onboard(request, cramSecret,
        autoCompleteActivation: completeActivation);
    final enrollmentId = response.enrollmentId;
    if (!response.isSuccessful || enrollmentId == null) {
      throw AtAuthenticationException(
          'the activation of $atSign did not complete: $response');
    }
    return enrollmentId;
  } finally {
    if (forward != null) {
      // NOTE: the progress stream is a broadcast controller, which delivers
      // in a later turn; cancelling in the same turn as the last event drops
      // the completion the caller most wants to hear.
      await Future<void>.delayed(Duration.zero);
      await forward.cancel();
    }
    if (atLookUp == null) await auth.atLookUp?.close();
  }
}

/// An activation over a connection the caller supplied, which has already
/// reached the atServer: the provisioning wait, whose job is to find out
/// whether it can be reached, has nothing to wait for.
class _ConnectedActivation extends AtAuthImpl {
  _ConnectedActivation({required AtLookUp atLookUp})
      : super(atLookUp: atLookUp);

  @override
  Future<void> validateAtServer(AuthRequest atRequest) async {}
}
