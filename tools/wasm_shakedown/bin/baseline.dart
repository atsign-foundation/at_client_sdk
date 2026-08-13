/// Prints the `expectedOffenders` / `expectedBlocked` literals for one or more
/// barrels, ready to paste into a package's `test/wasm/dep_tree_test.dart`.
///
/// Every phase of the neutrality work shrinks a baseline, and a baseline
/// transcribed by hand is a baseline that can disagree with what the walk
/// actually found. Regenerate instead:
///
/// ```
/// dart run wasm_shakedown:baseline package:at_client/at_client.dart
/// dart run wasm_shakedown:baseline package:at_utils/at_utils.dart \
///     package:at_utils/at_logger.dart
/// ```
///
/// Run it from anywhere in the workspace; package resolution comes from the
/// nearest `.dart_tool/package_config.json`, so `dart pub get` must have run.
///
/// The owning package is taken from each `package:` URI. Pass `--io` to walk
/// with native semantics instead of web — useful for the inverse half of a
/// seam, where the assertion is that a native-only barrel really does still
/// carry the platform code it claims.
library;

import 'dart:io';

import 'package:wasm_shakedown/wasm_shakedown.dart';

void main(List<String> args) {
  final io = args.contains('--io');
  final barrels = args.where((a) => !a.startsWith('--')).toList();

  if (barrels.isEmpty) {
    stderr.writeln('usage: dart run wasm_shakedown:baseline [--io] '
        '<package-uri> [<package-uri>...]');
    exitCode = 64; // EX_USAGE
    return;
  }

  for (final barrel in barrels) {
    if (!barrel.startsWith('package:')) {
      stderr.writeln('$barrel is not a package: URI — the owning package '
          'cannot be determined without one');
      exitCode = 64;
      return;
    }
    final owner = barrel.substring('package:'.length).split('/').first;
    final result =
        shakedown(barrel, environment: io ? ioEnvironment : webEnvironment);

    print('// $barrel  (${io ? 'io' : 'web'} resolution, '
        '${result.filesWalked} files walked)');
    stdout.write(result.baselineLiteral(owner));
    if (result.missingFiles.isNotEmpty) {
      print('// WARNING imported but not found:');
      for (final missing in result.missingFiles) {
        print('//   $missing');
      }
    }
    print('');
  }
}
