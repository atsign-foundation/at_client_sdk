import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/test_keypairs.dart';

/// The two forms an atServer's global exception handler writes a refusal in:
/// plain on a connection whose `from:` named no version, JSON on one whose
/// `from:` named a version above 3.0.37.
final Map<String, String Function(String code, String description)> forms = {
  'plain': (code, description) => 'error:$code-$description',
  'JSON': (code, description) => 'error:${jsonEncode({
            'errorCode': code,
            'errorDescription': description,
          })}',
};

/// Each reader of an atServer's refusal reads it the same in either form.
void main() {
  const atSign = '@alice';
  const pkamRefused = 'Exception: pkam authentication failed';
  const causes = {
    'AT0401': AtConnectionCause.unauthenticated,
    'AT0027': AtConnectionCause.revoked,
    'AT0029': AtConnectionCause.invalidEnrollment,
    'AT0025': AtConnectionCause.enrollmentDenied,
    'AT0026': AtConnectionCause.enrollmentNotApproved,
  };
  final keys = keysHoldingApkam(atSign, null, pkamKeyPairFor(atSign, null));
  final logs = RecordedLogs();
  late List<Duration> defaultStartRetries;

  setUpAll(() {
    logs.installOn(level: 'warning');
    defaultStartRetries = Monitor.startRetryDelays;
    Monitor.startRetryDelays = const [Duration(milliseconds: 20)];
  });

  tearDownAll(() => Monitor.startRetryDelays = defaultStartRetries);

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  forms.forEach((form, refusal) {
    group('Given an atServer that refuses a PKAM in the $form form', () {
      causes.forEach((code, cause) {
        test(
            'when the start-up key check authenticates and is refused with '
            '$code, then it is refused as ${cause.name}', () async {
          final server =
              FakeAtServer(atSign: atSign, runsClientAuthenticator: true)
                ..refuseClientAuth = (_) => refusal(code, pkamRefused);

          await expectLater(
              Atsign(atSign).authenticatesAs(
                  keys: keys,
                  rootDomain: const AtRootDomain('127.0.0.1', 64),
                  lookUps: server.lookUps,
                  secondaryAddressFinder: server.addressFinder),
              throwsA(isA<AtCredentialRefusedException>()
                  .having((e) => e.state.cause, 'cause', cause)));
        });

        test(
            'when a verb connection is refused with $code, then the failure '
            'is classified as ${cause.name}', () {
          final failure = AtLookUpException('AT0401',
              'Exception: Failed connecting to $atSign. ${refusal(code, pkamRefused)}');

          expect(classifyConnectionFailure(failure)?.cause, cause);
        });
      });

      test(
          'when the notification connection authenticates, then the monitor '
          'retries until it is accepted, and logs the code', () async {
        final server =
            FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
        final client = await Atsign(atSign).open(
            keys: keys,
            preference: AtClientPreference()
              ..namespace = 'wavi'
              ..rootDomain = '127.0.0.1'
              ..atClientParticulars.appName = 'acme_chat',
            storage:
                InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
            lookUps: server.lookUps,
            secondaryAddressFinder: server.addressFinder);
        final monitorLookUp =
            (client.notificationService as NotificationServiceImpl)
                .monitor
                .lookUp;
        var refusals = 2;
        server.refuseClientAuth = (lookUp) =>
            identical(lookUp, monitorLookUp) && refusals-- > 0
                ? refusal('AT0401', pkamRefused)
                : null;
        final warningsBefore = logs.at('WARNING').length;

        client.notificationService.subscribe(regex: '.*');
        await server.waitUntil(() => server.monitorCount > 0,
            what: 'the monitor starting');

        expect(refusals, lessThan(0),
            reason: 'both refusals were sent, and the third login accepted');
        expect(
            logs
                .at('WARNING')
                .skip(warningsBefore)
                .where((w) => w.startsWith('Failed to start notifications'))
                .where((w) => w.contains('AT0401')),
            hasLength(2));
      });
    });
  });
}
