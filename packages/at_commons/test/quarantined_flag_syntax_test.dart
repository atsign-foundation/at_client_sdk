import 'dart:collection';

import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// The quarantined flag by which monitor, notify:list and notify:fetch ask
/// for notifications from quarantined atSigns, as an atServer parses it.
void main() {
  HashMap<String, String?> parse(String syntax, String command) {
    final HashMap<String, String?>? params =
        VerbUtil.getVerbParam(syntax, command);
    if (params == null) {
      throw StateError('"$command" did not parse');
    }
    return params;
  }

  group('Given the monitor grammar', () {
    test('when monitor asks for quarantined notifications, then the flag parses',
        () {
      expect(parse(VerbSyntax.monitor, 'monitor:quarantined')[
          AtConstants.quarantined], 'quarantined');
    });

    test('when it asks beside every other flag, then each parses', () {
      final HashMap<String, String?> params = parse(VerbSyntax.monitor,
          'monitor:strict:selfNotifications:multiplexed:quarantined:12345 .*chat');
      expect(params[AtConstants.monitorStrictMode], 'strict');
      expect(params[AtConstants.monitorSelfNotifications], 'selfNotifications');
      expect(params[AtConstants.monitorMultiplexedMode], 'multiplexed');
      expect(params[AtConstants.quarantined], 'quarantined');
      expect(params[AtConstants.epochMilliseconds], '12345');
      expect(params[AtConstants.monitorRegex], '.*chat');
    });

    test('when monitor does not ask, then the flag is absent', () {
      expect(parse(VerbSyntax.monitor, 'monitor:strict .*chat')[
          AtConstants.quarantined], isNull);
    });
  });

  group('Given the notify:list grammar', () {
    test('when notify:list asks, then the flag parses and no regex does', () {
      final HashMap<String, String?> params =
          parse(VerbSyntax.notifyList, 'notify:list:quarantined');
      expect(params[AtConstants.quarantined], 'quarantined');
      expect(params['regex'], isNull);
    });

    test('when it asks with dates and a regex, then each parses', () {
      final HashMap<String, String?> params = parse(VerbSyntax.notifyList,
          'notify:list:quarantined:2026-10-01:2026-10-11:.*chat');
      expect(params[AtConstants.quarantined], 'quarantined');
      expect(params['fromDate'], '2026-10-01');
      expect(params['toDate'], '2026-10-11');
      expect(params['regex'], '.*chat');
    });

    test('when it does not ask, then a regex parses as before', () {
      final HashMap<String, String?> params =
          parse(VerbSyntax.notifyList, 'notify:list:.*chat');
      expect(params[AtConstants.quarantined], isNull);
      expect(params['regex'], '.*chat');
    });
  });

  group('Given the notify:fetch grammar', () {
    test('when notify:fetch asks, then the id and the flag parse', () {
      final HashMap<String, String?> params = parse(VerbSyntax.notifyFetch,
          'notify:fetch:6e2b3c4d-0000-4000-8000-000000000001:quarantined');
      expect(params['notificationId'], '6e2b3c4d-0000-4000-8000-000000000001');
      expect(params[AtConstants.quarantined], 'quarantined');
    });

    test('when it does not ask, then the id parses whole, colons included',
        () {
      expect(parse(VerbSyntax.notifyFetch, 'notify:fetch:abc')['notificationId'],
          'abc');
      final HashMap<String, String?> params =
          parse(VerbSyntax.notifyFetch, 'notify:fetch:a:b');
      expect(params['notificationId'], 'a:b');
      expect(params[AtConstants.quarantined], isNull);
    });
  });
}
