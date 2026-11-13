import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
// ignore: implementation_imports
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';

import 'enrollment_document_store.dart';
import 'enrollment_pointer_store.dart';
import 'passkey_custody.dart';
import 'public_lookup.dart';
import 'portal_session.dart' show SessionTransport;

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

/// Runs a first-time activation with [cram] and [apkamKeyPair] as the
/// enrollment's APKAM key, and returns the keys it filed.
typedef Activator = Future<AtKeys> Function(
    {required String atSign,
    required String cram,
    required ApkamKeyPair apkamKeyPair});

const _enrollmentWait = Duration(seconds: 1);

/// The production [EnrollmentGateway]: at_auth enrollment and at_client
/// activation, with the APKAM key derived from the auth seed.
///
/// The private key exists only in memory for the call that derives it; the
/// sessions it returns hold no copy.
class AtAuthEnrollmentGateway implements EnrollmentGateway {
  /// [namespaces] is what an enrollment asks for, including the pointer's.
  /// [enrollment] and [activator] are the at_auth and at_client seams.
  AtAuthEnrollmentGateway(
      {required this.transport,
      required this.root,
      required this.app,
      required this.device,
      required this.namespaces,
      AtEnrollment Function()? enrollment,
      Activator? activator})
      : _enrollment = enrollment ?? AtEnrollment.create {
    _activator = activator ?? _activateWithAtClient;
  }

  final SessionTransport transport;
  final AtRootDomain root;
  final String app;
  final String device;
  final Map<String, String> namespaces;
  final AtEnrollment Function() _enrollment;
  late final Activator _activator;

  @override
  Future<EnrollmentSession> enroll(
      {required String atSign,
      required Uint8List authSeed,
      required String otp}) async {
    final pair = await apkamKeyPairFromSeed(authSeed);
    final lookUp = _lookUp(atSign);
    var enrollmentId = '';
    try {
      final enrollment = _enrollment();
      final response = await enrollment.submit(
          AtEnrollmentRequest(
              session: AtAuthSession(
                  atSign: atSign,
                  rootDomain: root,
                  // NOTE: a scratch destination; the approved keys are read
                  // from the response.
                  // ignore: invalid_use_of_visible_for_testing_member
                  atKeysIo: InMemoryAtKeysIo()),
              appName: app,
              deviceName: device,
              otp: otp,
              namespaces: namespaces,
              signingAlgo: SigningAlgoType.mldsa65,
              apkamKeyPair: pair),
          lookUp);
      enrollmentId = response.enrollmentId;
      await enrollment.waitForApproval(response,
          atLookup: lookUp, retryInterval: _enrollmentWait);
      // ignore: deprecated_member_use
      final keys = response.atAuthKeys;
      return _PkamSession(this, lookUp, atSign, response.enrollmentId, keys);
    } on UnAuthenticatedException {
      await _closeQuietly(lookUp);
      throw PkamRefusedException(enrollmentId);
    } catch (_) {
      await _closeQuietly(lookUp);
      rethrow;
    }
  }

  @override
  Future<EnrollmentSession> authenticate(
          {required String atSign,
          required String enrollmentId,
          required Uint8List authSeed}) async =>
      _authenticated(atSign, enrollmentId, await apkamKeyPairFromSeed(authSeed),
          keys: null);

  @override
  Future<EnrollmentSession> activate(
      {required String atSign,
      required Uint8List authSeed,
      required String cram}) async {
    final pair = await apkamKeyPairFromSeed(authSeed);
    final keys =
        await _activator(atSign: atSign, cram: cram, apkamKeyPair: pair);
    final enrollmentId = keys.enrollmentToAuthenticateAs();
    try {
      return await _authenticated(atSign, enrollmentId, pair, keys: keys);
    } on Object catch (e) {
      throw ActivationPkamFailedException(enrollmentId,
          atKeys: _atKeysDocument(keys, atSign), cause: e);
    }
  }

  AtLookupMuxable _lookUp(String atSign) => transport.lookUps(
      atSign: atSign,
      rootDomain: root,
      authenticator: null,
      secondaryAddressFinder: transport.finder);

  /// PKAM as [enrollmentId] with [pair] on a connection of its own.
  Future<EnrollmentSession> _authenticated(
      String atSign, String enrollmentId, ApkamKeyPair pair,
      {required AtKeys? keys}) async {
    final lookUp = _lookUp(atSign);
    try {
      final signingKeys =
          withApkamKey(AtKeys(atsign: Atsign(atSign)), enrollmentId, pair);
      lookUp.authenticator = authenticatorFor(
          // NOTE: a fixed key set for this handshake, never a keyfile.
          // ignore: invalid_use_of_visible_for_testing_member
          InMemoryAtKeysIo.holding(atSign, signingKeys),
          atSign,
          enrollmentId: enrollmentId);
      if (!await lookUp.pkamAuthenticate()) {
        throw PkamRefusedException(enrollmentId);
      }
    } on UnAuthenticatedException {
      await _closeQuietly(lookUp);
      throw PkamRefusedException(enrollmentId);
    } catch (_) {
      await _closeQuietly(lookUp);
      rethrow;
    }
    return _PkamSession(this, lookUp, atSign, enrollmentId, keys);
  }

