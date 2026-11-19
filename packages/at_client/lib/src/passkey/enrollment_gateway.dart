import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/remote_secondary.dart';
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

  /// Whether [e] carries the atServer's reply to the `pkam:` command saying it
  /// refuses [enrollmentId]: `error:AT0401` (the signature did not verify), or
  /// `error:AT0025`, `AT0027` or `AT0028` (the enrollment is denied, revoked,
  /// or expired or unknown) naming `enrollment_id: ID`. The atServer
  /// replies `error:CODE:MESSAGE` and at_auth wraps it as `Failed
  /// connecting to ATSIGN. REPLY`. AT0028 also stands for a throttled
  /// client, so a code without this enrollment's id is not a refusal; nor is
  /// AT0026 (pending). Any other failed handshake (a server error, a throttled
  /// or empty reply, an authenticator that reports failure) says nothing about
  /// the enrollment and is not a refusal.
  static bool _isPkamRefusal(UnAuthenticatedException e, String enrollmentId) {
    final reply = RegExp(r'\. error:(AT\d{4})\b(.*)$', dotAll: true)
        .firstMatch(e.message);
    if (reply == null) return false;
    switch (reply.group(1)) {
      case 'AT0401':
        return true;
      case 'AT0025' || 'AT0027' || 'AT0028':
        return RegExp('enrollment_id: ${RegExp.escape(enrollmentId)}(\\s|\$)')
            .hasMatch(reply.group(2)!);
      default:
        return false;
    }
  }

  /// PKAM as [enrollmentId] with [pair] on a connection of its own.
  ///
  /// Throws [PkamRefusedException] only when the atServer explicitly refuses
  /// the signature; other failures propagate as they are.
  Future<EnrollmentSession> _authenticated(
      String atSign, String enrollmentId, ApkamKeyPair pair,
      {required AtKeys? keys}) async {
    final lookUp = _lookUp(atSign);
    try {
      final signingKeys =
          withApkamKey(AtKeys(atsign: Atsign(atSign)), enrollmentId, pair);
      lookUp.authenticator = authenticatorFor(
          handshakeKeysIo(atSign, signingKeys), atSign,
          enrollmentId: enrollmentId);
      if (!await lookUp.pkamAuthenticate()) {
        throw UnAuthenticatedException('Failed connecting to $atSign. The '
            'authenticator reported failure');
      }
    } on UnAuthenticatedException catch (e) {
      await _closeQuietly(lookUp);
      if (_isPkamRefusal(e, enrollmentId)) {
        throw PkamRefusedException(enrollmentId);
      }
      rethrow;
    } catch (_) {
      await _closeQuietly(lookUp);
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

  @override
  Future<void> revokeOtherEnrollments() async {
    for (final other in await _otherApprovedEnrollments()) {
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

  /// Whether [e] is the atServer's answer refusing a verb, rather than the
  /// request failing to reach it or come back. A lost connection or a
  /// timeout reaches here as an [AtConnectException] or [AtTimeoutException],
  /// or as a bare [AtException]: [RemoteSecondary] turns the lookup's AT0004
  /// (connection) and AT0014 (timeout, unknown) codes into one.
  static bool _isRefusal(AtException e) =>
      e is! AtConnectException &&
      e is! AtTimeoutException &&
      e.runtimeType != AtException;

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
  Future<AtClient> openClient(WrittenAtKeysIo keysIo) => _gateway.clientOpener(
      lookUp: _lookUp,
      atSign: _atSign,
      enrollmentId: enrollmentId,
      keysIo: keysIo);

  @override
  Future<void> close() => _lookUp.close();
}

const _encryptPublicKey = 'aesEncryptPublicKey';
