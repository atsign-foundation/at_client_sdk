import 'dart:async' show FutureOr;

import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/keys/at_keys.dart' show AtKeys;
import 'package:at_auth/src/keys/io/at_keys_io.dart' show AtKeysIo;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;

/// How an enrollment's `apkamSymmetricKey` gets from one side to the other.
///
/// This is **not** the same question as whether the request advertises a key
/// package: a package is also how an approver seals this atSign's existing
/// secrets to a new device, which every mode does. This enum governs only the
/// symmetric key that wraps the encryption private key and the self-encryption
/// key.
enum EnrollmentKeyExchangeMode {
  /// The enrollee generates the symmetric key and RSA-encrypts it to the
  /// atSign's default encryption public key, which the approver unwraps.
  ///
  /// The wrap is the one Shor-vulnerable step in enrollment, so this mode does
  /// not survive a quantum adversary recording the request. It is the default
  /// because it is the only mode every published approver and atServer
  /// understands.
  legacy,

  /// The approver generates the symmetric key and encapsulates it to the key
  /// package the request advertised; the enrollee collects it after approval.
  ///
  /// Nothing RSA-wrapped rides the request. Requires the request to advertise
  /// a key package, to supply an [AtEnrollmentRequest.apkamSymmetricKeyResolver],
  /// an approver that conveys, and an atServer that does not insist on the
  /// wrapped key. Fails closed against any of those rather than degrading, so
  /// an enrollment either has the property or does not reach the atServer.
  pq,
}

/// The BaseEnrollmentRequest class encapsulates shared fields between the InitialEnrollmentRequest and EnrollmentRequest.
///
/// The [FirstEnrollmentRequest] is used when the app is onboarded for the first time. The request is sent to the server
/// via the CRAM authenticated connection and is auto approved.
///
/// The [EnrollmentRequest] is used by the other apps to authenticate. This request is sent to the server and subsequently
/// notified to apps with access to the "__manage" namespace. Upon approval, the requesting app is authenticated and granted
/// authorization to access the specified namespaces in the request. Conversely, if the request is disapproved, the requesting
/// app is denied login access.
abstract class EnrollmentRequest {
  String atSign;
  String appName;
  String deviceName;
  final EnrollOperationEnum enrollOperation = EnrollOperationEnum.request;
  String? apkamPublicKey;
  AtRootDomain rootDomain;

  /// A signing keypair this enrollment owns from birth, which `_apsk`
  /// advertises **instead of** [apkamPublicKey] and which this request files
  /// into the enrollment's key material.
  ///
  /// Null means the enrollment holds no signing key of its own, so its APKAM
  /// authentication key both authenticates and signs, and `_apsk` advertises
  /// that key — which is what every released build does, and what a client
  /// must keep doing until its fleet's readers have moved.
  ///
  /// **Supplied by the caller rather than minted here, because whether to hold
  /// one is a rollout position and at_auth cannot see a preference.** The
  /// caller knows where it stands; this package carries what it is given.
  ///
  /// ⚠️ **Whatever signs this enrollment's key package must be this key.**
  /// `_apsk` is what a peer resolves to verify a key package before sealing
  /// any secret to the enrollment, so a package signed by the APKAM key while
  /// the record names this one verifies against nothing — and the enrollment
  /// is created and then never receives any conveyed material. The two move
  /// together or neither moves.
  final ({
    SigningAlgoType algorithm,
    String publicKey,
    String privateKey
  })? advertisedSigningKey;

  EnrollmentRequest(
      {required this.atSign,
      required this.appName,
      required this.deviceName,
      this.apkamPublicKey,
      this.advertisedSigningKey,
      this.rootDomain = const AtRootDomain("root.atsign.org", 64)});
}

