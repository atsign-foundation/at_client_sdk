import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/lifecycle/at_connection.dart'
    show AtConnectionCause, classifyConnectionFailure;
import 'package:at_client/src/lifecycle/atsign_lifecycle.dart';
import 'package:at_client/src/lifecycle/pending_enrollment.dart'
    show handshakeKeysIo;
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/preference/client_config.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show decideEnrollmentOn, listEnrollmentsOn;
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_builders.dart' show EnrollVerbBuilder;
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:at_lookup/at_lookup.dart';

import 'at_keys_document.dart';
import 'completion_due_record.dart';
import 'enrollment_document_store.dart';
import 'enrollment_pointer_store.dart';
import 'passkey_custody.dart';
import 'public_lookup.dart';

/// An ML-DSA-65 APKAM key pair as base64 text, the form at_auth takes.
typedef ApkamKeyPair = ({String publicKey, String privateKey});

/// The ML-DSA-65 key pair [authSeed] derives, as base64 text.
Future<ApkamKeyPair> apkamKeyPairFromSeed(Uint8List authSeed) async {
  final pair = await MlDsa65PureDartAlgo().keyPairFromSeed(authSeed);
  return (
    publicKey: base64Encode(pair.publicKey),
    privateKey: base64Encode(pair.secretKey)
  );
}

/// [keys] with [pair] filed as the APKAM material of [enrollmentId].
AtKeys withApkamKey(AtKeys keys, String enrollmentId, ApkamKeyPair pair) => keys
  ..fileApkamMaterial(
      enrollmentId: enrollmentId,
      algorithm: CryptographicMaterialAlgorithm.mlDsa65,
      publicKey: pair.publicKey,
      privateKey: pair.privateKey);

/// Activates a fresh atSign with [cram] and [apkamKeyPair] as its first
/// enrollment's APKAM key, leaving the activation to be completed, and
/// returns the keys it minted.
typedef Activator = Future<AtKeys> Function(
    {required String atSign,
    required String cram,
    required ApkamKeyPair apkamKeyPair});

/// Opens the client that runs as [enrollmentId] on [lookUp]: the connection
/// that already authenticated as it. The client reads its @keys from [keysIo]
/// and persists every change through it. It takes over [lookUp] and stops it
/// when the client stops; it never closes [keysIo]. If this throws, [lookUp]
/// is still the caller's to release.
typedef ClientOpener = Future<AtClient> Function(
    {required AtLookupMuxable lookUp,
    required String atSign,
    required String enrollmentId,
    required WrittenAtKeysIo keysIo});

/// The production [EnrollmentGateway]: at_auth enrollment and at_client
/// activation, with the APKAM key pair the passkey derives.
///
/// A session from [activate] keeps the @keys the activation minted, which
/// include the APKAM private key, until the session is dropped;
/// [EnrollmentSession.atKeys] returns them without it.
class AtAuthEnrollmentGateway implements EnrollmentGateway {
  /// [activator] is the at_client activation seam; [clientOpener] is what
  /// [EnrollmentSession.openClient] runs to build the client.
  AtAuthEnrollmentGateway(
      {required this.lookUps,
      required this.finder,
      required this.root,
      required this.app,
      required this.device,
      required this.clientOpener,
      Activator? activator}) {
    _activator = activator ?? _activateWithoutClient;
  }

  /// Builds each connection a session makes.
  final AtLookUpFactory lookUps;

  /// Resolves an atSign to its atServer.
  final SecondaryAddressFinder finder;

  final AtRootDomain root;
  final String app;
  @override
  final String device;
  final ClientOpener clientOpener;
  late final Activator _activator;

  @override
  Future<EnrollmentSession> authenticate(
          {required String atSign,
          required String enrollmentId,
          required ApkamKeyPair apkamKeyPair}) =>
      _authenticated(atSign, enrollmentId, apkamKeyPair, keys: null);

  @override
  Future<EnrollmentSession> activate(
      {required String atSign,
      required ApkamKeyPair apkamKeyPair,
      required String cram}) async {
    final keys = await _activator(
        atSign: atSign, cram: cram, apkamKeyPair: apkamKeyPair);
    return _authenticated(
        atSign, keys.enrollmentToAuthenticateAs(), apkamKeyPair,
        keys: keys);
  }

  AtLookupMuxable _lookUp(String atSign) => lookUps(
      atSign: atSign,
      rootDomain: root,
      authenticator: null,
      secondaryAddressFinder: finder);

  static const _enrollmentRefusals = {
    AtConnectionCause.unauthenticated,
    AtConnectionCause.revoked,
    AtConnectionCause.enrollmentDenied,
    AtConnectionCause.invalidEnrollment,
  };

