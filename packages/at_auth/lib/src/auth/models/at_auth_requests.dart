import 'dart:async' show FutureOr;

import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

sealed class AuthRequest {
  String atSign;
  AtRootDomain rootDomain;
  String? namespace;

  AuthRequest(
    this.atSign, {
    this.retryOptions = RetryOptions.defaultRetryOptions,
    this.rootDomain = AtRootDomain.atsignDomain,
    this.namespace,
  });

  /// Options for retrying operations that validate atServer status' for Onboarding.
  RetryOptions retryOptions;

  /// Signing algorithm to use for pkam authentication.
  ///
  /// On an [AtOnboardingRequest] this also decides what the activation mints:
  /// `mldsa65` makes the atSign **PQ-native from activation** — the first
  /// enrollment's APKAM is an ML-DSA-65 keypair, filed as typed material under
  /// the enrollment id rather than in the flat `apkamPublicKey` /
  /// `apkamPrivateKey` fields, which stay empty.
  ///
  /// That shape is why this is opt-in rather than the default: a keyfile whose
  /// flat APKAM fields are absent makes any reader that calls
  /// `AtKeys.toAtChops()` fail loudly instead of signing an ML-DSA key with
  /// the RSA routine. Failing loudly is the point, but it is a behaviour
  /// change no minor release may impose on existing consumers.
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// Hashing algorithm to use for pkam authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;
}

class AtOnboardingRequest extends AuthRequest {
  /// Constructor for [AtOnboardingRequest]
  /// [atSign] is the atSign for onboarding
  ///
  /// optional:
  /// [rootDomain] is the default domain of the root server (e.g. root.atsign.org, 64)
  /// [appName] is the name of the app
  /// [deviceName] is the name of the device
  /// [atKeysIo] controls how AtKeys are loaded and saved (e.g. file system, keychain, secure element)

  AtOnboardingRequest(
    super.atSign, {
    super.rootDomain,
    super.retryOptions,
    this.atKeysIo,
  });

  // Default root domain and port
  String appName = "firstApp";
  String deviceName = "firstDevice";
  AtKeysIo? atKeysIo;

  /// Whether to mint the legacy RSA encryption keypair, the
  /// `selfEncryptionKey` and the `apkamSymmetricKey`, and publish
  /// `public:publickey@<atSign>`.
  ///
  /// An **opt-out**, and null is the release default rather than false:
  /// legacy material is retained until the *ecosystem* is post-quantum, not
  /// until this atSign is. Whether a brand-new atSign will ever need to talk
  /// to a legacy peer is decided by the apps that adopt it, which is unknowable
  /// at activation — so the safe answer is to cut the material and let a caller
  /// that genuinely knows better turn it off.
  ///
  /// Resolving null to true is deliberate and is expected to invert in a later
  /// major, once every first-party downstream writes PQ by default.
  ///
  /// Setting it false makes a legacy peer's send to this atSign unsupported:
  /// there is no `public:publickey` for them to encrypt to. It also leaves the
  /// keyfile with no `selfEncryptionKey`, which is correct — with no legacy
  /// flat fields to protect there is nothing for it to encrypt, and a
  /// passphrase envelope is what protects the typed material at rest.
  bool? mintLegacyMaterial;

  /// Builds the metadata that rides the first enrollment's `enroll:request`.
  ///
  /// See [FirstEnrollmentRequest.metadataBuilder]. `metadata.keyPackage` is
  /// written by the request that creates the enrollment record and never
  /// again, so onboarding is the only moment a first enrollment can advertise
  /// an encapsulation key at all.
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? metadataBuilder;

  /// A signing keypair this atSign's first enrollment owns from birth.
  ///
  /// Becomes [EnrollmentRequest.advertisedSigningKey]: `_apsk` advertises it
  /// instead of the APKAM key, and the activation files it under
  /// `sign:<algorithm>:<generation>`.
  ///
  /// ⚠️ **Whatever signs [metadataBuilder]'s key package must be this key.** A
  /// peer verifies that package against `_apsk` before sealing any secret to
  /// the enrollment, so the two disagreeing means a freshly activated atSign
  /// is never sent anything.
  ({
    SigningAlgoType algorithm,
    String publicKey,
    String privateKey
  })? advertisedSigningKey;
}

class AtAuthRequest extends AuthRequest {
  /// Constructor for [AtAuthRequest]
  /// [atSign] is the atSign for authentication
  ///
  /// Must provide one of the following!
  /// atKeysIo - method of authentication
  ///    or
  /// atAuthKeys - the actual keys themselves
  ///
  /// [atKeysIo] controls how AtKeys are loaded and saved (e.g. file system, keychain, secure element)
  /// [atAuthKeys] are the keys for authentication of an atSign
  ///
  /// optional:
  /// [rootDomain] is the default domain of the root server (e.g. root.atsign.org, 64)
  AtAuthRequest(
    super.atSign, {
    super.rootDomain,
    super.retryOptions,
    this.atKeysIo,
    this.atAuthKeys,
  }) {
    if (atKeysIo == null && atAuthKeys == null) {
      throw Exception(
          "Either method of authentication(atKeysIo) or atAuthKeys need to be provided");
    }
  }

  // Controls how the authentication is performed
  AtKeysIo? atKeysIo;

  /// The enrollmentId for APKAM authentication
  String? enrollmentId;

  /// The keys for authentication of an atSign.
  @Deprecated('remove in v5')
  AtKeys? atAuthKeys;
}

class RetryOptions {
  static const defaultRetryOptions =
      RetryOptions(maxRetries: 10, retryDelay: Duration(seconds: 2));

  final int maxRetries;
  final Duration retryDelay;

  /// The maximum total wall-clock to spend reaching/validating the atServer —
  /// the whole retry/poll loop. When null, the default depends on the request:
  /// authentication uses the short process-wide default
  /// (`AtNetworkTimeouts.effectiveDefault`, 30s) so a dead network fails fast,
  /// while ONBOARDING uses `AtNetworkTimeouts.defaultOnboardingTimeout` (5 min)
  /// because a newly-registered atSign can take minutes to be provisioned. This
  /// bounds the loop and is deliberately NOT clamped to
  /// `AtNetworkTimeouts.maxAllowed` — that cap applies to individual network
  /// operations. Note [maxRetries] no longer bounds this loop; this deadline
  /// does (the loop retries every [retryDelay] until the budget is spent).
  final Duration? overallTimeout;

  const RetryOptions(
      {required this.maxRetries,
      required this.retryDelay,
      this.overallTimeout});
}
