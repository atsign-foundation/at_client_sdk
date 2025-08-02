import 'dart:io';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

class SecureSocketUtil {
  static AtSignLogger _logger = AtSignLogger('SecureSocketUtil');
  ///method that creates and returns a [SecureSocket]. If [decryptPackets] is set to true,the TLS keys are logged into a file.
  static Future<SecureSocket> createSecureSocket(
      String host, String port, SecureSocketConfig secureSocketConfig) async {
    SecurityContext securityContext = SecurityContext.defaultContext;

    bool certsProvided = false;
    if (secureSocketConfig.pathToCerts != null &&
        await File(secureSocketConfig.pathToCerts!).exists()) {
      securityContext.setTrustedCertificates(secureSocketConfig.pathToCerts!);
      certsProvided = true;
    }

    if (!secureSocketConfig.decryptPackets) {
      SecureSocket aSecureSocket = await SecureSocket.connect(
        host,
        int.parse(port),
        context: securityContext,
      );
      aSecureSocket.setOption(SocketOption.tcpNoDelay, true);
      return aSecureSocket;
    } else {
      // USE ONLY FOR DEBUGGING / DEMO PURPOSES
      _logger.warning('decryptPackets is set;'
          ' it should only be set for demo or debugging purposes');
      try {
        File? keysFile = secureSocketConfig.tlsKeysSavePath != null
            ? File(secureSocketConfig.tlsKeysSavePath!)
            : null;
        if (!certsProvided) {
          throw AtException(
              'decryptPackets set to true but path to trusted certificated not provided');
        }
        SecureSocket aSecureSocket = await SecureSocket.connect(host, int.parse(port),
            context: securityContext,
            keyLog: (line) =>
                keysFile?.writeAsStringSync(line, mode: FileMode.append));
        aSecureSocket.setOption(SocketOption.tcpNoDelay, true);
        return aSecureSocket;
      } catch (e) {
        throw AtException(e.toString());
      }
    }
  }
}