/// The [EnrollmentRequest] is used by the apps to submit enrollment request for APKAM keys which provides .atKeys specific to
/// an application with restricted access to the namespaces. The application can access only the namespaces which are specified
/// in the enrollment request. If the namespace has Read-Write access then the application is allowed to create/update the data,
/// otherwise, if the namespace has only Read access then the application is allowed to read the data, but cannot create/update
/// the data.
///
/// This request is sent to the server and subsequently notified to apps with access to the "__manage" namespace. Upon approval, the requesting app is authenticated and granted
/// authorization to access the specified namespaces in the request. Conversely, if the request is disapproved, the requesting
/// app is denied login access.
class AtEnrollmentRequest extends EnrollmentRequest {
  /// The authenticated session of the app submitting this enrollment request.
  ///
  /// When supplied, it is the source of the request's [atSign] and [rootDomain],
  /// and its [AtAuthSession.atKeysIo] is where the newly enrolled app's keys are
  /// persisted and handed back on the [AtEnrollmentResponse.session] after
  /// approval. Prefer this over the deprecated `atSign`/`rootDomain` params.
  final AtAuthSession? session;

  Map<String, String> namespaces;
  String? encryptedAPKAMSymmetricKey;
  String otp;
  Duration? apkamKeysExpiryDuration;

  /// Builds the opaque metadata stored verbatim on this enrollment's record.
  ///
  /// Called once, after the APKAM keypair for this request has been generated
  /// and before the request is sent, with an [AtKeysIo] holding that keypair.
  /// Whatever it returns is attached to the request unchanged; at_auth never
  /// inspects it.
  ///
  /// The callback is how a caller contributes material that must be **signed
  /// by the new APKAM key** — the secret-sharing key package is the first such
  /// case. That cannot be built by the caller beforehand, because the keypair
  /// does not exist until this request is being assembled, and it cannot be
  /// added afterwards, because the metadata is only ever written by the
  /// request that creates the record.
  ///
  /// The keys it receives carry **no `enrollmentId`**: the atServer assigns
  /// that in its response to this request. Anything the callback builds must
  /// therefore be valid without one.
  final FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)?
      metadataBuilder;

  /// Obtains this enrollment's `apkamSymmetricKey` once the approver has
  /// delivered it, for a request whose [metadataBuilder] advertised a key
  /// package.
  ///
  /// Such a request never generates the symmetric key and never RSA-wraps one:
  /// the approver mints it and encapsulates it to the advertised public half,
  /// so it has to be collected after approval rather than carried in. This
  /// runs inside `waitForApproval`, after PKAM authentication succeeds — the
  /// earliest point at which the enrollment can read anything — and is handed
  /// the authenticated [AtLookUp] plus the [AtKeys] holding the key package's
  /// private half.
  ///
  /// Supplied by — and only by — [AtEnrollmentRequest.pq], which requires it:
  /// without one a pq request would authenticate and then be unable to decrypt
  /// anything. Null on a legacy request, which carries its own symmetric key
  /// in and has nothing to collect.
  final FutureOr<String> Function(AtKeys keys, AtLookUp atLookUp)?
      apkamSymmetricKeyResolver;

  /// How this request conveys the enrollment's symmetric key.
  ///
  /// Not a parameter — the constructor decides it, because the mode and the
  /// callbacks it needs cannot be chosen separately without producing requests
  /// at_auth has to refuse at runtime. The default constructor is
  /// [EnrollmentKeyExchangeMode.legacy], the mode every published approver and
  /// atServer understands; [AtEnrollmentRequest.pq] is the other.
  final EnrollmentKeyExchangeMode keyExchangeMode;

  /// A legacy-mode enrollment request: this app mints the symmetric key and
  /// RSA-wraps it to the atSign's encryption public key for the approver to
  /// unwrap.
  ///
  /// A [metadataBuilder] is still welcome here — a key package on the record
  /// is also how an approver seals this atSign's existing secrets to the new
  /// device, which is a separate question from how the symmetric key travels.
  AtEnrollmentRequest({
    this.session,
    @Deprecated('Provide `session` instead; its atSign is used.')
    String? atSign,
    @Deprecated('Provide `session` instead; its rootDomain is used.')
    AtRootDomain? rootDomain,
    required super.appName,
    required super.deviceName,
    @Deprecated('Provide `session` instead; it contains a AtKeysIo to use.')
    super.apkamPublicKey,
    required this.otp,
    required this.namespaces,
    @Deprecated('Provide `session` instead; it contains a AtKeysIo to use.')
    this.encryptedAPKAMSymmetricKey,
    this.apkamKeysExpiryDuration,
    this.metadataBuilder,
  })  : keyExchangeMode = EnrollmentKeyExchangeMode.legacy,
        apkamSymmetricKeyResolver = null,
        super(
          atSign: _atSignOf(session, atSign),
          rootDomain:
              session?.rootDomain ?? rootDomain ?? AtRootDomain.atsignDomain,
        );

  /// A pq-mode enrollment request: nothing RSA-wrapped rides it. The approver
  /// mints the symmetric key and encapsulates it to the key package this
  /// request advertises, and [apkamSymmetricKeyResolver] collects it after
  /// approval.
  ///
  /// Both callbacks are required because a pq request is unusable without
  /// either: no [metadataBuilder] means no public half to encapsulate to, and
  /// no resolver means nothing ever collects what was encapsulated. They were
  /// optional parameters checked at submission time, and are constructor
  /// requirements instead, so the two ways of getting this wrong stopped being
  /// reachable states.
  ///
  /// The atSign is sourced exactly as it is for a legacy request: a [session]
  /// if there is one, else the deprecated loose `atSign`. A request that only
  /// wants the key exchange — one that inspects what it advertised and never
  /// waits for approval — has nowhere to persist keys and needs no session.
  AtEnrollmentRequest.pq({
    this.session,
    @Deprecated('Provide `session` instead; its atSign is used.')
    String? atSign,
    @Deprecated('Provide `session` instead; its rootDomain is used.')
    AtRootDomain? rootDomain,
    required super.appName,
    required super.deviceName,
    required this.otp,
    required this.namespaces,
    required FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)
        this.metadataBuilder,
    required FutureOr<String> Function(AtKeys keys, AtLookUp atLookUp)
        this.apkamSymmetricKeyResolver,
    this.apkamKeysExpiryDuration,
  })  : keyExchangeMode = EnrollmentKeyExchangeMode.pq,
        encryptedAPKAMSymmetricKey = null,
        super(
          atSign: _atSignOf(session, atSign),
          rootDomain:
              session?.rootDomain ?? rootDomain ?? AtRootDomain.atsignDomain,
        );

  /// The one rule for where a request's atSign comes from, shared by both
  /// constructors: the session if there is one, else the deprecated parameter,
  /// else a refusal — a request with no atSign has no atServer to reach.
  static String _atSignOf(AtAuthSession? session, String? atSign) =>
      session?.atSign ??
      atSign ??
      (throw ArgumentError(
          'AtEnrollmentRequest requires a `session` (or the deprecated `atSign`)'));
}

