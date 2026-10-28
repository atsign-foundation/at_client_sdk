import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';

import 'secondary_address_finder.dart';

/// The most bytes an atDirectory answer may hold. A `host:port` answer needs
/// at most 253 for the host name, one for the colon and five for the port.
const int maxAtDirectoryAnswerBytes = 512;

/// Where the atDirectory at [scheme]://[host]:[port] answers for [atSign]:
/// the path is the atSign's canonical form.
///
/// Throws [InvalidAtSignException] when [atSign] is not an atSign.
Uri atDirectoryUri(String scheme, String host, int port, String atSign) =>
    Uri(
        scheme: scheme,
        host: host,
        port: port,
        pathSegments: [atSign.toAtsign()]);

/// An atDirectory's answer for [atSign], collected as it arrives.
class AtDirectoryAnswer {
  static final _hostPort = RegExp(r'^((?=[^:]{1,253}:)[A-Za-z0-9_-]{1,63}'
      r'(?:\.[A-Za-z0-9_-]{1,63})*):(\d{1,5})$');

  /// The atSign the answer is for.
  final String atSign;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  AtDirectoryAnswer(this.atSign);

  /// Adds [chunk] to the answer.
  ///
  /// Throws [AtException] once the answer holds more than
  /// [maxAtDirectoryAnswerBytes].
  void add(List<int> chunk) {
    if (_bytes.length + chunk.length > maxAtDirectoryAnswerBytes) {
      throw AtException('atDirectory answer for $atSign is longer than '
          '$maxAtDirectoryAnswerBytes bytes');
    }
    _bytes.add(chunk);
  }

  /// The atServer address the answer names.
  ///
  /// Throws [AtException] unless the answer is `host:port`: a host name of
  /// dot-separated labels of letters, digits, hyphens and underscores, and a
  /// port from 1 to 65535.
  SecondaryAddress get address {
    final answer = utf8.decode(_bytes.toBytes(), allowMalformed: true).trim();
    final match = _hostPort.firstMatch(answer);
    final port = match == null ? null : int.parse(match[2]!);
    if (port == null || port < 1 || port > 65535) {
      throw AtException(
          'atDirectory answered "$answer" for $atSign, which is not host:port');
    }
    return SecondaryAddress(match![1]!, port);
  }
}
