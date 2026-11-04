import 'dart:io';

import 'package:alfred/alfred.dart';

/// In your working directory, place a sub-directory called 'certs'
/// which needs to contain fullchain.pem and privkey.pem
/// <p/>
///
/// You can run your fake registrar at `vip.ve.atsign.zone` by linking to the
/// certs in the at_server virtual environment, as follows:
/// `ln -s /path/to/at_server repo/tools/build_virtual_environment/ve_base/contents/atsign/secondary/base/certs .`
SecurityContext getSecurityContext() {
  var secCon = SecurityContext();

  secCon.useCertificateChain('certs/fullchain.pem');
  secCon.usePrivateKey('certs/privkey.pem');
  secCon.setTrustedCertificates('/etc/cacert/cacert.pem');

  return secCon;
}

void main(List<String> args) async {
  final app = Alfred();
  logReq(HttpRequest req) async {
    final body = await req.body;
    stderr.writeln('${req.method} ${req.uri}\n'
        'Headers:\n${req.headers}\n'
        'Body:\n$body');
  }

  app.post('/api/app/v3/authenticate/atsign', (req, res) async {
    await logReq(req);

    stderr.writeln('Sending success response');
    return {'message': 'Sent Successfully'};
  });

  app.post('/api/app/v3/authenticate/atsign/activate', (req, res) async {
    await logReq(req);

    final json = await req.body as Map<String, dynamic>;
    final atSign = json['atsign'];
    final otp = json['otp'];

    if (otp != 'ABCD') {
      res.statusCode = 403;
      return {'message': 'Invalid OTP'};
    }
    stderr.writeln('Sending CRAM secret');
    return {'message': 'Verified', 'cramkey': '$atSign:${atSign.substring(1)}'};
  });

  app.all('/*', (req, res) async {
    await logReq(req);

    final Map<String, dynamic> r = {};
    return r;
  });

  await app.listenSecure(
    securityContext: getSecurityContext(),
    port: 443,
  );
}
