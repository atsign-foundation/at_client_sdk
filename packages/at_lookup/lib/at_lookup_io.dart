/// at_lookup on a native socket: everything in `at_lookup.dart`, plus the
/// transport that reaches an atServer over TLS on TCP.
///
/// The split exists so that naming the native transport is what pulls the
/// native imports in. A caller that imports only `at_lookup.dart` and injects
/// its own transport does not acquire `dart:io` through a default it never
/// asked for — which is the way a transport swap otherwise fails silently
/// instead of failing to compile.
///
/// ⚠️ **Importing this library is not yet the only thing standing between
/// at_lookup and a non-socket transport, and it does not claim to be.**
/// `AtConnection` still exposes `Socket getSocket()`, which the message
/// listener calls and which every `implements AtConnection` would have to
/// drop. Until that member goes, a transport built on anything other than a
/// socket cannot satisfy the connection type this one produces. What this
/// split buys is that the shape is already right when that change lands,
/// rather than the change also having to remove a default.
library;

import 'package:at_commons/at_commons.dart'
    show AtRootDomain, SecureSocketConfig;

import 'src/at_lookup.dart'
    show
        AtAuthenticator,
        AtCommandExecutor,
        AtLookUp,
        AtLookUpFactory,
        AtLookupTransport;
import 'src/cache/secondary_address_finder.dart' show SecondaryAddressFinder;

export 'at_lookup.dart';

/// TLS over TCP — the transport to pass to `AtLookUp.withSecureSocket` unless
/// you are supplying your own.
///
/// A function rather than a constant because the configuration belongs to the
/// transport, and a caller has to state it: `secureSocketTransport(
/// SecureSocketConfig())` says "the TLS defaults", where a constant would let
/// a site inherit settings its neighbour set deliberately.
AtLookupTransport secureSocketTransport(
        SecureSocketConfig secureSocketConfig) =>
    AtLookupTransport(secureSocketConfig: secureSocketConfig);

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
        secondaryAddressFinder: secondaryAddressFinder,
        clientConfig: clientConfig,
        onConnect: onConnect,
      );
}
