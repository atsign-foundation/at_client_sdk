import 'dart:async';
import 'dart:js_interop';

import 'package:at_commons/at_commons.dart';
import 'package:web/web.dart';

import '../cache/secondary_address_finder.dart';

/// Finds an atServer through the atDirectory's HTTPS face:
/// `GET scheme://host:port/@alice` answers `200` with `atServerHost:port`, or
/// `404` for an atSign it does not hold.
///
/// [scheme] is `http` only for tests.
class HttpsSecondaryAddressFinder implements SecondaryAddressFinder {
  final String host;
  final int port;
  final String scheme;

  const HttpsSecondaryAddressFinder(this.host,
      {this.port = 443, this.scheme = 'https'});

  /// Throws [SecondaryNotFoundException] on a `404`,
  /// [RootServerConnectivityException] on any other failure to get an answer,
  /// [AtTimeoutException] once [timeout] elapses, and [AtException] on an
  /// answer that is not `host:port`.
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    final name = atSign.startsWith('@') ? atSign : '@$atSign';
    final uri =
        Uri(scheme: scheme, host: host, port: port, pathSegments: [name]);
    final budget =
        AtNetworkTimeouts.cap(timeout ?? AtNetworkTimeouts.defaultTimeout);
    final abort = AbortController();
    var timedOut = false;
    final timer = Timer(budget, () {
      timedOut = true;
      abort.abort();
    });
    try {
      final response = await window
          .fetch(uri.toString().toJS, RequestInit(signal: abort.signal))
          .toDart;
      if (response.status == 404) {
        throw SecondaryNotFoundException('No entry in atDirectory for $name');
      }
      if (!response.ok) {
        throw RootServerConnectivityException(
            'atDirectory $host answered ${response.status} for $name');
      }
      return _address(name, (await response.text().toDart).toDart);
    } on AtException {
      rethrow;
    } catch (e) {
      if (timedOut) {
        throw AtTimeoutException(
            'atDirectory $host did not answer for $name within $budget');
      }
      throw RootServerConnectivityException(
          'unable to reach atDirectory $host for $name - $e');
    } finally {
      timer.cancel();
    }
  }

  static final _hostPort = RegExp(r'^([^\s:/]+):(\d{1,5})$');

  static SecondaryAddress _address(String atSign, String body) {
    final match = _hostPort.firstMatch(body.trim());
    final port = match == null ? null : int.parse(match[2]!);
    if (port == null || port < 1 || port > 65535) {
      throw AtException(
          'atDirectory answered "$body" for $atSign, which is not host:port');
    }
    return SecondaryAddress(match![1]!, port);
  }
}
