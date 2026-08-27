import 'dart:io';

import 'package:at_utils/at_logger.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A `dart:io` HTTP client for registrar calls, able to ignore certificate
/// problems when told to.
///
/// [RegistrarService] defaults to a plain `package:http` client, which
/// validates certificates and works under WASM. Pass [create]'s result as its
/// `httpClient` to get the `dart:io` stack instead, which is what makes
/// [allowBadCertificates] available.
class RegistrarIoClient {
  RegistrarIoClient._();

  /// Whether to accept a registrar certificate that fails validation —
  /// expired, self-signed, or naming a different host.
  ///
  /// **Off by default, and it should stay off outside testing.** A registrar
  /// call carries the API key that registers atSigns; accepting any
  /// certificate means accepting any interceptor holding one. It exists
  /// because a test registrar is usually self-signed, and every bypass is
  /// announced at `shout` so it cannot pass unnoticed in a log.
  static bool allowBadCertificates = false;

  static final AtSignLogger _logger = AtSignLogger('RegistrarIoClient');

  /// A client honouring [allowBadCertificates] as it stands when a request is
  /// made — the flag is read per certificate, not captured here.
  static http.Client create() {
    final ioc = HttpClient();
    ioc.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (allowBadCertificates) {
        _logger.shout('*************');
        _logger
            .shout('************* Ignoring bad certificate from $host:$port');
        _logger.shout('*************');
        return true;
      }
      return false;
    };
    return IOClient(ioc);
  }
}
