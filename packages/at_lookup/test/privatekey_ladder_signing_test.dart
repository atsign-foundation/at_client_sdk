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

/// The deprecated privateKey ladder (`AtLookupImpl.authenticate`) accepts a
/// caller-supplied PKAM private key whose modulus size it does not control.
/// It signs via `signRsaPkam`, which tries every RSA size the protocol
/// defines rather than pinning the 2048-bit default — these tests pin that
/// a 4096-bit privateKey still authenticates and produces a signature that
/// verifies, rather than `RsaSigningAlgo` rejecting the modulus.
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
  const fromChallenge = 'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';
  const fromResponse = '_03fe0ff2-ac50-4c80-8f43-88480beba888@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';

  late List<String> replies;

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockSocketFactory = MockSecureSocketFactory();
    mockSecureSocketListenerFactory = MockSecureSocketListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    registerFallbackValue(SecureSocketConfig());
    mockSecureSocket = createMockAtServerSocket(host, port);

    when(() => mockSecondaryAddressFinder.findSecondary('@alice'))
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

  AtLookupImpl build() => AtLookupImpl('@alice', host, 64,
      secondaryAddressFinder: mockSecondaryAddressFinder,
      secureSocketFactory: mockSocketFactory,
      socketListenerFactory: mockSecureSocketListenerFactory,
      outboundConnectionFactory: mockOutboundConnectionFactory);

  for (final keySize in [2048, 4096]) {
    test(
        'authenticate(privateKey) with a $keySize-bit key signs the from '
        'challenge and the signature verifies', () async {
      final keyPair = await RsaSigningAlgo(keySize: keySize).generateKeyPair();
      final privateKey = base64Encode(keyPair.secretKey);
      replies = [fromChallenge, 'data:success'];

      // ignore: deprecated_member_use_from_same_package
      final result = await build().authenticate(privateKey);

      expect(result, true);
      final sentPkamCommand = verify(() => mockOutBoundConnection.write(
          captureAny(that: startsWith('pkam:')))).captured.single as String;
      final signature =
          base64Decode(sentPkamCommand.replaceFirst('pkam:', '').trim());

      await RsaSigningAlgo(keySize: keySize).verifyBytes(
          Uint8List.fromList(utf8.encode(fromResponse)),
          signature: signature,
          publicKey: keyPair.publicKey);
    });
  }
}
