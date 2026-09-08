/// at_lookup on a native socket: everything in `at_lookup.dart`, plus the
/// transport that reaches an atServer over TLS on TCP.
///
/// The split exists so that naming the native transport is what pulls the
/// native imports in. A caller that imports only `at_lookup.dart` and injects
/// its own transport does not acquire `dart:io` through a default it never
/// asked for — which is the way a transport swap otherwise fails silently
/// instead of failing to compile.
///
/// ⚠️ **The connection path is transport-neutral; the atDirectory lookup is
/// not yet.** `AtConnection` speaks `inbound`/`add` and no longer hands out a
/// socket, so a WebSocket transport satisfies it. What still reaches
/// `dart:io` from the neutral barrel is `CacheableSecondaryAddressFinder`,
/// which resolves an atSign to a host over raw TLS. It moves here next; until
/// it does, importing `at_lookup.dart` alone is not a web-safety claim.
library;

import 'package:at_commons/at_commons.dart' show SecureSocketConfig;

import 'src/at_lookup.dart' show AtLookupTransportFactories;
import 'src/io/secure_socket_transport.dart' show SecureSocketTransportFactory;

export 'at_lookup.dart';
export 'src/io/secure_socket_transport.dart';

/// TLS over TCP — the transport to pass to `AtLookUp.withSecureSocket` unless
/// you are supplying your own.
///
/// A function rather than a constant because the configuration belongs to the
/// transport, and a caller has to state it: `secureSocketTransport(
/// SecureSocketConfig())` says "the TLS defaults", where a constant would let
/// a site inherit settings its neighbour set deliberately.
AtLookupTransportFactories secureSocketTransport(
        SecureSocketConfig secureSocketConfig) =>
    AtLookupTransportFactories(
        transportFactory: SecureSocketTransportFactory(
            secureSocketConfig: secureSocketConfig));
