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

import 'package:at_commons/at_commons.dart'
    show AtRootDomain, SecureSocketConfig;

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
AtLookupTransport secureSocketTransport(
        SecureSocketConfig secureSocketConfig) =>
    AtLookupTransport(
        transportFactory: SecureSocketTransportFactory(
            secureSocketConfig: secureSocketConfig));

/// The default [AtLookUpFactory]: every connection over TLS on TCP, under
/// [config] (the TLS defaults with none), through `AtLookUp.withSecureSocket`.
///
/// [onConnect] runs on each connection once it is up and before anything else
/// is sent on it, which is how a deployment behind a proxy sends the `from:`
/// the proxy needs first.
AtLookUpFactory secureSocketLookUps({
  SecureSocketConfig? config,
  Future<void> Function(AtCommandExecutor connection)? onConnect,
}) {
  final transport = secureSocketTransport(config ?? SecureSocketConfig());
  return ({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
    Map<String, dynamic> clientConfig = const {},
  }) =>
      AtLookUp.withSecureSocket(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        transport: transport,
        secondaryAddressFinder: secondaryAddressFinder ??
            CacheableSecondaryAddressFinder(
                rootDomain.rootDomain, rootDomain.rootPort),
        clientConfig: clientConfig,
        onConnect: onConnect,
      );
}