  /// PKAM as [enrollmentId] with [pair] on a connection of its own, whose
  /// `from:` carries at_client's clientConfig.
  ///
  /// Throws [PkamRefusedException] when the run of the authenticator that
  /// failed sent a `pkam:` and [classifyConnectionFailure] reads the failure
  /// as a refusal whose cause is [AtConnectionCause.unauthenticated],
  /// [AtConnectionCause.revoked], [AtConnectionCause.enrollmentDenied] or
  /// [AtConnectionCause.invalidEnrollment]. Any other failure, one before the
  /// `pkam:` or a refusal as [AtConnectionCause.enrollmentNotApproved]
  /// included, propagates as it is.
  Future<EnrollmentSession> _authenticated(
      String atSign, String enrollmentId, ApkamKeyPair pair,
      {required AtKeys? keys}) async {
    final lookUp = _lookUp(atSign);
    var pkamSent = false;
    try {
      final signingKeys =
          withApkamKey(AtKeys(atsign: Atsign(atSign)), enrollmentId, pair);
      final authenticate = authenticatorFor(
          handshakeKeysIo(atSign, signingKeys), atSign,
          enrollmentId: enrollmentId, clientConfig: clientConfigOf(null));
      // NOTE: only a reply to the pkam: can be a refusal.
      lookUp.authenticator = (executor) {
        pkamSent = false;
        return authenticate(_NotingPkam(executor, () => pkamSent = true));
      };
      if (!await lookUp.pkamAuthenticate()) {
        throw UnAuthenticatedException('Failed connecting to $atSign. The '
            'authenticator reported failure');
      }
    } catch (e) {
      await _closeQuietly(lookUp);
      if (pkamSent &&
          _enrollmentRefusals.contains(classifyConnectionFailure(e)?.cause)) {
        throw PkamRefusedException(enrollmentId);
      }
      rethrow;
    }
    return _PkamSession(this, lookUp, atSign, enrollmentId, keys);
  }

  Future<AtKeys> _activateWithoutClient(
      {required String atSign,
      required String cram,
      required ApkamKeyPair apkamKeyPair}) async {
    final filing = scratchKeysIo();
    final preference = AtClientPreference()
      ..namespace = app
      ..rootDomain = root.rootDomain
      ..rootPort = root.rootPort;
    await activateWithoutClient(Atsign(atSign),
        cramSecret: cram,
        keys: filing,
        preference: preference,
        app: app,
        device: device,
        mintLegacyMaterial: true,
        signingAlgo: SigningAlgoType.mldsa65,
        apkamKeyPair: apkamKeyPair,
        lookUps: lookUps,
        secondaryAddressFinder: finder,
        completeActivation: false,
        clientConfig: clientConfigOf(preference.atClientParticulars));
    return filing.read(atSign);
  }
}

/// [_executor], calling [_onPkam] as each `pkam:` is sent through it.
class _NotingPkam implements AtCommandExecutor {
  _NotingPkam(this._executor, this._onPkam);

  final AtCommandExecutor _executor;
  final void Function() _onPkam;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) {
    if (command.startsWith('pkam:')) _onPkam();
    return _executor.sendSync(command,
        maxWaitMilliSeconds: maxWaitMilliSeconds,
        transientWaitTimeMillis: transientWaitTimeMillis);
  }
}

Future<void> _closeQuietly(AtLookupMuxable lookUp) async {
  try {
    await lookUp.close();
  } catch (e, st) {
    AtSignLogger('enrollmentGateway').warning('closing a lookUp failed', e, st);
  }
}

class _PkamSession implements EnrollmentSession {
  static final _logger = AtSignLogger('enrollmentSession');

  _PkamSession(
      this._gateway, this._lookUp, this._atSign, this.enrollmentId, this._keys)
      : _remote = RemoteSecondary(_atSign, AtClientPreference(),
            atLookUp: _lookUp,
            lookUps: _gateway.lookUps,
            secondaryAddressFinder: _gateway.finder);

  final AtAuthEnrollmentGateway _gateway;
  final AtLookupMuxable _lookUp;
  final String _atSign;
  final RemoteSecondary _remote;
  final AtKeys? _keys;

  @override
  final String enrollmentId;

  @override
  late final EnrollmentDocumentStore documents =
      RemoteEnrollmentDocumentStore(_remote);

  late final _completionDue =
      CompletionDueRecord(_remote, atSign: _atSign, enrollmentId: enrollmentId);

  @override
  late final EnrollmentPointerStore pointers = RemoteEnrollmentPointerStore(
      LookupEnrollmentPointerReader(
          lookUps: _gateway.lookUps,
          rootDomain: _gateway.root,
          secondaryAddressFinder: _gateway.finder),
      _remote);