/// An APKAM-authenticated self-enrollment: the request an already-enrolled
/// client submits to spawn a FRESH enrollment for itself — the client half of
/// the PQ retrofit (`at_client_sdk` `docs/projects/pq/decisions.md` 5, 40,
/// 42 item 1). No OTP and no human approval: the connection's existing
/// approved enrollment is the whole authority, and the atServer auto-approves
/// a subset of its grants.
///
/// The submission must ride an APKAM-authenticated [AtLookUp] — the atServer
/// discriminates this path solely by the connection's authType. On the
/// auto-approved response, the freshly minted ML-DSA-65 APKAM keypair (and
/// whatever typed material the [metadataBuilder] filed, such as the X-Wing
/// key package) is persisted into the SAME keyfile that holds the legacy
/// material, as typed materials tagged with the new enrollment id. The
/// legacy flat fields are untouched, so the original enrollment keeps
/// authenticating until the atServer's expiry cap retires it.
class AtSelfEnrollmentRequest extends EnrollmentRequest {
  /// The authenticated session whose keyfile self-enrolls. Its
  /// [AtAuthSession.atKeysIo] is both the source of the existing material
  /// and the destination of the new enrollment's, which is why it is
  /// required rather than optional here.
  final AtAuthSession session;

  /// The grants the new enrollment requests. Must be non-empty (the atServer
  /// refuses an empty set) and a subset of the authenticated enrollment's
  /// (anything more is refused as escalation).
  Map<String, String> namespaces;

  /// The new enrollment's key-expiry posture. Absent, the atServer inherits
  /// the parent enrollment's.
  Duration? apkamKeysExpiryDuration;

  /// See [AtEnrollmentRequest.metadataBuilder]. The handed keys carry the
  /// freshly minted APKAM keypair of [signingAlgo]'s algorithm, so a builder
  /// that signs with it must sign the same one — e.g.
  /// `enrollmentKeyPackageBuilder(atSign, signingAlgo: request.signingAlgo)`.
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? metadataBuilder;

