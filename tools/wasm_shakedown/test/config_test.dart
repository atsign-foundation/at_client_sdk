// Reads the real .github/wasm_gates.yaml off disk, so VM only like the rest.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wasm_shakedown/config.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// Parses [source] with a fixed set of known package names.
GateConfig _parse(String source) => GateConfig.parse(source,
    path: '.github/wasm_gates.yaml',
    knownPackages: const ['at_auth', 'at_chops', 'at_utils']);

/// A minimal valid stanza, for mutating one field at a time.
const _valid = '''
at_auth:
  ratchets:
    - barrel: package:at_auth/at_auth.dart
      max_blocked_packages: 4
      min_files_walked: 850
  probe:
    - package:at_auth/at_auth.dart
''';

void main() {
  group('the real .github/wasm_gates.yaml', () {
    late GateConfig config;

    setUpAll(() => config = GateConfig.load());

    // Nothing here names a package or a baseline. Adding a package is meant to
    // be one stanza, and this suite gates `wasm_ratchet` — so an assertion that
    // has to be edited alongside the config would turn onboarding a package, or
    // tightening a baseline, into a red tooling job that skips the gates
    // entirely. Everything below is a property every stanza must have.
    test('gates at least one package, so the checks below are not vacuous', () {
      expect(config.gates, isNotEmpty);
    });

    test('every barrel it names resolves to a file on disk', () {
      // Stops a renamed barrel making a gate walk less and still pass.
      expect(config.unresolvableBarrels(resolvePackageRoots()), isEmpty);
    });

    test('every gate has a ratchet with usable baselines', () {
      for (final gate in config.gates) {
        expect(gate.ratchets, isNotEmpty, reason: gate.package);
        for (final ratchet in gate.ratchets) {
          // Near the real figure, not 1: every other ratchet check is about
          // what the walk did not find, and a stalled walk finds nothing.
          expect(ratchet.minFilesWalked, greaterThan(1),
              reason: '${gate.package} ${ratchet.barrel}');
          expect(ratchet.maxBlockedPackages, greaterThanOrEqualTo(0),
              reason: '${gate.package} ${ratchet.barrel}');
        }
      }
    });

    test('every gated package has at least one probe barrel', () {
      // A probe importing nothing compiles clean forever.
      for (final gate in config.gates) {
        expect(gate.probe, isNotEmpty, reason: gate.package);
      }
    });

    test('every gated package has a positive control', () {
      // Not enforced by the parser — a package might have no platform seam.
      // Every package gated so far has one, and losing it would make an empty
      // offender set unfalsifiable.
      for (final gate in config.gates) {
        expect(gate.controls, isNotEmpty, reason: gate.package);
      }
    });
  });

  group('load', () {
    test('finds the default config from anywhere in the repo', () {
      final root = workspaceRoot();
      final fromPackage =
          GateConfig.load(from: Directory('${root.path}/packages/at_auth'));
      expect(fromPackage.gates.map((g) => g.package),
          GateConfig.load().gates.map((g) => g.package));
    });

    test('an explicit path is taken as given', () {
      // What --config reaches, and what CI passes so the workflow names the
      // file rather than leaning on the default.
      final config =
          GateConfig.load(path: '${workspaceRoot().path}/$gateConfigPath');
      expect(config.gates, isNotEmpty);
      expect(config.path, endsWith(gateConfigPath));
    });

    test('a missing config names the path it tried', () {
      expect(
          () => GateConfig.load(path: 'no/such/gates.yaml'),
          throwsA(isA<GateConfigException>().having(
              (e) => e.message, 'message', contains('no/such/gates.yaml'))));
    });
  });

  group('parsing rejects', () {
    test('a package this workspace does not have', () {
      expect(
          () => _parse('at_chpos:\n  ratchets: []\n  probe: []\n'),
          throwsA(isA<GateConfigException>()
              .having((e) => e.message, 'message', contains('at_chpos'))));
    });

    test('an unknown key, naming the line and what is allowed', () {
      expect(
          () => _parse('$_valid  contorls: []\n'),
          throwsA(isA<GateConfigException>()
              .having((e) => e.message, 'message', contains('contorls'))));
    });

    test('a control naming neither axis', () {
      expect(
          () => _parse('''$_valid  controls:
    - barrel: package:at_auth/at_auth_io.dart
      because: nothing in particular
'''),
          throwsA(isA<GateConfigException>().having((e) => e.message, 'message',
              contains('control asserting nothing'))));
    });

    test('a gate with no ratchets', () {
      expect(
          () => _parse('at_auth:\n  ratchets: []\n'
              '  probe: [package:at_auth/at_auth.dart]\n'),
          throwsA(isA<GateConfigException>()
              .having((e) => e.message, 'message', contains('no ratchets'))));
    });

    test('a gate with no probe barrels', () {
      expect(
          () => _parse('at_auth:\n'
              '  ratchets:\n'
              '    - barrel: package:at_auth/at_auth.dart\n'
              '      max_blocked_packages: 4\n'
              '      min_files_walked: 850\n'
              '  probe: []\n'),
          throwsA(isA<GateConfigException>().having((e) => e.message, 'message',
              contains('compiles clean forever'))));
    });

    test('a barrel that is not a package: URI', () {
      expect(
          () => _parse('at_auth:\n'
              '  ratchets:\n'
              '    - barrel: lib/at_auth.dart\n'
              '      max_blocked_packages: 4\n'
              '      min_files_walked: 850\n'
              '  probe: [package:at_auth/at_auth.dart]\n'),
          throwsA(isA<GateConfigException>()
              .having((e) => e.message, 'message', contains('package: URI'))));
    });

    test('a missing baseline field', () {
      expect(
          () => _parse('at_auth:\n'
              '  ratchets:\n'
              '    - barrel: package:at_auth/at_auth.dart\n'
              '      max_blocked_packages: 4\n'
              '  probe: [package:at_auth/at_auth.dart]\n'),
          throwsA(isA<GateConfigException>().having(
              (e) => e.message, 'message', contains('min_files_walked'))));
    });

    test('a baseline that is not a number', () {
      expect(
          () => _parse('at_auth:\n'
              '  ratchets:\n'
              '    - barrel: package:at_auth/at_auth.dart\n'
              '      max_blocked_packages: four\n'
              '      min_files_walked: 850\n'
              '  probe: [package:at_auth/at_auth.dart]\n'),
          throwsA(isA<GateConfigException>()
              .having((e) => e.message, 'message', contains('must be int'))));
    });

    test('an unknown control environment', () {
      expect(
          () => _parse('''$_valid  controls:
    - barrel: package:at_auth/at_auth_io.dart
      reaches_library: dart:io
      because: the filesystem code
      environment: node
'''),
          throwsA(isA<GateConfigException>()
              .having((e) => e.message, 'message', contains('"io" or "web"'))));
    });
  });

  group('parsing accepts', () {
    test('a control defaults to io semantics', () {
      final config = _parse('''$_valid  controls:
    - barrel: package:at_auth/at_auth_io.dart
      reaches_library: dart:io
      because: the filesystem code
''');
      expect(config['at_auth']!.controls.single.environment, ioEnvironment);
    });

    test('a control with both axes, and an explicit web environment', () {
      final config = _parse('''$_valid  controls:
    - barrel: package:at_auth/at_auth.dart
      reaches_file: lib/src/auth/socket_probe_io.dart
      reaches_library: dart:io
      because: the conditional seam
      environment: web
''');
      final control = config['at_auth']!.controls.single;
      expect(control.reachesFile, 'lib/src/auth/socket_probe_io.dart');
      expect(control.reachesLibrary, 'dart:io');
      expect(control.environment, webEnvironment);
    });

    test('a gate with no controls at all', () {
      expect(_parse(_valid)['at_auth']!.controls, isEmpty);
    });

    test('allowed_offenders omitted, meaning none', () {
      expect(
          _parse(_valid)['at_auth']!.ratchets.single.allowedOffenders, isEmpty);
    });

    test(
        'an unresolvable barrel is reported, not thrown, so the message can '
        'list every one', () {
      final config = _parse('at_auth:\n'
          '  ratchets:\n'
          '    - barrel: package:at_auth/renamed.dart\n'
          '      max_blocked_packages: 4\n'
          '      min_files_walked: 850\n'
          '  probe: [package:at_auth/at_auth.dart]\n');
      expect(config.unresolvableBarrels(resolvePackageRoots()),
          contains('package:at_auth/renamed.dart'));
    });
  });

  group('workspaceRoot', () {
    test('resolves the same root from a deep package directory', () {
      // A walk-up that stopped at the first pubspec.yaml would land on
      // at_auth, so the fixture is deliberately deep.
      final root = workspaceRoot();
      final deep = Directory('${root.path}/packages/at_auth/lib/src/keys/io');
      expect(deep.existsSync(), isTrue, reason: 'fixture path moved');
      expect(workspaceRoot(from: deep).path, root.path);
    });

    test('terminates at the filesystem root rather than looping', () {
      expect(() => workspaceRoot(from: Directory('/')),
          throwsA(isA<StateError>()));
    });
  });
}
