import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

/// A get of a value the atServer serves with `isEncrypted: false`, written by
/// a client that encrypted it and sent no flag, or false.
///
/// Catalogue: features/at_client/get_legacy_ciphertext_flagged_unencrypted.feature
void main() {
  const group = '{"name":"admins","members":["@bob"]}';
  // A fixed self encryption key, so the value below is deterministically not
  // ciphertext under it.
  final selfKey = base64Encode(List<int>.generate(32, (i) => i));

  final logs = RecordedLogs();
  late MockAtClient client;
  late MockLocalSecondary local;
  late GetResponseTransformer transformer;

  setUpAll(() {
    logs.installOn();
    registerFallbackValue(FakeLocalLookUpVerbBuilder());
    registerFallbackValue(FakeLookupVerbBuilder());
  });

  setUp(() {
    logs.records.clear();
    client = MockAtClient();
    local = MockLocalSecondary();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.getLocalSecondary()).thenReturn(local);
    when(() => local.getEncryptionSelfKey()).thenAnswer((_) async => selfKey);
    transformer = GetResponseTransformer(client);
  });

  /// The value of [key] as a get returns it, from a response serving [data]
  /// with `isEncrypted: false`, no ivNonce, and [metaData] besides.
  Future<dynamic> get(AtKey key, String data,
      {Map<String, dynamic> metaData = const {}}) async {
    final tuple = Tuple<AtKey, String>()
      ..one = key
      ..two = jsonEncode({
        'key': '$key',
        'data': data,
        'metaData': {'isEncrypted': false, ...metaData},
      });
    return (await transformer.transform(tuple)).value;
  }

  AtKey selfRecord() => AtKey.fromString('2.groups.policy.sshnp@alice');

  test('Legacy ciphertext flagged isEncrypted false is decrypted', () async {
    final stored = EncryptionUtil.encryptValue(group, selfKey);

    expect(await get(selfRecord(), stored), group);
  });

  test('A plain value flagged isEncrypted false comes back unchanged',
      () async {
    expect(await get(selfRecord(), group), group);
    verifyNever(() => local.getEncryptionSelfKey());
  });

  test(
      'Given a plain base64 value flagged false whose decoded length is not a '
      'multiple of 16, when it is read, then it comes back unchanged without '
      'a decryption attempt', () async {
    const plain = 'true';

    expect(await get(selfRecord(), plain), plain);
    verifyNever(() => local.getEncryptionSelfKey());
  });

  test(
      'Given a plain local record flagged true that decodes as base64 but not '
      'to a multiple of 16 bytes, when it is read, then it comes back '
      'unchanged without a decryption attempt', () async {
    final key = AtKey.fromString('local:2.groups.policy.sshnp@alice');
    const plain = 'true';
    final tuple = Tuple<AtKey, String>()
      ..one = key
      ..two = jsonEncode({
        'key': '$key',
        'data': plain,
        'metaData': {'isEncrypted': true},
      });

    expect((await transformer.transform(tuple)).value, plain);
    verifyNever(() => local.getEncryptionSelfKey());
  });

  test(
      'A value with ciphertext\'s shape that does not decrypt comes back '
      'unchanged', () async {
    final stored = base64Encode(List<int>.generate(32, (i) => 255 - i));

    expect(await get(selfRecord(), stored), stored);
    verify(() => local.getEncryptionSelfKey()).called(1);
  });

  test('A record shared before at_client 3.2.1 is decrypted by its recipient',
      () async {
    final alice = RSAKeypair.fromRandom();
    final sharedKey = AESKey.generate(32).key;
    stubEncryptionKeyPair(
        local,
        '@alice',
        RsaKeyPair.create(
            alice.publicKey.toString(), alice.privateKey.toString()));
    final sealedForAlice =
        EncryptionUtil.encryptKey(sharedKey, alice.publicKey.toString());
    when(() => local.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:$sealedForAlice');
    final stored = EncryptionUtil.encryptValue(group, sharedKey);

    expect(
        await get(AtKey.fromString('@alice:2.groups.policy.sshnp@bob'), stored),
        group);
  });

  test(
      'Given a shaped value flagged false from another atSign whose shared key '
      'does not unwrap under this client\'s key, when it is read, then it '
      'comes back unchanged', () async {
    final alice = RSAKeypair.fromRandom();
    final someoneElse = RSAKeypair.fromRandom();
    stubEncryptionKeyPair(
        local,
        '@alice',
        RsaKeyPair.create(
            alice.publicKey.toString(), alice.privateKey.toString()));
    final sealedForSomeoneElse = EncryptionUtil.encryptKey(
        AESKey.generate(32).key, someoneElse.publicKey.toString());
    when(() => local.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:$sealedForSomeoneElse');
    final stored = base64Encode(List<int>.generate(32, (i) => 255 - i));

    expect(
        await get(AtKey.fromString('@alice:2.groups.policy.sshnp@bob'), stored),
        stored);
    verify(() => local.executeVerb(any<LLookupVerbBuilder>())).called(1);
  });

  test(
      'Given a shaped value flagged false and no self encryption key, when it '
      'is read, then it comes back as stored and a warning names the key',
      () async {
    final notCiphertext = AtKey.fromString('3.groups.policy.sshnp@alice');
    final junk = base64Encode(List<int>.generate(32, (i) => 255 - i));
    expect(await get(notCiphertext, junk), junk);
    expect(logs.at('INFO'), contains(contains('$notCiphertext')),
        reason: 'the control: the recorder sees this logger');
    expect(logs.at('WARNING'), isNot(contains(contains('$notCiphertext'))),
        reason: 'a value that does not decrypt is not a missing key');

    when(() => local.getEncryptionSelfKey()).thenAnswer((_) async => null);
    final key = selfRecord();
    final stored = EncryptionUtil.encryptValue(group, selfKey);

    expect(await get(key, stored), stored);
    expect(logs.at('WARNING'), contains(contains('$key')));
  });

  test(
      'Given a shaped value flagged false from another atSign and no '
      'encryption private key, when it is read, then it comes back as stored '
      'and a warning names the key', () async {
    final alice = RSAKeypair.fromRandom();
    final sharedKey = AESKey.generate(32).key;
    stubEncryptionKeyPair(
        local,
        '@alice',
        RsaKeyPair.create(
            alice.publicKey.toString(), alice.privateKey.toString()));
    when(() => local.getEncryptionPrivateKey()).thenAnswer((_) async => null);
    final sealedForAlice =
        EncryptionUtil.encryptKey(sharedKey, alice.publicKey.toString());
    when(() => local.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:$sealedForAlice');
    final key = AtKey.fromString('@alice:5.groups.policy.sshnp@bob');
    final stored = EncryptionUtil.encryptValue(group, sharedKey);

    expect(await get(key, stored), stored);
    expect(logs.at('WARNING'), contains(contains('$key')));
  });

  test(
      'Given a shaped value flagged false shared with another atSign and no '
      'shared key, when it is read, then it comes back as stored and a warning '
      'names the key', () async {
    final remote = MockRemoteSecondary();
    when(() => client.getRemoteSecondary()).thenReturn(remote);
    when(() => local.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:null');
    when(() => remote.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:null');
    final key = AtKey.fromString('@bob:6.groups.policy.sshnp@alice');
    final stored = EncryptionUtil.encryptValue(group, selfKey);

    expect(await get(key, stored), stored);
    expect(logs.at('WARNING'), contains(contains('$key')));
    expect(logs.at('INFO'), isNot(contains(contains('$key'))));
  });

  test(
      'Given a shaped value flagged false from another atSign and no '
      'shared key, when it is read, then it comes back as stored and a warning '
      'names the key', () async {
    final remote = MockRemoteSecondary();
    when(() => client.getRemoteSecondary()).thenReturn(remote);
    when(() => local.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:null');
    when(() => remote.executeVerb(any<LookupVerbBuilder>()))
        .thenAnswer((_) async => 'data:null');
    final key = AtKey.fromString('@alice:7.groups.policy.sshnp@bob');
    final stored = base64Encode(List<int>.generate(32, (i) => 255 - i));

    expect(await get(key, stored), stored);
    expect(logs.at('WARNING'), contains(contains('$key')));
    expect(logs.at('INFO'), isNot(contains(contains('$key'))));
  });

  test(
      'Given a shaped value flagged false, when the client stops while it is '
      'being decrypted, then the get throws StoppedException rather than '
      'returning it as stored', () async {
    when(() => local.getEncryptionSelfKey())
        .thenThrow(StoppedException('the client stopped'));

    await expectLater(
        get(selfRecord(), EncryptionUtil.encryptValue(group, selfKey)),
        throwsA(isA<StoppedException>()));
  });

  test(
      'Given a shaped value flagged false under a provider other than legacy, '
      'when it is read, then it comes back unchanged without a decryption '
      'attempt', () async {
    final key = AtKey.fromString('4.groups.policy.sshnp@alice');
    final stored = EncryptionUtil.encryptValue(group, selfKey);
    final otherProvider =
        Metadata.encodeAppMetadata(AppMetadata(providerId: 'other'));

    expect(
        await get(key, stored,
            metaData: {AtConstants.appMetadata: otherProvider}),
        stored);
    verifyNever(() => local.getEncryptionSelfKey());
    final messages = logs.records.map((r) => r.message);
    expect(messages, isNot(contains(contains('$key'))),
        reason: 'every attempt on this path logs a line naming the key');
  });

  test(
      'Given a value flagged false with an encoding, when it is read, then it '
      'comes back decoded without a decryption attempt', () async {
    const plain = 'thirty-two bytes of plain text!!';
    final stored = base64Encode(utf8.encode(plain));

    expect(
        await get(selfRecord(), stored,
            metaData: {AtConstants.encoding: 'base64'}),
        plain);
    verifyNever(() => local.getEncryptionSelfKey());
  });

  test(
      'Given a shaped value flagged false that decrypts under the self key to '
      'bytes that are not UTF-8, when it is read, then it comes back '
      'unchanged', () async {
    final key = selfRecord();
    final stored = base64Encode(EncryptionUtil.encryptBytes(
        List<int>.generate(20, (i) => 0xff - i), selfKey));

    expect(await get(key, stored), stored);
    verify(() => local.getEncryptionSelfKey()).called(1);
    expect(logs.at('INFO'), contains(contains('$key')));
    expect(logs.at('WARNING'), isNot(contains(contains('$key'))));
  });
}