  /// The enrollment's @keys as a document, without any APKAM private key:
  /// the flat field and every typed `privateAuthentication` material.
  @override
  Future<Map<String, dynamic>> atKeys() async {
    final keys = _keys;
    if (keys == null) {
      throw StateError('this session was authenticated, not enrolled: it '
          'holds no @keys');
    }
    return atKeysDocument(keys, _atSign);
  }

  /// How the key published at `publickey@<atSign>` stands against the
  /// encryption public key in [atKeys]: the same when [atKeys] holds none,
  /// since there is nothing to match, and none when the lookup finds no key.
  @override
  Future<PublishedEncryptionKey> publishedEncryptionKey(
      Map<String, dynamic> atKeys) async {
    final restored = atKeys[_encryptPublicKey];
    if (restored is! String) return PublishedEncryptionKey.same;
    return switch (await _published()) {
      null => PublishedEncryptionKey.none,
      final published when published == restored => PublishedEncryptionKey.same,
      _ => PublishedEncryptionKey.different,
    };
  }

  /// The `publickey` the atServer publishes for this atSign, or null.
  Future<String?> _published() => publicLookup(
      lookUps: _gateway.lookUps,
      rootDomain: _gateway.root,
      secondaryAddressFinder: _gateway.finder,
      atSign: _atSign,
      key: 'publickey');

  /// Logs a warning naming the atSign and the enrollment before each revoke
  /// it sends.
  @override
  Future<void> revokeOtherEnrollments() async {
    for (final other in await _otherApprovedEnrollments()) {
      _logger.warning('revoking enrollment $other of ${_atSign.toAtsign()}');
      try {
        await decideEnrollmentOn(
            _remote,
            _atSign,
            EnrollVerbBuilder()
              ..operation = EnrollOperationEnum.revoke
              ..enrollmentId = other);
      } on AtException catch (e) {
        if (!_isRefusal(e)) rethrow;
        _logger.info('a revoke was refused (${e.runtimeType}); the list that '
            'follows decides whether it matters');
      }
    }
    final remaining = await _otherApprovedEnrollments();
    if (remaining.isNotEmpty) {
      throw AtEnrollmentException('${remaining.length} approved enrollments '
          'other than $enrollmentId remain after revoking them');
    }
  }

  /// Whether a failed revoke is left to the list that follows: only the
  /// atServer's refusals of the revoke itself, which [RemoteSecondary] maps
  /// from AT0028 (the enrollment has expired or no longer exists; it arrives
  /// as an [AtThrottleLimitExceeded], the type at_commons gives that code),
  /// AT0029 (invalid or expired enrollment), AT0031 (the atServer will not
  /// revoke it) and AT0032 (the enrollment is in no state to revoke). Every
  /// other failure, such as a lost or failed connection (AT0004, AT0021), a
  /// timeout, a paused, busy or failing atServer (AT0024, AT0012, AT0011) or
  /// an I/O error, propagates as it is.
  ///
  /// The list decides: it throws while an enrollment the revoke named is
  /// still approved, and it fails too when this session's own enrollment has
  /// expired, which the atServer also answers with AT0028.
  static bool _isRefusal(AtException e) =>
      e is AtThrottleLimitExceeded ||
      e is AtInvalidEnrollmentException ||
      e is AtEnrollmentRevokeException ||
      e is IllegalStateException;

  /// The ids of the atSign's approved enrollments other than this one.
  Future<List<String>> _otherApprovedEnrollments() async => [
        for (final enrollment in await listEnrollmentsOn(_remote,
            params: EnrollmentListRequestParam()
              ..enrollmentListFilter = [EnrollmentStatus.approved]))
          if (enrollment.enrollmentStatus == EnrollmentStatus.approved &&
              enrollment.enrollmentId != enrollmentId)
            enrollment.enrollmentId!
      ];

  @override
  Future<void> completeActivation(Map<String, dynamic> atKeys) =>
      completeActivationOf(
          atLookUp: _lookUp,
          atSign: _atSign,
          encryptionPublicKey: atKeys[_encryptPublicKey] as String?);

  @override
  Future<void> recordCompletionDue(CompletionDue state) =>
      _completionDue.write(state);

  @override
  Future<CompletionDue?> completionDue() => _completionDue.read();

  @override
  Future<void> clearCompletionDue() => _completionDue.clear();

  @override
  Future<AtClient> openClient(WrittenAtKeysIo keysIo) => _gateway.clientOpener(
      lookUp: _lookUp,
      atSign: _atSign,
      enrollmentId: enrollmentId,
      keysIo: keysIo);

  @override
  Future<void> close() => _lookUp.close();
}

const _encryptPublicKey = 'aesEncryptPublicKey';
