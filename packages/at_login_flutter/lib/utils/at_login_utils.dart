import 'dart:core';
import 'dart:math';
import 'dart:io';
import 'package:basic_utils/basic_utils.dart';

class AtLoginUtils {
  static final AtLoginUtils _singleton = AtLoginUtils._internal();

  factory AtLoginUtils() {
    return _singleton;
  }

  AtLoginUtils._internal();

  String generateAlphanumeric(int len) {
    var r = Random();
    const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';
    return List.generate(len, (index) => _chars[r.nextInt(_chars.length)])
        .join();
  }

  String generateLocation(String s, bool derived) {
    var hidden;
    if (derived) {
      hidden = s;
    } else {
      hidden = generateAlphanumeric(32);
    }
    return '_' + hidden;
  }

  Future<bool> checkSSLCertViaFQDN(String fqdn) async {
    var test = false;
    var secConConnect = SecurityContext.defaultContext;
    try {
      var socket =
          await SecureSocket.connect(fqdn, 443, context: secConConnect);
      var cn = socket.peerCertificate!;
      // ignore: unnecessary_null_comparison
      if (cn != null) {
        print('Connected to: ' + socket.peerCertificate!.subject);
        // If you would like to see the cert
        //print(connection.peerCertificate.pem);
        var x509Pem = socket.peerCertificate!.pem;
        // test with an internet available certificate to ensure we are picking out the SAN and not the CN
        var data = X509Utils.x509CertificateFromPem(x509Pem);
        var subjectAlternativeName =
            data.tbsCertificate?.extensions?.subjectAlternativNames;
        var commonName = data.tbsCertificate?.subject['2.5.4.3'];
        subjectAlternativeName!.add(commonName!);
        print('SAN: $subjectAlternativeName');
        for (var i = 0; i < subjectAlternativeName.length; i++) {
          if (subjectAlternativeName[i] == fqdn ||
              subjectAlternativeName[i] == '*.$fqdn') {
            test = true;
          }
        }
      }
      await socket.close();
    } catch (e) {
      stderr.writeln(e.toString());
    }
    return test;
  }

  Future<bool> checkSSLCertViaHTTPS(String url) async {
    var test = false;
    if (url.startsWith('https://')) {
      //var secConConnect = SecurityContext.defaultContext;
      var client = HttpClient();
      try {
        await client.getUrl(Uri.parse(url));
        test = true;
      } catch (e) {
        stderr.writeln(e.toString());
        return test;
      }
      client.close(force: true);
    }
    return test;
  }
}
