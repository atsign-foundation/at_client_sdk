import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';

int mockSocketNumber = 1;

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockSecondaryUrlFinder extends Mock implements SecondaryUrlFinder {}

class MockSecureSocketFactory extends Mock
    implements AtLookupSecureSocketFactory {}

class MockStreamSubscription<T> extends Mock implements StreamSubscription<T> {}

class MockSecureSocket extends Mock implements SecureSocket {
  bool destroyed = false;
  int mockNumber = mockSocketNumber++;
}

class MockSecureSocketListenerFactory extends Mock
    implements AtLookupSecureSocketListenerFactory {}

class MockOutboundConnectionFactory extends Mock
    implements AtLookupOutboundConnectionFactory {}

class MockOutboundMessageListener extends Mock
    implements OutboundMessageListener {}

/// An [AtSignatureAlgorithm] that returns a canned signature and records what it
/// was asked to sign.
///
/// A fake rather than a mock so tests can assert the exact bytes at_lookup
/// signed — the `from` challenge — and the exact key it was handed, without
/// doing real RSA work.
class FakeSignatureAlgo implements AtSignatureAlgorithm {
  FakeSignatureAlgo({
    required this.signature,
    this.signingAlgoType = SigningAlgoType.rsa2048,
    this.hashingAlgoType = HashingAlgoType.sha256,
  });

  /// Returned verbatim by [signBytes].
  final Uint8List signature;

  @override
  final SigningAlgoType signingAlgoType;

  @override
  final HashingAlgoType? hashingAlgoType;

  /// The message passed to the most recent [signBytes] call, or null if it has
  /// not been called.
  Uint8List? signedMessage;

  /// The key passed to the most recent [signBytes] call.
  Uint8List? secretKeyUsed;

  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    signedMessage = message;
    secretKeyUsed = secretKey;
    return signature;
  }

  @override
  Future<bool> verifyBytes(Uint8List message,
          {required Uint8List signature, required Uint8List publicKey}) async =>
      throw UnimplementedError();

  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() =>
      throw UnimplementedError();
}

class MockOutboundConnectionImpl extends Mock
    implements OutboundConnectionImpl {}

SecureSocket createMockAtServerSocket(String address, int port) {
  SecureSocket mss = MockSecureSocket();
  when(() => mss.destroy()).thenAnswer((invocation) {
    (mss as MockSecureSocket).destroyed = true;
  });
  when(() => mss.setOption(SocketOption.tcpNoDelay, true)).thenReturn(true);
  when(() => mss.remoteAddress).thenReturn(InternetAddress('127.0.0.66'));
  when(() => mss.remotePort).thenReturn(port);
  when(() => mss.listen(any(),
      onError: any(named: "onError"),
      onDone: any(named: "onDone"))).thenReturn(MockStreamSubscription());
  return mss;
}
