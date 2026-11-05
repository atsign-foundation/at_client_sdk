import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

/// Answers a challenge-response without an atServer.
///
/// The `from:` reply has to be well formed — at_auth refuses to sign a
/// challenge that does not carry a uuid and this atSign — or every arm fails
/// for that reason instead of the one under test.
class OfflineExchange implements AtCommandExecutor {
  OfflineExchange(this.atSign);

  final String atSign;
  final List<String> sent = [];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command.trim());
    if (command.startsWith('from:')) {
      return 'data:_6c9f8b1e-6f7a-4d3b-9a1a-2f5e7c8d9012$atSign'
          ':b2d4a6c8-1e3f-4a5b-8c7d-9e0f1a2b3c4d';
    }
    return 'data:success';
  }
}

/// A port on the loopback interface that nothing listens on, so a connect to
/// it is refused at once.
Future<int> refusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// The atSign [approvingAtServer] speaks for, whose demo keys it holds.
const approvingAtSign = '@alice🛠';

/// The enrollment id [approvingAtServer] gives a request.
const approvedEnrollmentId = 'e-1';

/// The atServer and the approving client in one double, for
/// [approvingAtSign]. [decide] answers each PKAM attempt after submission:
/// `true` approves, and an exception is the atServer's refusal. [wrapped]
/// holds the symmetric key the request RSA-wrapped, shared between doubles so
/// a wait resumed against a second one can be answered with secrets sealed
/// under the same key.
({MockAtLookupImpl lookUp, List<String> sent}) approvingAtServer(
    {required Future<bool> Function(int attempt) decide,
    required List<String> wrapped}) {
  final encryptionPublicKey = demo.encryptionPublicKeyMap[approvingAtSign]!;
  final encryptionPrivateKey = demo.encryptionPrivateKeyMap[approvingAtSign]!;
  final selfEncryptionKey = demo.aesKeyMap[approvingAtSign]!;
  final lookUp = MockAtLookupImpl();
  final sent = <String>[];
  var attempts = 0;

  Future<Map<String, String>> sealed(String secret) async {
    final symmetricKey = utf8.decode((RsaEncryptionAlgo()
          ..atPrivateKey = AtPrivateKey.fromString(encryptionPrivateKey))
        .decrypt(base64Decode(wrapped.single)));
    final iv = InitialisationVector.random(16);
    final bytes = await AESEncryptionAlgo(AESKey(symmetricKey))
        .encrypt(Uint8List.fromList(utf8.encode(secret)), iv: iv);
    return {'value': base64Encode(bytes), 'iv': base64Encode(iv.ivBytes)};
  }

  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((i) async {
    final command = i.positionalArguments.first as String;
    sent.add(command);
    if (command.startsWith('enroll:')) {
      final json = jsonDecode(command.substring(
          command.indexOf('{'), command.lastIndexOf('}') + 1));
      wrapped
        ..clear()
        ..add(json['encryptedAPKAMSymmetricKey'] as String);
      return 'data:${jsonEncode({
            'enrollmentId': approvedEnrollmentId,
            'status': 'pending'
          })}';
    }
    if (command.startsWith(
        'keys:get:keyName:$approvedEnrollmentId.default_enc_private_key')) {
      return 'data:${jsonEncode(await sealed(encryptionPrivateKey))}';
    }
    if (command.startsWith(
        'keys:get:keyName:$approvedEnrollmentId.default_self_enc_key')) {
      return 'data:${jsonEncode(await sealed(selfEncryptionKey))}';
    }
    throw StateError('the mocked atServer has no answer for: $command');
  });
  when(() => lookUp.executeVerb(any())).thenAnswer((i) async {
    final builder = i.positionalArguments.first;
    if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
      return 'data:$encryptionPublicKey';
    }
    throw StateError('the mocked atServer has no answer for: '
        '${(builder as VerbBuilder).buildCommand()}');
  });
  when(() => lookUp.pkamAuthenticate())
      .thenAnswer((_) => decide(++attempts));
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(lookUp.stop).thenAnswer((_) async {});
  when(() => lookUp.dropConnection()).thenAnswer((_) async {});
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  return (lookUp: lookUp, sent: sent);
}

/// Files a request for [approvingAtSign] in the keyfile at [keysPath], as
/// `at_activate enroll` does before it waits, against an atServer that has
/// not decided it, and returns the symmetric key it wrapped for
/// [approvingAtServer].
Future<List<String>> fileRequest(
    {required String keysPath,
    required int rootPort,
    required String namespace}) async {
  final wrapped = <String>[];
  final undecided = approvingAtServer(
      decide: (_) async => throw UnAuthenticatedException(
          'Failed connecting to $approvingAtSign. '
          'error:AT0026:Apkam Auth Failed'),
      wrapped: wrapped);
  await Atsign(approvingAtSign).enroll(
      otp: 'ABC123',
      app: 'wavi',
      device: 'phone',
      namespaces: {namespace: 'rw'},
      keys: FileAtKeysIo(filePath: (_) => keysPath),
      preference: AtClientPreference()
        ..rootDomain = InternetAddress.loopbackIPv4.address
        ..rootPort = rootPort
        ..namespace = namespace,
      atLookUp: undecided.lookUp,
      lookUps: secureSocketLookUps(),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          InternetAddress.loopbackIPv4.address, rootPort));
  return wrapped;
}

/// The enrollments the keyfile at [keysPath] holds for [atSign] still
/// awaiting approval; none when there is no keyfile.
Future<List<String>> pendingIn(String keysPath, String atSign) async =>
    File(keysPath).existsSync()
        ? (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
            .pendingEnrollmentIds
            .toList()
        : [];

/// A lookup whose PKAM attempt does what [onPkam] says.
MockAtLookupImpl lookUpAnswering(Future<bool> Function() onPkam) {
  final lookUp = MockAtLookupImpl();
  when(() => lookUp.pkamAuthenticate())
      .thenAnswer((_) => onPkam());
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(lookUp.stop).thenAnswer((_) async {});
  when(() => lookUp.dropConnection()).thenAnswer((_) async {});
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  return lookUp;
}
