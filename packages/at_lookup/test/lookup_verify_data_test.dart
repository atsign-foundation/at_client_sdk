// The signature here is made the way the atSign's owner makes one, through
// at_chops' RSA SHA-256 signing, which at_chops 3.x deprecates.
// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';
import 'fake_at_server_socket.dart';

/// `lookup(verifyData: true)` returns the value only when its signature
/// verifies against the sharer's public key.
void main() {
  const host = '127.0.0.1';
  const port = 12345;

  late List<FakeAtServerSocket> sockets;
  late MockSecondaryAddressFinder addressFinder;
  late MockSecureSocketFactory socketFactory;
  // Stands in for the sharer's key pair.
  final bob = AtChopsUtil.generateAtPkamKeyPair();

  setUp(() {
    sockets = [];
    addressFinder = MockSecondaryAddressFinder();
    socketFactory = MockSecureSocketFactory();
    registerFallbackValue(SecureSocketConfig());
    when(() => addressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => socketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) async {
      final s = FakeAtServerSocket();
      sockets.add(s);
      return s;
    });
  });

  String signatureOver(String data) =>
      base64Encode(PkamSigningAlgo(bob, HashingAlgoType.sha256)
          .sign(Uint8List.fromList(utf8.encode(data))));

  /// Looks up `k@bob` with verifyData, the atServer answering with [data]
  /// signed by [signature] and with bob's public key.
  Future<String> lookupVerified(String data, String signature) async {
    final atLookup = AtLookUp.withSecureSocket(
      atSign: '@alice',
      rootDomain: const AtRootDomain(host, 64),
      authenticator: (_) async => true,
      secondaryAddressFinder: addressFinder,
      transport: AtLookupTransport(
        secureSocketConfig: SecureSocketConfig(),
        socketFactory: socketFactory,
      ),
    );
    final result = atLookup.lookup('k', '@bob', verifyData: true);

    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets.single.written.last, 'lookup:all:k@bob\n');
    final record = jsonEncode({
      'data': data,
      'metaData': {'dataSignature': signature}
    });
    await sockets.single.serverSends('data:$record\n@alice@');

    await Future.delayed(const Duration(milliseconds: 50));
    expect(sockets.single.written.last, 'plookup:publickey@bob\n');
    await sockets.single
        .serverSends('data:${bob.atPublicKey.publicKey}\n@alice@');

    try {
      return await result;
    } finally {
      await atLookup.stop();
    }
  }

  test('returns the value when its signature verifies', () async {
    expect(await lookupVerified('good', signatureOver('good')), 'data:good');
  });

  test('does not return a value whose signature does not verify', () async {
    expect(await lookupVerified('changed', signatureOver('good')), 'data:null',
        reason: 'a value signed for other data is not verified data');
  });
}
