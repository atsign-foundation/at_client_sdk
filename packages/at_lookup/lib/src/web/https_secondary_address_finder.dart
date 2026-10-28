import 'dart:async';
import 'dart:js_interop';

import 'package:at_commons/at_commons.dart';
import 'package:web/web.dart';

import '../cache/atdirectory_answer.dart';
import '../cache/secondary_address_finder.dart';
import '../util/abandonment.dart';

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

  /// Asks for [atSign] in its canonical form.
  ///
  /// Throws [InvalidAtSignException], asking nothing, when [atSign] is not an
  /// atSign; [SecondaryNotFoundException] on a `404`;
  /// [RootServerConnectivityException] on any other failure to get an answer,
  /// a close of the lookup it asks for included; [AtTimeoutException] once
  /// [timeout] elapses; and [AtException] on an answer longer than
  /// [maxAtDirectoryAnswerBytes] or that is not `host:port`.
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    final uri = atDirectoryUri(scheme, host, port, atSign);
    final name = uri.pathSegments.single;
    final budget =
        AtNetworkTimeouts.cap(timeout ?? AtNetworkTimeouts.defaultTimeout);
    final abort = AbortController();
    var timedOut = false;
    var abandoned = false;
    final timer = Timer(budget, () {
      timedOut = true;
      abort.abort();
    });
    final unregister = Abandonment.current?.onAbandon(() {
      abandoned = true;
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
      final answer = AtDirectoryAnswer(name);
      final body = response.body;
      if (body != null) {
        final reader = body.getReader() as ReadableStreamDefaultReader;
        while (true) {
          final chunk = await reader.read().toDart;
          if (chunk.done) break;
          answer.add((chunk.value as JSUint8Array).toDart);
        }
      }
      return answer.address;
    } on AtException {
      rethrow;
    } catch (e) {
      if (abandoned) {
        throw RootServerConnectivityException(
            'atDirectory lookup for $name abandoned: its owner has closed');
      }
      if (timedOut) {
        throw AtTimeoutException(
            'atDirectory $host did not answer for $name within $budget');
      }
      throw RootServerConnectivityException(
          'unable to reach atDirectory $host for $name - $e');
    } finally {
      timer.cancel();
      unregister?.call();
      abort.abort();
    }
  }
}
