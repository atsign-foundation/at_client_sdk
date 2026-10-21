import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';

/// `lookup(verifyData: true)` verifies a peer's data signature with the
/// stateless at_chops 4 [RsaSigningAlgo.verifyBytes], which throws on a
/// failed verification rather than returning false. These tests use a real
/// generated key pair and a real signature, rather than a mock, because the
/// property under test — a forged or mismatched signature can never be
/// returned as verified data — depends on the actual verification math, not
/// on what a mock is told to answer.
void main() {
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtLookupSecureSocketFactory mockSocketFactory;
  late AtLookupSecureSocketListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;
  late SecureSocket mockSecureSocket;

  const host = '127.0.0.1';
  const port = 12345;

  /// Responses the fake atServer hands back, in order: the data lookup, then
  /// the public key lookup.
  late List<String> replies;

  late Uint8List publicKey;
  late Uint8List secretKey;

  setUpAll(() async {
    final keyPair = await RsaSigningAlgo().generateKeyPair();
    publicKey = keyPair.publicKey;
    secretKey = keyPair.secretKey;
  });

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockSocketFactory = MockSecureSocketFactory();
    mockSecureSocketListenerFactory = MockSecureSocketListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    registerFallbackValue(SecureSocketConfig());
    mockSecureSocket = createMockAtServerSocket(host, port);

    when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => mockSocketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) => Future<SecureSocket>.value(mockSecureSocket));
    when(() => mockOutboundConnectionFactory.createOutboundConnection(
        mockSecureSocket)).thenAnswer((_) => mockOutBoundConnection);
    when(() => mockSecureSocketListenerFactory.createListener(
        mockOutBoundConnection)).thenAnswer((_) => mockOutboundListener);
    when(() => mockOutBoundConnection.getMetaData())
        .thenReturn(OutboundConnectionMetadata()..isAuthenticated = false);
    when(() => mockOutBoundConnection.isInValid()).thenReturn(false);
    when(() => mockOutBoundConnection.write(any()))
        .thenAnswer((_) => Future.value());

    replies = [];
    when(() => mockOutboundListener.read())
        .thenAnswer((_) => Future.value(replies.removeAt(0)));
  });

  AtLookupImpl build() => AtLookupImpl('@bob', host, 64,
      secondaryAddressFinder: mockSecondaryAddressFinder,
      secureSocketFactory: mockSocketFactory,
      socketListenerFactory: mockSecureSocketListenerFactory,
      outboundConnectionFactory: mockOutboundConnectionFactory);

  /// A `lookup:all` response naming [value] and [signature], as the atServer
  /// would format it.
  String lookupReply(String value, Uint8List signature) => 'data:'
      '${json.encode({
            'data': value,
            'metaData': {'dataSignature': base64Encode(signature)}
          })}';

  test('a genuine signature verifies and the data is returned', () async {
    const value = 'the data a peer actually wrote';
    final signature = await RsaSigningAlgo().signBytes(
        Uint8List.fromList(utf8.encode(value)),
        secretKey: secretKey);
    replies = [
      lookupReply(value, signature),
      'data:${base64Encode(publicKey)}'
    ];

    final result =
        await build().lookup('phone', '@bob', auth: false, verifyData: true);

    expect(result, 'data:$value');
  });

  test('a forged signature is rejected: no data is returned', () async {
    const value = 'the data a peer actually wrote';
    const forgedValue = 'data an attacker substituted';
    // Signed over different bytes than [value] claims to carry: exactly what
    // a man-in-the-middle substituting the payload after signing would
    // produce.
    final forgedSignature = await RsaSigningAlgo().signBytes(
        Uint8List.fromList(utf8.encode(forgedValue)),
        secretKey: secretKey);
    replies = [
      lookupReply(value, forgedSignature),
      'data:${base64Encode(publicKey)}'
    ];

    final result =
        await build().lookup('phone', '@bob', auth: false, verifyData: true);

    expect(result, 'data:null',
        reason: 'verifyBytes throws on a failed verification, and that must '
            'never be read as verified data');
  });

  test('a signature from an unrelated key is rejected', () async {
    const value = 'the data a peer actually wrote';
    final attackerKeyPair = await RsaSigningAlgo().generateKeyPair();
    final attackerSignature = await RsaSigningAlgo().signBytes(
        Uint8List.fromList(utf8.encode(value)),
        secretKey: attackerKeyPair.secretKey);
    replies = [
      lookupReply(value, attackerSignature),
      'data:${base64Encode(publicKey)}'
    ];

    final result =
        await build().lookup('phone', '@bob', auth: false, verifyData: true);

    expect(result, 'data:null',
        reason: 'a signature that verifies under a different key must not '
            'verify under the atKey this lookup actually returned');
  });
}
