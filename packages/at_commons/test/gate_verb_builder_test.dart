import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// [GateVerbBuilder] builds the gate verb's commands, as `VerbSyntax.gate`
/// parses them, from arguments that cannot form a command it refuses.
///
/// Race: none can arise. A builder is an immutable value made from its
/// arguments, with no shared state and no I/O.
/// Replay: none. It builds a command and issues nothing.
/// DoS: it sends nothing itself, and refuses malformed input before any
/// command exists. An atSign is held to 55 characters by [Atsign]; a
/// namespace's length is left to the atServer.
/// Forgery: no field can add a segment or a second command. A namespace
/// refuses `:`, `@` and line breaks, and an atSign is made by [Atsign], which
/// refuses `:`, a second `@`, whitespace and control characters; the builder
/// makes it again in case a String was cast to one.
/// Impersonation: an atSign in a command is only data. Who may run each
/// command is the atServer's decision, on the connection's own authentication.
void main() {
  final Atsign bob = '@bob'.toAtsign();

  group("Given a GateVerbBuilder for the atSign's default", () {
    test('when it reads the default, then it builds `gate:default`', () {
      expect(GateVerbBuilder.readDefault().buildCommand(), 'gate:default\n');
    });

    test(
        'when it switches the default to closed, then it builds'
        ' `gate:default:closed`', () {
      expect(GateVerbBuilder.switchDefault(GateDefault.closed).buildCommand(),
          'gate:default:closed\n');
    });

    test(
        'when it switches the default to ungated, then it builds'
        ' `gate:default:ungated`', () {
      expect(GateVerbBuilder.switchDefault(GateDefault.ungated).buildCommand(),
          'gate:default:ungated\n');
    });
  });

  group("Given a GateVerbBuilder for a namespace's rule", () {
    test('when it opens a namespace, then it builds `gate:rule:chat:open`', () {
      expect(
          GateVerbBuilder.open('chat').buildCommand(), 'gate:rule:chat:open\n');
    });

    group(
        'when it opens a namespace with a setting, then it builds the setting'
        ' and its value', () {
      final Map<GateSetting, (int, String)> settings = {
        GateSetting.limit: (3, 'gate:rule:invitations.chat:open:limit:3\n'),
        GateSetting.window: (
          7200,
          'gate:rule:invitations.chat:open:window:7200\n'
        ),
        GateSetting.size: (1024, 'gate:rule:invitations.chat:open:size:1024\n'),
        GateSetting.maxQuarantined: (
          2,
          'gate:rule:invitations.chat:open:maxQuarantined:2\n'
        ),
        GateSetting.maxQuarantinedBytes: (
          1048576,
          'gate:rule:invitations.chat:open:maxQuarantinedBytes:1048576\n'
        ),
      };
      settings.forEach((GateSetting setting, (int, String) expected) {
        test(expected.$2.trim(), () {
          expect(
              GateVerbBuilder.openWith('invitations.chat', setting, expected.$1)
                  .buildCommand(),
              expected.$2);
        });
      });
    });

    test(
        'when it returns a setting to the default, then it builds'
        ' `gate:rule:invitations.chat:open:limit:default`', () {
      expect(
          GateVerbBuilder.openWithDefault('invitations.chat', GateSetting.limit)
              .buildCommand(),
          'gate:rule:invitations.chat:open:limit:default\n');
    });

    test('when it closes a namespace, then it builds `gate:rule:chat:closed`',
        () {
      expect(GateVerbBuilder.close('chat').buildCommand(),
          'gate:rule:chat:closed\n');
    });

    test(
        'when it closes a namespace admitting an atSign, then it builds'
        ' `gate:rule:chat:closed:admit:@bob`', () {
      expect(GateVerbBuilder.close('chat', admit: bob).buildCommand(),
          'gate:rule:chat:closed:admit:@bob\n');
    });

    test(
        "when it removes a namespace's rule, then it builds"
        ' `gate:rule:chat:none`', () {
      expect(GateVerbBuilder.removeRule('chat').buildCommand(),
          'gate:rule:chat:none\n');
    });
  });

  group("Given a GateVerbBuilder for a namespace's sets", () {
    test('when it admits an atSign, then it builds `gate:admit:chat:@bob`', () {
      expect(GateVerbBuilder.admit('chat', bob).buildCommand(),
          'gate:admit:chat:@bob\n');
    });

    test('when it denies an atSign, then it builds `gate:deny:chat:@bob`', () {
      expect(GateVerbBuilder.deny('chat', bob).buildCommand(),
          'gate:deny:chat:@bob\n');
    });

    test('when it removes an atSign, then it builds `gate:remove:chat:@bob`',
        () {
      expect(GateVerbBuilder.remove('chat', bob).buildCommand(),
          'gate:remove:chat:@bob\n');
    });

    test(
        'when it admits an atSign atSign-wide, then it builds'
        ' `gate:admit:*:@bob`', () {
      expect(GateVerbBuilder.admitAtSignWide(bob).buildCommand(),
          'gate:admit:*:@bob\n');
    });

    test(
        'when it removes an atSign atSign-wide, then it builds'
        ' `gate:remove:*:@bob`', () {
      expect(GateVerbBuilder.removeAtSignWide(bob).buildCommand(),
          'gate:remove:*:@bob\n');
    });
  });

  group('Given a GateVerbBuilder for a read', () {
    test('when it shows a namespace, then it builds `gate:show:chat`', () {
      expect(GateVerbBuilder.show('chat').buildCommand(), 'gate:show:chat\n');
    });

    test(
        'when it shows the atSign-wide admitted set, then it builds'
        ' `gate:show:*`', () {
      expect(GateVerbBuilder.showAtSignWide().buildCommand(), 'gate:show:*\n');
    });

    test('when it checks an atSign, then it builds `gate:check:chat:@bob`', () {
      expect(GateVerbBuilder.check('chat', bob).buildCommand(),
          'gate:check:chat:@bob\n');
    });

    test('when it lists the namespaces, then it builds `gate:list`', () {
      expect(GateVerbBuilder.list().buildCommand(), 'gate:list\n');
    });
  });

  group('Given any command a GateVerbBuilder builds', () {
    final Map<String, (GateVerbBuilder, Map<String, String?>)> built = {
      'readDefault': (
        GateVerbBuilder.readDefault(),
        {AtConstants.gateDefault: 'default', AtConstants.gateDefaultMode: null}
      ),
      'switchDefault': (
        GateVerbBuilder.switchDefault(GateDefault.closed),
        {AtConstants.gateDefaultMode: 'closed'}
      ),
      'open': (
        GateVerbBuilder.open('chat'),
        {
          AtConstants.gateRuleNamespace: 'chat',
          AtConstants.gateOpen: 'open',
          AtConstants.gateSetting: null
        }
      ),
      'openWith': (
        GateVerbBuilder.openWith('invitations.chat', GateSetting.window, 7200),
        {
          AtConstants.gateRuleNamespace: 'invitations.chat',
          AtConstants.gateSetting: 'window',
          AtConstants.gateSettingValue: '7200'
        }
      ),
      'openWithDefault': (
        GateVerbBuilder.openWithDefault('invitations.chat', GateSetting.size),
        {
          AtConstants.gateRuleNamespace: 'invitations.chat',
          AtConstants.gateSetting: 'size',
          AtConstants.gateSettingValue: 'default'
        }
      ),
      'close': (
        GateVerbBuilder.close('chat'),
        {
          AtConstants.gateRuleNamespace: 'chat',
          AtConstants.gateClosed: 'closed',
          AtConstants.gateAdmit: null
        }
      ),
      'close admitting': (
        GateVerbBuilder.close('chat', admit: bob),
        {AtConstants.gateRuleNamespace: 'chat', AtConstants.gateAdmit: '@bob'}
      ),
      'removeRule': (
        GateVerbBuilder.removeRule('chat'),
        {AtConstants.gateRuleNamespace: 'chat', AtConstants.gateNone: 'none'}
      ),
      'admit': (
        GateVerbBuilder.admit('chat', bob),
        {
          AtConstants.gateSetOperation: 'admit',
          AtConstants.gateSetNamespace: 'chat',
          AtConstants.gateSetAtSign: '@bob'
        }
      ),
      'deny': (
        GateVerbBuilder.deny('chat', bob),
        {
          AtConstants.gateSetOperation: 'deny',
          AtConstants.gateSetNamespace: 'chat',
          AtConstants.gateSetAtSign: '@bob'
        }
      ),
      'remove': (
        GateVerbBuilder.remove('chat', bob),
        {
          AtConstants.gateSetOperation: 'remove',
          AtConstants.gateSetNamespace: 'chat',
          AtConstants.gateSetAtSign: '@bob'
        }
      ),
      'admitAtSignWide': (
        GateVerbBuilder.admitAtSignWide(bob),
        {
          AtConstants.gateSetOperation: 'admit',
          AtConstants.gateSetNamespace: '*',
          AtConstants.gateSetAtSign: '@bob'
        }
      ),
      'removeAtSignWide': (
        GateVerbBuilder.removeAtSignWide(bob),
        {
          AtConstants.gateSetOperation: 'remove',
          AtConstants.gateSetNamespace: '*',
          AtConstants.gateSetAtSign: '@bob'
        }
      ),
      'show': (
        GateVerbBuilder.show('chat'),
        {AtConstants.gateShow: 'show', AtConstants.gateShowNamespace: 'chat'}
      ),
      'showAtSignWide': (
        GateVerbBuilder.showAtSignWide(),
        {AtConstants.gateShowNamespace: '*'}
      ),
      'check': (
        GateVerbBuilder.check('chat', bob),
        {
          AtConstants.gateCheckNamespace: 'chat',
          AtConstants.gateCheckAtSign: '@bob'
        }
      ),
      'list': (GateVerbBuilder.list(), {AtConstants.gateList: 'list'}),
    };

    group(
        'when it is parsed with VerbSyntax.gate, then it gives back the'
        ' namespace, atSign, setting and value it was built from', () {
      built.forEach(
          (String name, (GateVerbBuilder, Map<String, String?>) entry) {
        test(name, () {
          final String command = entry.$1.buildCommand();
          expect(command, endsWith('\n'));
          final String line = command.substring(0, command.length - 1);
          expect(line, isNot(contains('\n')),
              reason: 'one command, ended by its one line break');
          final Map<String, String?>? params =
              VerbUtil.getVerbParam(VerbSyntax.gate, line);
          expect(params, isNotNull, reason: '"$line" must parse');
          entry.$2.forEach((String param, String? value) {
            expect(params![param], value, reason: '$param of "$line"');
          });
        });
      });
    });

    test('when checkParams is asked, then it answers true', () {
      for (final (GateVerbBuilder, Map<String, String?>) entry
          in built.values) {
        expect(entry.$1.checkParams(), isTrue, reason: entry.$1.buildCommand());
      }
    });
  });

  group('Given inputs the builder tidies', () {
    test(
        "when a namespace has capitals, then it is lower-cased:"
        " `open('Invitations.Chat')` builds `gate:rule:invitations.chat:open`",
        () {
      expect(GateVerbBuilder.open('Invitations.Chat').buildCommand(),
          'gate:rule:invitations.chat:open\n');
    });

    test(
        "when an atSign is an Atsign, then it is built as Atsign made it:"
        " `admit('chat', 'Bob'.toAtsign())` builds `gate:admit:chat:@bob`", () {
      expect(GateVerbBuilder.admit('chat', 'Bob'.toAtsign()).buildCommand(),
          'gate:admit:chat:@bob\n');
    });

    test(
        'when an atSign is an emoji atSign, then it is built as given:'
        ' `@alice\u{1F6E0}`', () {
      expect(
          GateVerbBuilder.admit('chat', '@alice\u{1F6E0}'.toAtsign())
              .buildCommand(),
          'gate:admit:chat:@alice\u{1F6E0}\n');
    });
  });

  group('Given inputs the builder refuses', () {
    final Map<String, GateVerbBuilder Function(String)> takingANamespace = {
      'open': (String ns) => GateVerbBuilder.open(ns),
      'openWith': (String ns) =>
          GateVerbBuilder.openWith(ns, GateSetting.limit, 3),
      'openWithDefault': (String ns) =>
          GateVerbBuilder.openWithDefault(ns, GateSetting.limit),
      'close': (String ns) => GateVerbBuilder.close(ns),
      'removeRule': (String ns) => GateVerbBuilder.removeRule(ns),
      'admit': (String ns) => GateVerbBuilder.admit(ns, bob),
      'deny': (String ns) => GateVerbBuilder.deny(ns, bob),
      'remove': (String ns) => GateVerbBuilder.remove(ns, bob),
      'show': (String ns) => GateVerbBuilder.show(ns),
      'check': (String ns) => GateVerbBuilder.check(ns, bob),
    };

    final Map<String, GateVerbBuilder Function(Atsign)> takingAnAtSign = {
      'close admitting': (Atsign a) => GateVerbBuilder.close('chat', admit: a),
      'admit': (Atsign a) => GateVerbBuilder.admit('chat', a),
      'deny': (Atsign a) => GateVerbBuilder.deny('chat', a),
      'remove': (Atsign a) => GateVerbBuilder.remove('chat', a),
      'admitAtSignWide': (Atsign a) => GateVerbBuilder.admitAtSignWide(a),
      'removeAtSignWide': (Atsign a) => GateVerbBuilder.removeAtSignWide(a),
      'check': (Atsign a) => GateVerbBuilder.check('chat', a),
    };

    group(
        'when a namespace is not dot-separated labels of word characters and'
        ' hyphens, then it refuses with `ArgumentError` naming the namespace',
        () {
      final Map<String, String> refused = {
        '.chat': '.chat',
        'chat.': 'chat.',
        'a..chat': 'a..chat',
        'the empty string': '',
        'chat:x': 'chat:x',
        'chat@x': 'chat@x',
        '*': '*',
        'ch at': 'ch at',
        'a namespace holding a line break': 'chat\nscan',
      };
      refused.forEach((String name, String namespace) {
        test(name, () {
          takingANamespace.forEach(
              (String constructor, GateVerbBuilder Function(String) build) {
            expect(
                () => build(namespace),
                throwsA(isA<ArgumentError>()
                    .having((e) => e.name, 'name', 'namespace')
                    .having((e) => e.invalidValue, 'invalidValue', namespace)),
                reason: constructor);
          });
        });
      });
    });

    group(
        'when a String cast to Atsign is not an atSign, then it refuses as'
        ' Atsign does', () {
      final Map<String, String> refused = {
        r"'@bob\nscan' as Atsign": '@bob\nscan',
        "'@bo b' as Atsign": '@bo b',
        'one with 56 characters after its "@"': '@${'a' * 56}',
      };
      refused.forEach((String name, String notAnAtSign) {
        test(name, () {
          takingAnAtSign.forEach(
              (String constructor, GateVerbBuilder Function(Atsign) build) {
            expect(() => build(notAnAtSign as Atsign),
                throwsA(isA<InvalidAtSignException>()),
                reason: constructor);
          });
        });
      });
    });

    test(
        "when a String cast to Atsign is untidy, then it is built as Atsign"
        " would make it: `'Bob' as Atsign` builds `@bob`", () {
      expect(GateVerbBuilder.admit('chat', 'Bob' as Atsign).buildCommand(),
          'gate:admit:chat:@bob\n');
    });

    test(
        'when a setting value is negative, then it refuses with `ArgumentError`',
        () {
      expect(() => GateVerbBuilder.openWith('chat', GateSetting.limit, -1),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'value')));
    });
  });
}
