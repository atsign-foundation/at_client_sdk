// The injected authenticator is the replacement for the atChops credential
// ladder, so these tests hold both sides and use the vocabulary at_chops has
// deprecated (AtChops, AtSigningInput, AtSigningResult) to stand in for the
// old one.
// TODO(4.0): remove the ladder side with the credential ladder.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_lookup_test_utils.dart';

class FakeAtSigningInput extends Fake implements AtSigningInput {}

/// The injected authenticator, which takes over from the
/// atChops/privateKey/cramSecret ladder.
void main() {
  late OutboundConnection mockOutBoundConnection;
  late SecondaryAddressFinder mockSecondaryAddressFinder;
  late OutboundMessageListener mockOutboundListener;
  late AtLookupSecureSocketFactory mockSocketFactory;
  late AtLookupSecureSocketListenerFactory mockSecureSocketListenerFactory;
  late AtLookupOutboundConnectionFactory mockOutboundConnectionFactory;
  late AtChops mockAtChops;
  late SecureSocket mockSecureSocket;

  const host = '127.0.0.1';
  const port = 12345;
  const fromChallenge = 'data:_03fe0ff2-ac50-4c80-8f43-88480beba888@alice'
      ':c3d345fc-5691-4f90-bc34-17cba31f060f';

  /// Responses the fake atServer hands back, in order.
  late List<String> replies;

  setUp(() {
    mockOutBoundConnection = MockOutboundConnectionImpl();
    mockSecondaryAddressFinder = MockSecondaryAddressFinder();
    mockOutboundListener = MockOutboundMessageListener();
    mockSocketFactory = MockSecureSocketFactory();
    mockSecureSocketListenerFactory = MockSecureSocketListenerFactory();
    mockOutboundConnectionFactory = MockOutboundConnectionFactory();
    mockAtChops = MockAtChops();
    registerFallbackValue(SecureSocketConfig());
    registerFallbackValue(FakeAtSigningInput());
    mockSecureSocket = createMockAtServerSocket(host, port);

    when(() => mockSecondaryAddressFinder.findSecondary('@alice'))
        .thenAnswer((_) async => SecondaryAddress(host, port));
    when(() => mockSocketFactory.createSocket(host, '$port', any()))
        .thenAnswer((_) => Future<SecureSocket>.value(mockSecureSocket));
    when(() => mockOutboundConnectionFactory
        .createOutboundConnection(mockSecureSocket))
        .thenAnswer((_) => mockOutBoundConnection);
    when(() => mockSecureSocketListenerFactory
        .createListener(mockOutBoundConnection))
        .thenAnswer((_) => mockOutboundListener);
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

  test('an injected authenticator runs, and the ladder does not', () async {
    replies = [fromChallenge, 'data:success', 'data:[]'];
    final atLookup = build();
    // atChops is set too, so the ladder COULD run. This is the whole claim:
    // the injected authenticator is preferred over it, not merely available
    // when it is absent.
    atLookup.atChops = mockAtChops;
    // Stubbed so that if the ladder DID run it would succeed rather than
    // crash on an unstubbed mock. Otherwise removing the preference fails
    // this test with a type error instead of with the assertion below, and
    // a type error proves nothing about which route was taken.
    when(() => mockAtChops.sign(any()))
        .thenReturn(AtSigningResult()..result = 'ladder-signature');

    var authenticatorCalls = 0;
    atLookup.authenticator = (executor) async {
      authenticatorCalls++;
      final challenge = await executor.sendSync('from:@alice\n');
      expect(challenge, fromChallenge,
          reason: 'sendSync must return what the atServer replied');
      await executor.sendSync('pkam:signature\n');
      return true;
    };

    final result = await atLookup.executeCommand('scan\n', auth: true);

    expect(authenticatorCalls, 1, reason: 'the authenticator must have run');
    verifyNever(() => mockAtChops.sign(any()));
    expect(result, 'data:[]');
    expect(mockOutBoundConnection.getMetaData()!.isAuthenticated, isTrue,
        reason: 'a successful authenticator must be recorded on the '
            'connection, exactly as the ladder records it');
  });

  test('an authenticator reporting failure raises UnAuthenticatedException',
      () async {
    replies = [fromChallenge];
    final atLookup = build();
    atLookup.authenticator = (executor) async {
      await executor.sendSync('from:@alice\n');
      return false;
    };

    await expectLater(
        () => atLookup.executeCommand('scan\n', auth: true),
        throwsA(predicate((dynamic e) =>
            e is UnAuthenticatedException &&
            e.message.contains('The authenticator reported failure'))));
    expect(mockOutBoundConnection.getMetaData()!.isAuthenticated, isFalse,
        reason: 'a failed authentication must not be recorded');
  });

  test('with no authenticator the atChops ladder still runs', () async {
    // The "alongside" half of the seam: nothing about the existing route
    // changes while an authenticator is absent.
    replies = [fromChallenge, 'data:success', 'data:[]'];
    final atLookup = build();
    atLookup.atChops = mockAtChops;
    when(() => mockAtChops.sign(any()))
        .thenReturn(AtSigningResult()..result = 'sig');

    final result = await atLookup.executeCommand('scan\n', auth: true);

    verify(() => mockAtChops.sign(any())).called(1);
    expect(result, 'data:[]');
  });
}
