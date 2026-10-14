import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// A get of a value the atServer serves with `isEncrypted: false`, written by
/// a client that encrypted without sending the flag.
///
/// Catalogue: features/at_client/get_legacy_ciphertext_flagged_unencrypted.feature
void main() {
  const group = '{"name":"admins","members":["@bob"]}';
  // A fixed self encryption key, so the value below is deterministically not
  // ciphertext under it.
  final selfKey = base64Encode(List<int>.generate(32, (i) => i));

  late MockAtClient client;
  late MockLocalSecondary local;
  late GetResponseTransformer transformer;

  setUpAll(() {
    registerFallbackValue(FakeLocalLookUpVerbBuilder());
  });

  setUp(() {
    client = MockAtClient();
    local = MockLocalSecondary();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.getLocalSecondary()).thenReturn(local);
    when(() => local.getEncryptionSelfKey()).thenAnswer((_) async => selfKey);
    transformer = GetResponseTransformer(client);
  });

  /// The value of [key] as a get returns it, from a response serving [data]
  /// with `isEncrypted: false` and no ivNonce.
  Future<dynamic> get(AtKey key, String data) async {
    final tuple = Tuple<AtKey, String>()
      ..one = key
      ..two = jsonEncode({
        'key': '$key',
        'data': data,
        'metaData': {'isEncrypted': false},
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
}
