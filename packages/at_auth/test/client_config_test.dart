// The keys a PKAM signs with are set through their flat fields.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/auth/program_name.dart';
import 'package:at_auth/src/auth/program_name_stub.dart' as no_io;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils/from_recorder.dart';

/// A value of a clientConfig key that is not a string.
class _Spelt {
  _Spelt(this.text);

  final String text;

  @override
  String toString() => text;
}

void main() {
  const atSign = '@alice🛠';
  final atAuthVersion = pubspecVersion();

  group('clientConfigFor', () {
    test('an absent app version, SDK name and SDK version take at_auth\'s', () {
      final config = clientConfigFor(appName: 'acme_chat');

      expect(config['appName'], 'acme_chat');
      expect(config['appVersion'], 'unknown');
      expect(config['sdkName'], 'atsign.dart.at_auth');
      expect(config['sdkVersion'], atAuthVersion,
          reason: 'at_auth names its own version, the one its pubspec '
              'declares');
    });

    test('an absent app name is the name of the program file', () {
      final programFile = Platform.script.pathSegments.last;

      expect(clientConfigFor()['appName'], programFile.split('.').first,
          reason: 'the program file is $programFile; its name is what comes '
              'before the first dot');
    });

    test('an empty value counts as absent', () {
      final config = clientConfigFor(
          appName: '', appVersion: '', sdkName: '', sdkVersion: '');

      expect(config['appName'], isNotEmpty);
      expect(config['appVersion'], 'unknown');
      expect(config['sdkName'], 'atsign.dart.at_auth');
      expect(config['sdkVersion'], atAuthVersion);
    });

    test('a value that is only whitespace counts as absent', () {
      final config = clientConfigFor(
          appName: ' \t', appVersion: '\u2028', sdkName: '\n', sdkVersion: ' ');

      expect(config['appName'], clientConfigFor()['appName'],
          reason: 'an app named in whitespace is named after its program file');
      expect(config['appVersion'], 'unknown');
      expect(config['sdkName'], 'atsign.dart.at_auth');
      expect(config['sdkVersion'], atAuthVersion);
    });

    test('given values are sent as given, under these four keys', () {
      expect(
          clientConfigFor(
              appName: 'acme_chat',
              appVersion: '2.3.1',
              sdkName: 'atsign.dart.at_client',
              sdkVersion: '4.1.0'),
          {
            'appName': 'acme_chat',
            'appVersion': '2.3.1',
            'sdkName': 'atsign.dart.at_client',
            'sdkVersion': '4.1.0',
          });
    });

    test('each value longer than 64 characters is cut to its first 64', () {
      final config = clientConfigFor(
          appName: 'a' * 80,
          appVersion: 'b' * 80,
          sdkName: 'c' * 80,
          sdkVersion: 'd' * 80);

      expect(config['appName'], 'a' * 64);
      expect(config['appVersion'], 'b' * 64);
      expect(config['sdkName'], 'c' * 64);
      expect(config['sdkVersion'], 'd' * 64);
    });

    test('with no version given, none is sent', () {
      for (final version in [null, '', ' \t']) {
        expect(clientConfigFor(appName: 'acme_chat', version: version),
            isNot(contains('version')),
            reason:
                'at_auth adds no version of its own: ${jsonEncode(version)}');
      }
    });

    test('a version, when given, is sent as version, cut like the others', () {
      expect(clientConfigFor(version: '4.1.0')['version'], '4.1.0');
      expect(clientConfigFor(version: 'v\u2028${'9' * 80}')['version'],
          'v ${'9' * 62}');
    });

    test('a value of exactly 64 characters is sent whole', () {
      expect(clientConfigFor(appName: 'a' * 64)['appName'], 'a' * 64);
    });

    test('a cut never leaves half of a surrogate pair', () {
      // The emoji is two code units, the 64th and 65th.
      final config = clientConfigFor(appName: '${'a' * 63}😀b');

      expect(config['appName'], 'a' * 63,
          reason: 'a lone high surrogate is not text; the atServer would '
              'decode and log a malformed name');
    });

    test(
        'a cut keeps out the high surrogate of U+10000, the lowest pair, when '
        'it is the 64th code unit', () {
      expect(clientConfigFor(appName: '${'a' * 63}\u{10000}b')['appName'],
          'a' * 63,
          reason: 'U+D800, the lowest high surrogate, would be left alone');
    });

    test(
        'a cut keeps out the high surrogate of U+10FFFF, the highest pair, '
        'when it is the 64th code unit', () {
      expect(clientConfigFor(appName: '${'a' * 63}\u{10FFFF}b')['appName'],
          'a' * 63,
          reason: 'U+DBFF, the highest high surrogate, would be left alone');
    });

    test('a pair that ends at the 64th code unit is kept whole', () {
      expect(clientConfigFor(appName: '${'a' * 62}\u{10000}b')['appName'],
          '${'a' * 62}\u{10000}',
          reason: 'U+DC00, the lowest low surrogate, ends the pair; it is not '
              'half of one');
    });

    test(
        'a from: whose appName holds a line or paragraph separator still '
        'matches the from: syntax', () {
      final syntax = RegExp(VerbSyntax.from);
      String fromCommand(String appName) => (FromVerbBuilder()
            ..atSign = '@alice'
            ..clientConfig = clientConfigFor(appName: appName))
          .buildCommand()
          .trim();

      expect(syntax.hasMatch(fromCommand('acme_chat')), isTrue,
          reason: 'the control: a plain from: matches');
      expect(syntax.hasMatch(fromCommand('acme\u2028chat\u2029app')), isTrue,
          reason: 'the atServer parses from: with this syntax, whose `.` '
              'matches neither separator, and JSON leaves both raw');
      expect(clientConfigFor(appName: 'acme\u2028chat\u2029app')['appName'],
          'acme chat app');
    });
  });

  group('the name of the program file', () {
    test('a script run from acme_chat.dart is acme_chat', () {
      expect(programNameOf(() => Uri.file('/home/me/acme_chat.dart')),
          'acme_chat');
    });

    test('a pub snapshot named at_activate.dart-3.14.0.snapshot is at_activate',
        () {
      expect(
          programNameOf(() => Uri.file(
              '/home/me/.dart_tool/pub/bin/at_client_cli/at_activate.dart-3.14.0.snapshot')),
          'at_activate');
    });

    test('an executable compiled as at_activate is at_activate', () {
      expect(programNameOf(() => Uri.file('/usr/local/bin/at_activate')),
          'at_activate');
    });

    test('a Windows executable at_activate.exe is at_activate', () {
      expect(
          programNameOf(() => Uri.file(
              r'C:\Program Files\atsign\at_activate.exe',
              windows: true)),
          'at_activate');
    });

    test('a file whose name starts with a dot names nothing, so is "unknown"',
        () {
      expect(programNameOf(() => Uri.file('/home/me/.hidden')), 'unknown');
    });

    test('a script that cannot be read is "unknown"', () {
      expect(programNameOf(() => throw UnsupportedError('no script here')),
          'unknown');
    });

    test('a script that is not a file is "unknown"', () {
      expect(
          programNameOf(() => Uri.dataFromString('void main() {}',
              mimeType: 'application/dart')),
          'unknown',
          reason: 'a data: URI holds the program\'s source, which is never '
              'sent');
    });

    test('a platform without dart:io has no program file, so is "unknown"', () {
      expect(no_io.derivedProgramName(), 'unknown');
    });
  });

  group('an authenticator fills the four values its caller leaves out', () {
    final keys = InMemoryAtKeysIo.holding(
        atSign,
        AtKeys()
          ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
          ..apkamPrivateKey =
              AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!));

    final builders =
        <String, AtAuthenticator Function(Map<String, dynamic> clientConfig)>{
      'authenticatorFor, signing PKAM': (config) =>
          authenticatorFor(keys, atSign, clientConfig: config),
      // An empty store reads as no keyfile, which is when CRAM applies.
      'authenticatorFor, falling back to CRAM': (config) => authenticatorFor(
          InMemoryAtKeysIo(), atSign,
          cramSecret: 'secret', clientConfig: config),
      'authenticatorForPrivateKey': (config) =>
          authenticatorForPrivateKey(atSign, 'unused', clientConfig: config),
      'authenticatorForCramSecret': (config) =>
          authenticatorForCramSecret(atSign, 'secret', clientConfig: config),
    };

    Future<Map<String, dynamic>> sentBy(AtAuthenticator authenticator) async {
      final recorder = FromRecorder();
      await authenticator(recorder);
      const prefix = 'from:$atSign:clientConfig:';
      expect(recorder.from, startsWith(prefix),
          reason: 'the authenticator sent from: without a clientConfig');
      return jsonDecode(recorder.from!.substring(prefix.length).trim())
          as Map<String, dynamic>;
    }

    builders.forEach((name, build) {
      group(name, () {
        test('the caller\'s keys win, the rest are filled, others pass through',
            () async {
          final config = await sentBy(build({
            'appName': 'acme_chat',
            'version': '9.9.9',
            'clientId': '42',
            'platform': 'macos',
          }));

          expect(config, {
            'appName': 'acme_chat',
            'version': '9.9.9',
            'clientId': '42',
            'platform': 'macos',
            'appVersion': 'unknown',
            'sdkName': 'atsign.dart.at_auth',
            'sdkVersion': atAuthVersion,
          });
        });

        test('a caller that passes none sends at_auth\'s four and no more',
            () async {
          final config = await sentBy(build(const {}));

          expect(config.keys.toSet(),
              {'appName', 'appVersion', 'sdkName', 'sdkVersion'},
              reason: 'at_auth adds no version: only a caller\'s is sent');
          expect(config['sdkName'], 'atsign.dart.at_auth');
        });

        test('the caller\'s values are cut to 64 characters too', () async {
          final config = await sentBy(build({'appName': 'a' * 80}));

          expect(config['appName'], 'a' * 64);
        });

        test(
            'every string the caller passes, under any key, is one line and '
            'cut to 64 characters', () async {
          final long = 'mac\u2028os\u2029${'x' * 80}';
          final sendable = 'mac os ${'x' * 57}';

          final config = await sentBy(build({
            'platform': long,
            'clientId': long,
            'version': long,
            'extra': long,
            'retries': 3,
          }));

          expect(config['platform'], sendable);
          expect(config['clientId'], sendable);
          expect(config['version'], sendable);
          expect(config['extra'], sendable);
          expect(config['retries'], 3,
              reason: 'a value that is not a string, of a key other than the '
                  'four, is passed through');
        });

        test(
            'a separator in a key, or in a string nested in a Map or List, '
            'still gives a from: that matches the from: syntax', () async {
          final given = {
            'a b': 'x',
            'meta': {
              'note': 'a b ${'x' * 80}',
              'c d': ['e f', 4],
            },
          };
          final recorder = FromRecorder();
          await build(given)(recorder);

          expect(RegExp(VerbSyntax.from).hasMatch(recorder.from!.trim()),
              isTrue,
              reason: 'the atServer parses from: with this syntax, whose `.` '
                  'matches neither separator, and JSON leaves both raw');
          final config = await sentBy(build(given));
          expect(config['a b'], 'x');
          expect(config['meta'], {
            'note': 'a b ${'x' * 60}',
            'c d': ['e f', 4],
          });
        });

        test(
            'one of the four that is not a string is sent as its text, made '
            'sendable', () async {
          final config = await sentBy(build({
            'appName': _Spelt('acme\u2028chat${'x' * 80}'),
            'appVersion': 2,
            'sdkName': _Spelt(' '),
          }));

          expect(config['appName'], 'acme chat${'x' * 55}');
          expect(config['appVersion'], '2',
              reason: 'the caller\'s value, not at_auth\'s "unknown"');
          expect(config['sdkName'], 'atsign.dart.at_auth',
              reason: 'a value whose text is only whitespace counts as absent');
        });
      });
    });
  });
}
