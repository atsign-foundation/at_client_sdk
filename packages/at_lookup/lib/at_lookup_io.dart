/// at_lookup on a native socket: everything in `at_lookup.dart`, plus the
/// transport that reaches an atServer over TLS on TCP.
///
/// The split exists so that naming the native transport is what pulls the
/// native imports in. A caller that imports only `at_lookup.dart` and injects
/// its own transport does not acquire `dart:io` through a default it never
/// asked for — which is the way a transport swap otherwise fails silently
/// instead of failing to compile.
///
/// Both halves are here: the transport that carries the atServer session, and
/// [CacheableSecondaryAddressFinder], which resolves an atSign to a host by
/// asking the atDirectory over raw TLS. A caller that imports `at_lookup.dart`
/// alone supplies both — its own [AtTransportFactory], and a
/// [SecondaryAddressFinder] such as `ProxySecondaryAddressFinder`.
library;

import 'package:at_commons/at_commons.dart' show SecureSocketConfig;

import 'at_lookup.dart';
import 'src/io/cacheable_secondary_address_finder.dart'
    show CacheableSecondaryAddressFinder;
import 'src/io/secure_socket_transport.dart' show SecureSocketTransportFactory;

export 'package:at_commons/at_commons.dart' show SecureSocketConfig;

export 'at_lookup.dart';
export 'src/io/cacheable_secondary_address_finder.dart';
export 'src/io/secure_socket_transport.dart';
export 'src/io/secure_socket_util.dart';

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

/// The pre-4.0.0 `AtLookupImpl(atSign, rootDomain, rootPort)` constructor.
///
/// Supplies the two dependencies 4.0.0 made required — a
/// [CacheableSecondaryAddressFinder] and a [SecureSocketTransportFactory] — so
/// that a call which relied on the deleted defaults becomes a one-line change.
/// New code should use [AtLookUp.withSecureSocket], which names its transport
/// explicitly and hands back an interface.
@Deprecated('Use AtLookUp.withSecureSocket. Removed in the next major release.')
AtLookupImpl atLookupOverSecureSocket(
  String atSign,
  String rootDomain,
  int rootPort, {
  String? privateKey,
  String? cramSecret,
  SecureSocketConfig? secureSocketConfig,
  Map<String, dynamic>? clientConfig,
}) =>
    // ignore: deprecated_member_use_from_same_package
    AtLookupImpl(atSign, rootDomain, rootPort,
        privateKey: privateKey,
        cramSecret: cramSecret,
        clientConfig: clientConfig,
        secondaryAddressFinder:
            CacheableSecondaryAddressFinder(rootDomain, rootPort),
        transportFactory: SecureSocketTransportFactory(
            secureSocketConfig: secureSocketConfig ?? SecureSocketConfig()));
