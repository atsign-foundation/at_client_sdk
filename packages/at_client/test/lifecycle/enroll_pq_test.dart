// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/secret_sharing/envelope_addressing.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope, apskUri;
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart' show AtLookUp, AtLookUpException;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/remote_backed_client.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// The at_auth half of an approval, recorded rather than run: what matters
/// here is the symmetric key at_client minted for the pq request, which the
/// atServer-side double below seals the atSign's secrets under.
class _RecordingAtEnrollment extends Mock implements AtEnrollment {
  String? apkamSymmetricKey;

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision decision, AtLookUp atLookUp,
      {required ApproverKeyMaterial approverKeys}) async {
    apkamSymmetricKey = decision.mintedApkamSymmetricKey;
    return AtEnrollmentResponse(
        decision.enrollmentId, EnrollmentStatus.approved);
  }
}

/// `Atsign.enroll` under a post-quantum posture, approved by at_client's own
/// approver: the symmetric key travels sealed to the enrollment's key
/// package rather than RSA-wrapped, and `awaitApproval` opens it before it
/// can read the secrets the approver sealed under it.
///
/// The approver is the real `EnrollmentServiceImpl.approve` on a remote-backed
/// mock client, so the envelope is the one production seals; the enrollee's
/// atServer is a mocked lookup serving that client's remote data.
void main() {
  const atSign = '@alice🛠';
  const enrollmentId = 'pq-1';
  final encryptionPublicKey = demo.encryptionPublicKeyMap[atSign]!;
  final encryptionPrivateKey = demo.encryptionPrivateKeyMap[atSign]!;
  final selfEncryptionKey = demo.aesKeyMap[atSign]!;
  late Directory dir;
  late Map<String, String> remoteData;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue(AtKey());
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('enroll_pq_');
    remoteData = {};
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// A secret sealed under [symmetricKey] the way the approval handshake
  /// stores the atSign's secrets for the enrollee.
  Future<Map<String, String>> sealed(String secret, String symmetricKey) async {
    final iv = InitialisationVector.random(16);
    final bytes = await AESEncryptionAlgo(AESKey(symmetricKey))
        .encrypt(Uint8List.fromList(utf8.encode(secret)), iv: iv);
    return {'value': base64Encode(bytes), 'iv': base64Encode(iv.ivBytes)};
  }

  test(
      'a pq enrollment completes: the symmetric key sealed to its key '
      'package is opened, and the secrets under it read', () async {
    // The enrollee's atServer: answers by verb, and serves whatever the
    // approver's client wrote to the shared remote data.
    final lookUp = MockAtLookupImpl();
    Map<String, dynamic>? submitted;
    var approved = false;
    String? symmetricKey;
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      if (command.startsWith('enroll:request:')) {
        submitted = jsonDecode(command.substring(
            command.indexOf('{'), command.lastIndexOf('}') + 1));
        return 'data:${jsonEncode({
              'enrollmentId': enrollmentId,
              'status': 'pending'
            })}';
      }
      if (command.startsWith('scan ')) {
        final regex = RegExp(command.substring('scan '.length).trim());
        return 'data:${jsonEncode(remoteData.keys.where(regex.hasMatch).toList())}';
      }
      if (command.startsWith('llookup:')) {
        final key = command.substring('llookup:'.length).trim();
        final value = remoteData[key];
        if (value == null) {
          throw AtLookUpException('AT0015', 'key not found: $key');
        }
        return 'data:$value';
      }
      if (command.startsWith(
          'keys:get:keyName:$enrollmentId.default_enc_private_key')) {
        return 'data:${jsonEncode(await sealed(encryptionPrivateKey, symmetricKey!))}';
      }
      if (command
          .startsWith('keys:get:keyName:$enrollmentId.default_self_enc_key')) {
        return 'data:${jsonEncode(await sealed(selfEncryptionKey, symmetricKey!))}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
        return 'data:$encryptionPublicKey';
      }
      throw StateError('the mocked atServer has no answer for: '
          '${(builder as VerbBuilder).buildCommand()}');
    });
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async {
      if (approved) return true;
      throw AtLookUpException('AT0026', 'enrollment $enrollmentId is pending');
    });
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);

    // 1. The enrollee submits under a post-quantum posture.
    final store = InMemoryAtKeysIo();
    final pending = await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'wavi',
        device: 'phone',
        namespaces: {'wavi': 'rw'},
        keys: store,
        preference: AtClientPreference(posture: PqPosture.pqReady)
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = await refusedPort()
          ..hiveStoragePath = dir.path
          ..namespace = 'lifecycle',
        atLookUp: lookUp);
    expect(pending.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
    expect(submitted?['encryptedAPKAMSymmetricKey'], isNull,
        reason: 'nothing RSA-wrapped rides a pq request');
    final keyPackage = submitted?['metadata']?['keyPackage'];
    expect(keyPackage, isNotNull, reason: 'the approver seals to this');

    // 2. The atSign's owner approves through at_client's own approver, which
    //    mints the symmetric key and seals it to the advertised key package.
    final approver = buildRemoteBackedMockClient(
        atSign: atSign, enrollmentId: 'approver-1', remoteData: remoteData);
    stubApproverKeys(approver);
    when(() => approver.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return Future.value(
          remoteData.keys.where(regex.hasMatch).map(AtKey.fromString).toList());
    });
    when(() => approver.atKeysIo).thenReturn(null);
    await AtClientSecretSharing.forClient(approver).register();
    stubApproveListReads(
        approver.getRemoteSecondary()!,
        'data:${jsonEncode({
              '$enrollmentId.new.enrollments.__manage$atSign': {
                'appName': 'wavi',
                'deviceName': 'phone',
                'namespace': {'wavi': 'rw'},
                'metadata': {'keyPackage': keyPackage},
              }
            })}');
    // The atServer mints the enrollment's _apsk at approval from the signing
    // key the request advertised; this atServer is a map, so it is placed.
    remoteData[apskUri(atSign, enrollmentId)] =
        submitted!['apskLegacy'] as String;
    final recording = _RecordingAtEnrollment();
    await EnrollmentServiceImpl(approver, recording).approve(
        EnrollmentRequestDecision.approved(
            enrollmentId: enrollmentId,
            apkamSymmetricKey: AtBytes.fromString(''),
            atSign: atSign));
    symmetricKey = recording.apkamSymmetricKey;
    expect(symmetricKey, isNotEmpty,
        reason: 'the approver mints the symmetric key for a pq request');
    final kpid = ((SignedEnvelope.fromJson(keyPackage as Map).payload
            as Map)['keys'] as List)
        .single['kid'] as String;
    expect(
        remoteData.keys
            .where(RegExp(EnvelopeAddressing.regexFor(kpid)).hasMatch)
            .toList(),
        isNotEmpty,
        reason: 'the envelope sealed to key package $kpid reached the '
            'atServer; it holds: ${remoteData.keys.toList()}');
    approved = true;

    // 3. The enrollee completes: the envelope is found, verified against the
    //    approver\'s published signing key, opened with the key package's
    //    private half, and the secrets under the symmetric key are read.
    await pending.awaitApproval(retryInterval: Duration.zero);

    final completed = await store.read(atSign);
    expect(completed.pendingEnrollmentIds, isEmpty);
    expect(completed.apkamSymmetricKey?.toString(), symmetricKey,
        reason: 'the key the approver sealed to the key package');
    expect(completed.selfEncryptionKey?.key, selfEncryptionKey,
        reason: 'opened with that key, so the whole pq exchange worked');
    expect(completed.encryptionKeyPair?.atPrivateKey.privateKey, isNotNull);
  });
}
