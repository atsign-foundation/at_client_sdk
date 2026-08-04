import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/connection/outbound_connection.dart';
import 'package:at_lookup/src/connection/outbound_connection_impl.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:at_lookup/src/util/secure_socket_util.dart';

/// Seams for substituting the socket, its listener, and the connection wrapper.
///
/// These exist only so this package's own tests can drive an [AtLookUp] or a
/// [CacheableSecondaryAddressFinder] without a real atServer. No consumer
/// constructs one, so they are absent from the `AtLookUp` factories and live on
/// `AtLookupImpl`'s constructor instead.
///
/// Only [AtLookupSecureSocketFactory] is exported, because
/// [CacheableSecondaryAddressFinder]'s constructor names it. The other two are
/// reachable only from within this package.
class AtLookupSecureSocketFactory {
  Future<SecureSocket> createSocket(
      String host, String port, SecureSocketConfig socketConfig,
      {Duration? timeout}) async {
    return await SecureSocketUtil.createSecureSocket(host, port, socketConfig,
        timeout: timeout);
  }
}

class AtLookupSecureSocketListenerFactory {
  OutboundMessageListener createListener(
      OutboundConnection outboundConnection) {
    return OutboundMessageListener(outboundConnection);
  }
}

class AtLookupOutboundConnectionFactory {
  OutboundConnection createOutboundConnection(SecureSocket secureSocket) {
    return OutboundConnectionImpl(secureSocket);
  }
}
