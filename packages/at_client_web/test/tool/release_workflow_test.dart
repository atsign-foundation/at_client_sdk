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

  test('The release job derives its own asset list from the target', () {
    final release = _workflow.substring(_workflow.indexOf('\n  release:\n'));
    expect(release, contains('case "\$TARGET" in'));
    expect(release, contains('assets=(at_client_web.js)'));
    expect(release, contains('assets=(at_client_web.wasm at_client_web.mjs)'));
    expect(release, contains('exit 1'));
    expect(_workflow, isNot(contains('needs.build.outputs.assets')));
    expect(
      RegExp(r'^      assets:', multiLine: true).hasMatch(_workflow),
      isFalse,
      reason: 'the build job exposes no asset list',
    );
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
    expect(_workflow, contains('assets+=(bridge-manifest.json SHA256SUMS)'));
    expect(_workflow, contains('sha256sum -c at_client_web.js.sha256'));
    expect(
      _workflow,
      contains('sha256sum at_client_web.js > at_client_web.js.sha256'),
    );
  });

  test('Attestation covers the same files as the checksum file', () {
    expect(
      RegExp('uses: actions/attest-build-provenance').allMatches(_workflow),
      hasLength(1),
    );
    expect(
      RegExp('uses: actions/(upload|download)-artifact').allMatches(_workflow),
      hasLength(2),
      reason: 'one upload and one download, not one per target',
    );
    expect(
        _workflow, contains(r'name: at_client_web-bridge-${{ env.TARGET }}'));
    // The attested directory is the one the verify step proved holds exactly
    // the target's assets, bridge-manifest.json and SHA256SUMS.
    final verify = _workflow.indexOf('Verify the bundle and checksums');
    final attest = _workflow.indexOf('uses: actions/attest-build-provenance');
    expect(verify, isNonNegative);
    expect(verify, lessThan(attest));
    expect(_workflow, contains('subject-path: bridge/*'));
    expect(_workflow, contains(r'expected=$(printf'));
    expect(_workflow, contains(r'"$expected" != "$found"'));
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
      greaterThanOrEqualTo(5),
    );
    expect(_workflow, contains('assets+=(at_client_web.js.sha256)'));
    expect(_workflow, contains('cp "\${assets[@]}" bridge-manifest.json'));
  });
}
