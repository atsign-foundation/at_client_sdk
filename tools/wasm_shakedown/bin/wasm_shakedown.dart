/// Runs every WASM gate the repo declares, in one command.
///
///     dart run wasm_shakedown
///     dart run wasm_shakedown --package at_auth
///     dart run wasm_shakedown --config path/to/gates.yaml
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

Default config: $gateConfigPath, relative to the pub workspace root.
''';

Future<void> main(List<String> args) async {
  final only = <String>[];
  String? configPath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      stdout.write(_usage);
      return;
    } else if (arg == '--package' || arg == '-p') {
      if (i + 1 >= args.length) _die('--package needs a package name');
      only.add(args[++i]);
    } else if (arg == '--config' || arg == '-c') {
      if (i + 1 >= args.length) _die('--config needs a path');
      configPath = args[++i];
    } else {
      _die('unrecognised argument "$arg"\n\n$_usage');
    }
  }

  final GateConfig config;
  try {
    config = GateConfig.load(path: configPath);
  } on GateConfigException catch (e) {
    _die('$e');
  }

  final unresolvable = config.unresolvableBarrels(resolvePackageRoots());
  if (unresolvable.isNotEmpty) {
    _die('${config.path} names barrels that do not exist. A renamed barrel '
        'makes a gate walk less and still pass, so this is an error:\n'
        '${unresolvable.entries.map((e) => '  ${e.key} — ${e.value}').join('\n')}');
  }

  for (final name in only) {
    if (config[name] == null) {
      _die('"$name" is not gated. ${config.path} lists: '
          '${config.gates.map((g) => g.package).join(', ')}');
    }
  }

  final gates = only.isEmpty
      ? config.gates
      : config.gates.where((g) => only.contains(g.package)).toList();

  final runner = GateRunner();
  final results = <GateResult>[];
  for (final gate in gates) {
    stdout.writeln(gate.package);
    final result = await runner.run(gate);
    results.add(result);

    for (final ratchet in result.ratchets) {
      // Every run, pass or fail: a loose baseline shows up nowhere else.
      stdout.writeln('  ${ratchet.verdict.figure}');
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