  /// The algorithm of the APKAM keypair this self-enrollment mints —
  /// `mldsa65` (the default: today's PQ retrofit) or `rsa2048` for a
  /// rollout-window retrofit that needs no ML-DSA anywhere. Either way the
  /// keypair is FRESH: a new enrollment never reuses the legacy key object,
  /// which is what keeps one-enrollment-one-keypair and the PKAM binding
  /// unambiguous.
  final SigningAlgoType signingAlgo;

  AtSelfEnrollmentRequest({
    required this.session,
    required super.appName,
    required super.deviceName,
    required this.namespaces,
    this.apkamKeysExpiryDuration,
    this.metadataBuilder,
    super.advertisedSigningKey,
    this.signingAlgo = SigningAlgoType.mldsa65,
  }) : super(atSign: session.atSign, rootDomain: session.rootDomain);
}

/// The FirstEnrollmentRequest represents an enrollment request when onboarding (activating) an atSign.
///
/// Upon submitting the [FirstEnrollmentRequest], an APKAM key pair and an encryption key pair are generated, and an enrollment
/// request is sent to the server. The server assigns the "__manage" namespace, which has access to all namespaces and serves as
/// the administrator app responsible for approving subsequent enrollment requests.
///
/// ```dart
/// Example on submitting FirstEnrollmentRequest
///   FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
///               appName: 'wavi',
///               deviceName: 'iphone',
///               apkamPublicKey: 'dummy-apkam-public key', // Generated by the system
///               encryptedDefaultEncryptionPrivateKey: 'dummy-encrypted-private-key', // Generated by the system and encrypted by the APKAM symmetric key
///               encryptedDefaultSelfEncryptionKey: 'dummy-self-encryption-key'); // Generated by the system and encrypted by the APKAM symmetric key);
///```
/// Two pair of RSA key pairs one for authentication which is called APKAM keys and other for shared data encryption
/// which is called encryption key pair. Two AES keys pairs self data encryption and APKAM encryption key.
///
/// The APKAM public key is stored in the secondary server. The default encryption private key and self encryption keys are
/// encrypted with the APKAM symmetric key and stored into the server.

class FirstEnrollmentRequest extends EnrollmentRequest {
  /// The signing algorithm of [apkamPublicKey] — `rsa2048` for a legacy
  /// onboard, `mldsa65` for a PQ-native one.
  ///
  /// It reaches the enrollment record, and names the algorithm of the key this
  /// request advertises in its `_apsk` (see `apskAdvertisement`); the atServer
  /// composes nothing. Getting it wrong is not a degraded mode but a broken one: the
  /// atServer would verify this enrollment's PKAM signatures with the wrong
  /// routine, so the first enrollment could never authenticate.
  SigningAlgoType signingAlgo;

  /// See [AtEnrollmentRequest.metadataBuilder].
  ///
  /// For a first enrollment the handed keys carry the freshly minted APKAM
  /// keypair — the enrollment record does not exist yet, so this is the only
  /// moment anything can be put on it (`metadata.keyPackage` is written by the
  /// request that creates the record and never afterwards). A PQ-native
  /// onboard passes `enrollmentKeyPackageBuilder(atSign,
  /// signingAlgo: SigningAlgoType.mldsa65,
  /// keyEstablishmentAlgo: preference.keyEstablishmentAlgo)`.
  ///
  /// Requires [atKeys], because a builder both reads the APKAM keypair it
  /// signs with and **writes back** the material it minted.
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo keysIo)? metadataBuilder;

  /// The keys being enrolled — the same instance the caller keeps, not a copy.
  ///
  /// [metadataBuilder] mutates it: the key package's private half is added
  /// here and nowhere else, so a caller that hands over a copy publishes an
  /// encapsulation target whose private half it never kept, and every sender
  /// seals to a key that can never be opened. Only needed when a
  /// [metadataBuilder] is supplied.
  AtKeys? atKeys;

  FirstEnrollmentRequest(
      {required super.atSign,
      required super.appName,
      required super.deviceName,
      required super.apkamPublicKey,
      super.advertisedSigningKey,
      this.signingAlgo = SigningAlgoType.rsa2048,
      this.metadataBuilder,
      this.atKeys});
}
