import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// The gate verb's grammar, as an atServer parses it.
void main() {
  Map<String, String?> parse(String command) {
    final Map<String, String?>? params =
        VerbUtil.getVerbParam(VerbSyntax.gate, command);
    if (params == null) {
      throw StateError('"$command" did not parse');
    }
    return params;
  }

  group("Given the gate verb's grammar", () {
    test('when the default is asked for, then it parses with no mode', () {
      final Map<String, String?> params = parse('gate:default');
      expect(params[AtConstants.gateDefault], 'default');
      expect(params[AtConstants.gateDefaultMode], isNull);
    });

    test('when the default is switched, then its mode parses', () {
      expect(parse('gate:default:ungated')[AtConstants.gateDefaultMode],
          'ungated');
      expect(parse('gate:default:closed')[AtConstants.gateDefaultMode],
          'closed');
    });

    test('when a namespace is opened, then the namespace parses with no setting',
        () {
      final Map<String, String?> params = parse('gate:rule:chat:open');
      expect(params[AtConstants.gateRule], 'rule');
      expect(params[AtConstants.gateRuleNamespace], 'chat');
      expect(params[AtConstants.gateOpen], 'open');
      expect(params[AtConstants.gateSetting], isNull);
      expect(params[AtConstants.gateClosed], isNull);
    });

    test('when a namespace is opened with a setting, then the setting and its'
        ' value parse', () {
      for (final String setting in [
        'limit',
        'window',
        'size',
        'maxQuarantined',
        'maxQuarantinedBytes'
      ]) {
        final Map<String, String?> params =
            parse('gate:rule:invitations.chat:open:$setting:3');
        expect(params[AtConstants.gateRuleNamespace], 'invitations.chat');
        expect(params[AtConstants.gateSetting], setting);
        expect(params[AtConstants.gateSettingValue], '3');
      }
    });

    test('when a namespace is closed, then it parses with or without an atSign'
        ' admitted', () {
      final Map<String, String?> closed = parse('gate:rule:chat:closed');
      expect(closed[AtConstants.gateClosed], 'closed');
      expect(closed[AtConstants.gateAdmit], isNull);
      expect(closed[AtConstants.gateOpen], isNull);

      final Map<String, String?> admitting =
          parse('gate:rule:chat:closed:admit:@bob');
      expect(admitting[AtConstants.gateClosed], 'closed');
      expect(admitting[AtConstants.gateAdmit], '@bob');
    });

    test('when an atSign is admitted, denied or removed, then the operation,'
        ' namespace and atSign parse', () {
      for (final String operation in ['admit', 'deny', 'remove']) {
        final Map<String, String?> params =
            parse('gate:$operation:x51.chat:@bob🛠');
        expect(params[AtConstants.gateSetOperation], operation);
        expect(params[AtConstants.gateSetNamespace], 'x51.chat');
        expect(params[AtConstants.gateSetAtSign], '@bob🛠');
      }
    });

    test('when the atSign-wide set is named, then its namespace parses as *', () {
      expect(parse('gate:admit:*:@dave')[AtConstants.gateSetNamespace], '*');
    });

    test('when a namespace is shown, then the namespace parses', () {
      final Map<String, String?> params = parse('gate:show:chat');
      expect(params[AtConstants.gateShow], 'show');
      expect(params[AtConstants.gateShowNamespace], 'chat');
    });

    test('when the atSign-wide set is shown, then its namespace parses as *',
        () {
      expect(parse('gate:show:*')[AtConstants.gateShowNamespace], '*');
    });

    test(
        "when a setting is returned to the operator's default, then its value"
        ' parses as default', () {
      final Map<String, String?> params =
          parse('gate:rule:invitations.chat:open:limit:default');
      expect(params[AtConstants.gateSetting], 'limit');
      expect(params[AtConstants.gateSettingValue], 'default');
    });

    test('when an atSign is checked in a namespace, then both parse', () {
      final Map<String, String?> params = parse('gate:check:chat:@bob🛠');
      expect(params[AtConstants.gateCheck], 'check');
      expect(params[AtConstants.gateCheckNamespace], 'chat');
      expect(params[AtConstants.gateCheckAtSign], '@bob🛠');
    });

    test('when the namespaces are listed, then it parses', () {
      expect(parse('gate:list')[AtConstants.gateList], 'list');
    });

    test('when a command breaks the grammar, then it does not parse', () {
      for (final String command in [
        'gate',
        'gate:',
        'gate:default:open',
        'gate:rule:chat',
        'gate:rule:chat:open:limit',
        'gate:rule:chat:open:limit:three',
        'gate:rule:chat:open:limit:defaults',
        'gate:rule:chat:open:colour:3',
        'gate:rule:chat:closed:limit:3',
        'gate:rule:chat:open:admit:@bob',
        'gate:rule:*:open',
        'gate:rule:chat:closed:admit:@bob:extra',
        'gate:admit:chat:bob',
        'gate:admit:chat',
        'gate:deny:chat:@bob:extra',
        'gate:show',
        'gate:show:chat:extra',
        'gate:check:chat',
        'gate:check:*:@bob',
        'gate:check:chat:bob',
        'gate:list:chat',
      ]) {
        expect(VerbUtil.getVerbParam(VerbSyntax.gate, command), isNull,
            reason: '"$command" is not in the grammar');
      }
    });
  });
}
