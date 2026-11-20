import 'package:at_client/passkey.dart';

import 'portal_session.dart' show SessionTransport;
import 'session_open.dart';
import 'session_transport.dart';
import 'session_transport_options.dart';

/// What a passkey entry point reaches the atServer with: one transport, the
/// pointer reader and the enrollment gateway built on it.
typedef PasskeyServerSide = ({
  SessionTransport transport,
  EnrollmentPointerReader pointerReader,
  AtAuthEnrollmentGateway gateway,
});

/// Builds the server side of a passkey flow for [options], by default direct.
///
/// The reader, the gateway and the clients it opens share [options]' root,
/// connections and address finder, so a proxy or a root reaches all of them.
PasskeyServerSide passkeyServerSide(
    {required SessionTransportOptions? options,
    required String app,
    required String device}) {
  final SessionTransport transport =
      sessionTransport(options ?? SessionTransportOptions());
  return (
    transport: transport,
    pointerReader: LookupEnrollmentPointerReader(
        lookUps: transport.lookUps,
        rootDomain: transport.root,
        secondaryAddressFinder: transport.finder),
    gateway: AtAuthEnrollmentGateway(
        lookUps: transport.lookUps,
        finder: transport.finder,
        root: transport.root,
        app: app,
        device: device,
        clientOpener: (
                {required lookUp,
                required atSign,
                required enrollmentId,
                required keysIo}) =>
            openSession(
                lookUp: lookUp,
                atSign: atSign,
                enrollmentId: enrollmentId,
                keysIo: keysIo,
                app: app,
                transport: transport)),
  );
}
