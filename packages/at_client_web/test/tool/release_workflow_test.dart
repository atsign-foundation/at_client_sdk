@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

Directory _repoRoot() {
  for (final start in [
    Directory.current.absolute,
    Directory('${Directory.current.path}/packages/at_client_web').absolute,
  ]) {
    var dir = start;
    while (true) {
      if (File(
              '${dir.path}/.github/workflows/at_client_web_bridge_release.yaml')
          .existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  throw StateError('could not find the repository root');
}

late String _workflow;

/// The `subject-path` lines of the attest step named [step].
List<String> _subjects(String step) {
  final lines = _workflow.split('\n');
  final at = lines.indexWhere((l) => l.contains('- name: $step'));
  expect(at, isNonNegative, reason: step);
  final start = lines.indexWhere((l) => l.contains('subject-path:'), at);
  return [
    for (var i = start + 1;
        i < lines.length && lines[i].startsWith('            ');
        i++)
      lines[i].trim(),
  ];
}

void main() {
  setUpAll(() {
    _workflow = File(
      '${_repoRoot().path}/.github/workflows/at_client_web_bridge_release.yaml',
    ).readAsStringSync();
  });

  test('Each target tag is fixed by the target', () async {
    // Run the tag step's own case block, up to the prefix choice.
    final from = _workflow.indexOf('case "\$TARGET" in');
    final to = _workflow.indexOf('esac', from) + 'esac'.length;
    final block = _workflow.substring(from, to);
    Future<ProcessResult> prefix(String target) => Process.run(
          'bash',
          ['-c', '$block\nprintf %s "\$prefix"'],
          environment: {'TARGET': target},
        );
    final js = await prefix('dart2js');
    final wasm = await prefix('dart2wasm');
    expect(js.stdout, 'at_client_web-bridge-');
    expect(wasm.stdout, 'at_client_web-bridge-wasm-');
    expect(await prefix('both'),
        isA<ProcessResult>().having((r) => r.exitCode, 'exitCode', 1));
    expect(_workflow, contains('tag="\${prefix}\${GITHUB_SHA::12}"'));
  });

  test('One checksum file covers every asset and the manifest', () {
    expect(
      _workflow,
      contains('sha256sum "\${assets[@]}" bridge-manifest.json > SHA256SUMS'),
    );
    expect(_workflow, contains('assets=(at_client_web.js)'));
    expect(
        _workflow, contains('assets=(at_client_web.wasm at_client_web.mjs)'));
    expect(_workflow, contains('sha256sum -c SHA256SUMS'));
    expect(_workflow, contains('sha256sum -c at_client_web.js.sha256'));
    expect(
      _workflow,
      contains('sha256sum at_client_web.js > at_client_web.js.sha256'),
    );
  });

  test('Attestation covers the same files as the checksum file', () {
    expect(
      RegExp('uses: actions/attest-build-provenance').allMatches(_workflow),
      hasLength(2),
    );
    expect(_subjects('Attest the dart2js bundle'), [
      'bridge/at_client_web.js',
      'bridge/at_client_web.js.sha256',
      'bridge/bridge-manifest.json',
      'bridge/SHA256SUMS',
    ]);
    expect(_subjects('Attest the dart2wasm bundle'), [
      'bridge/at_client_web.wasm',
      'bridge/at_client_web.mjs',
      'bridge/bridge-manifest.json',
      'bridge/SHA256SUMS',
    ]);
    expect(_workflow, contains("env.TARGET == 'dart2js'"));
    expect(_workflow, contains("env.TARGET == 'dart2wasm'"));
  });

  test('The release build compares its manifest with the committed one', () {
    expect(
      _workflow,
      contains('cmp build/bridge-manifest.json bridge-manifest.json'),
    );
    expect(
      _workflow.indexOf('tool/build.sh at_client_bridge_entry --target'),
      lessThan(_workflow.indexOf('cmp build/bridge-manifest.json')),
    );
    expect(
      'bridge-manifest.json'.allMatches(_workflow).length,
      greaterThanOrEqualTo(6),
    );
    expect(_workflow, contains('assets+=(at_client_web.js.sha256)'));
    expect(_workflow, contains('assets+=(bridge-manifest.json)'));
  });
}
