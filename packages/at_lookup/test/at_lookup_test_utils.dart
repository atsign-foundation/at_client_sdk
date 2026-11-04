import 'dart:async';
import 'dart:io';

import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockSecondaryUrlFinder extends Mock implements SecondaryUrlFinder {}

class MockSecureSocketFactory extends Mock
    implements AtLookupSecureSocketFactory {}

class MockStreamSubscription<T> extends Mock implements StreamSubscription<T> {}

/// Only the atDirectory lookup still speaks [SecureSocket] directly; the
/// connection path uses `FakeAtServerTransport`.
class MockSecureSocket extends Mock implements SecureSocket {
  bool destroyed = false;
}

/// For the tests that stub the whole factory chain and need the transport
/// instance they hand back to be the one they hold. Tests that only need *a*
/// transport use `FakeAtServerTransportFactory`.
class MockAtTransportFactory extends Mock implements AtTransportFactory {}

class MockMessageListenerFactory extends Mock
    implements AtLookupMessageListenerFactory {}

class MockOutboundConnectionFactory extends Mock
    implements AtLookupOutboundConnectionFactory {}

class MockOutboundMessageListener extends Mock
    implements OutboundMessageListener {}

class MockOutboundConnectionImpl extends Mock
    implements OutboundConnectionImpl {}