  Future<AtKeys> _activateWithAtClient(
      {required String atSign,
      required String cram,
      required ApkamKeyPair apkamKeyPair}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    final keysIo = InMemoryAtKeysIo();
    final client = await Atsign(atSign).activate(
        cramSecret: cram,
        keys: keysIo,
        preference: AtClientPreference()
          ..namespace = app
          ..rootDomain = root.rootDomain
          ..rootPort = root.rootPort,
        namespace: app,
        storage: InMemoryAtClientStorage(atSign: atSign),
        app: app,
        device: device,
        mintLegacyMaterial: true,
        signingAlgo: SigningAlgoType.mldsa65,
        apkamKeyPair: apkamKeyPair,
        lookUps: transport.lookUps,
        secondaryAddressFinder: transport.finder);
    return readKeysThenStop(keysIo, atSign, client.stop);
  }
}

/// Reads [atSign]'s activated keys from [keysIo], then calls [stop]; a
/// failing [stop] does not lose the keys.
Future<AtKeys> readKeysThenStop(
    AtKeysIo keysIo, String atSign, Future<void> Function() stop) async {
  final keys = await keysIo.read(atSign);
  try {
    await stop();
  } on Object catch (e, st) {
    // The keys are the only copy, so a failed stop is logged, not rethrown.
    AtSignLogger('enrollmentGateway')
        .severe('stopping the activation client of $atSign failed', e, st);
  }
  return keys;
}

/// [keys] as a document, without any APKAM private key: the flat field and
/// every typed `privateAuthentication` material.
Map<String, dynamic> _atKeysDocument(AtKeys keys, String atSign) {
  keys.atsign ??= Atsign(atSign);
  final json = Map<String, dynamic>.of(keys.toJson())..remove(apkamPrivateKey);
  final enrollments = json['enrollments'];
  if (enrollments is List) {
    json['enrollments'] = [
      for (final e in enrollments)
        {
          ...(e as Map<String, dynamic>),
          'keys': [
            for (final key in e['keys'] as List)
              {
                ...(key as Map<String, dynamic>),
                'material': [
                  for (final m in key['material'] as List)
                    if ((m as Map)['role'] != _privateAuthenticationRole) m
                ]
              }
          ]
        }
    ];
  }
  return json;
}

Future<void> _closeQuietly(AtLookupMuxable lookUp) async {
  try {
    await lookUp.close();
  } catch (e, st) {
    // The refusal being reported is the error that matters.
    AtSignLogger('enrollmentGateway').warning('closing a lookUp failed', e, st);
  }
}

class _PkamSession implements EnrollmentSession {
  _PkamSession(
      this._gateway, this._lookUp, this._atSign, this.enrollmentId, this._keys)
      : _remote = RemoteSecondary(_atSign, AtClientPreference(),
            atLookUp: _lookUp,
            lookUps: _gateway.transport.lookUps,
            secondaryAddressFinder: _gateway.transport.finder);

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
          lookUps: _gateway.transport.lookUps,
          rootDomain: _gateway.root,
          secondaryAddressFinder: _gateway.transport.finder),
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
    return _atKeysDocument(keys, _atSign);
  }

  /// Whether the encryption public key in [atKeys] is the one published at
  /// `publickey@<atSign>`; false when either is missing.
  @override
  Future<bool> publicKeysMatch(Map<String, dynamic> atKeys) async {
    final restored = atKeys[_encryptPublicKey];
    if (restored is! String) return false;
    final published = await publicLookup(
        lookUps: _gateway.transport.lookUps,
        rootDomain: _gateway.root,
        secondaryAddressFinder: _gateway.transport.finder,
        atSign: _atSign,
        key: 'publickey$_atSign');
    return published == restored;
  }

  @override
  Future<void> revoke(String enrollmentId) async {
    final command = (EnrollVerbBuilder()
          ..enrollmentId = enrollmentId
          ..operation = EnrollOperationEnum.revoke)
        .buildCommand();
    await _lookUp.executeCommand(command, auth: true);
  }

  @override
  Future<void> close() => _lookUp.close();
}

const _encryptPublicKey = 'aesEncryptPublicKey';
const _privateAuthenticationRole = 'privateAuthentication';
