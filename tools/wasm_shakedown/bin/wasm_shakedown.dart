/// Runs every WASM gate the repo declares, in one command.
///
///     dart run wasm_shakedown
///     dart run wasm_shakedown --package at_auth
///     dart run wasm_shakedown --config path/to/gates.yaml
///     dart run wasm_shakedown --resolve-from at_chops=packages/at_chops
///
/// Named for the package, so it is the default entry point and needs no
/// `:suffix`. The gated set comes from `.github/wasm_gates.yaml` unless
/// `--config` says otherwise.
///
/// The only file here that prints; `runner.dart` produces results and
/// `verdict.dart` decides what they mean.
///
/// No `--no-compile`, deliberately: a green that is not CI-green is the failure
/// class these gates exist to prevent. And nothing writes a baseline back — the
/// failure output already prints the live walk.
library;

import 'dart:io';

import 'package:wasm_shakedown/config.dart';
import 'package:wasm_shakedown/runner.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

const _usage = '''
Runs the WASM gates declared in a gate config.

  dart run wasm_shakedown                 every gated package
  dart run wasm_shakedown --package NAME  just this one (repeatable)
  dart run wasm_shakedown --config PATH   a config other than the default

  dart run wasm_shakedown --resolve-from PACKAGE=DIR   (repeatable)
      Walk and compile PACKAGE's gate against DIR's own package config rather
      than the workspace's. For a package outside the root `workspace:` list,
      whose name resolves to the published copy in the pub cache — so its gate
      would measure a different package than this tree. DIR is relative to the
      workspace root and needs its own `dart pub get`. Every other gate is
      unaffected, so this stays one flag rather than a separate run.

Default config: $gateConfigPath, relative to the pub workspace root.
''';

Future<void> main(List<String> args) async {
  final only = <String>[];
  final resolveFrom = <String, String>{};
  String? configPath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      stdout.write(_usage);
      return;
    } else if (arg == '--package' || arg == '-p') {
      final (value, next) =
          _optionValue(args, i, '--package', 'a package name');
      only.add(value);
      i = next;
    } else if (arg == '--config' || arg == '-c') {
      final (value, next) = _optionValue(args, i, '--config', 'a path');
      configPath = value;
      i = next;
    } else if (arg == '--resolve-from') {
      final (value, next) =
          _optionValue(args, i, '--resolve-from', 'PACKAGE=DIR');
      final eq = value.indexOf('=');
      if (eq < 1) _die('--resolve-from takes PACKAGE=DIR, got "$value"');
      resolveFrom[value.substring(0, eq)] = value.substring(eq + 1);
      i = next;
    } else {
      _die('unrecognised argument "$arg"\n\n$_usage');
    }
  }

  final GateConfig config;
  try {
    config = GateConfig.load(path: configPath);
  } on GateConfigException catch (e) {
    _die('$e');
  } on FormatException catch (e) {
    // YamlException, i.e. the config is not YAML at all. A syntax error is a
    // config error like any other here, not a crash.
    _die('${configPath ?? gateConfigPath}: $e');
  } on StateError catch (e) {
    _die(e.message);
  }

  for (final name in [...only, ...resolveFrom.keys]) {
    if (config[name] == null) {
      _die('"$name" is not gated. ${config.path} lists: '
          '${config.gates.map((g) => g.package).join(', ')}');
    }
  }

  // Each --resolve-from package's own checkout directory, verified to hold a
  // package config. Never fall back to the workspace's: that is the copy the
  // flag exists to avoid, and a gate that quietly measured it would pass.
  final resolveRoots = <String, Directory>{};
  for (final MapEntry(key: package, value: path) in resolveFrom.entries) {
    final dir = Directory('${workspaceRoot().path}/$path');
    if (!File('${dir.path}/.dart_tool/package_config.json').existsSync()) {
      _die('no .dart_tool/package_config.json in $path, which $package\'s gate '
          'resolves from — run `dart pub get` there first.');
    }
    resolveRoots[package] = dir;
  }

  final gates = only.isEmpty
      ? config.gates
      : config.gates.where((g) => only.contains(g.package)).toList();

  // A union, not a replacement: a --resolve-from directory resolves its own
  // package (and wins, being spread last) while the workspace still resolves
  // every other gate in the same config.
  final roots = {
    ...resolvePackageRoots(),
    for (final dir in resolveRoots.values) ...resolvePackageRoots(from: dir),
  };

  final scopedConfig = GateConfig(gates, config.path);
  final unresolvable = scopedConfig.unresolvableBarrels(roots);
  if (unresolvable.isNotEmpty) {
    _die('${config.path} names barrels that do not exist. A renamed barrel '
        'makes a gate walk less and still pass, so this is an error:\n'
        '${unresolvable.entries.map((e) => '  ${e.key} — ${e.value}').join('\n')}');
  }

  final results = <GateResult>[];
  for (final gate in gates) {
    stdout.writeln(gate.package);
    // Per gate: a package outside the root `workspace:` list walks and compiles
    // against its own `dart pub get`, every other one against the workspace's.
    final result = await GateRunner(root: resolveRoots[gate.package]).run(gate);
    results.add(result);

    for (final ratchet in result.ratchets) {
      // Every run, pass or fail: a loose baseline shows up nowhere else.
      _line('ratchet', ratchet.verdict.figure, ratchet.holds);
    }
    for (final control in result.controls) {
      _line(
          'control',
          '${_short(control.spec.barrel)} reaches '
              '${control.verdict.target}',
          control.holds);
    }
    _line('compile', result.probe.barrels.map(_short).join(', '),
        result.probe.holds);
  }

  final failed = results.where((r) => !r.holds).toList();
  for (final result in failed) {
    for (final failure in result.failures) {
      stdout.writeln('\n${result.package}: $failure');
    }
    if (!result.probe.holds) {
      stdout.writeln('\n${result.package}: the compile probe did not build. '
          'The generated entry point is kept at ${result.probe.source} so the '
          'command can be re-run by hand:\n'
          '  dart compile wasm ${result.probe.source} -o /tmp/probe.wasm\n\n'
          '${result.probe.output}');
    }
  }

  _summary(results, config, only.isNotEmpty);
  if (failed.isNotEmpty) exitCode = 1;
}

(String, int) _optionValue(
    List<String> args, int index, String option, String valueName) {
  if (index + 1 >= args.length || args[index + 1].startsWith('-')) {
    _die('$option needs $valueName');
  }
  return (args[index + 1], index + 1);
}

void _summary(List<GateResult> results, GateConfig config, bool narrowed) {
  final ratchets = results.fold(0, (n, r) => n + r.ratchets.length);
  final controls = results.fold(0, (n, r) => n + r.controls.length);
  final failed = results.where((r) => !r.holds).length;
  // Always says how many of the configured packages ran, so --package cannot
  // read as a clean bill of health for the portfolio.
  final scope = narrowed
      ? '${results.length} of ${config.gates.length} gated packages'
      : _plural(results.length, 'gated package');
  stdout.writeln('\n$scope, ${_plural(ratchets, 'ratchet')}, '
      '${_plural(controls, 'control')}, '
      '${_plural(results.length, 'compile')} — '
      '${failed == 0 ? 'all green' : '$failed failed'}');
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

void _line(String kind, String what, bool holds) => stdout.writeln(
    '  ${kind.padRight(8)} ${what.padRight(58)} ${holds ? 'ok' : 'FAILED'}');

/// For the status lines only; failure messages carry the full URI.
String _short(String barrel) => barrel.substring(barrel.lastIndexOf('/') + 1);

Never _die(String message) {
  stderr.writeln(message);
  exit(2);
}
