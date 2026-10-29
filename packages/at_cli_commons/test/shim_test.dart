import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('at_cli_commons re-exports at_client_cli and nothing else', () {
    final barrel = File('lib/at_cli_commons.dart').readAsStringSync();
    final exports = RegExp(r"^export '([^']+)'", multiLine: true)
        .allMatches(barrel)
        .map((m) => m[1])
        .toList();

    expect(exports, ['package:at_client_cli/at_client_cli.dart']);
    expect(barrel,
        contains("@Deprecated('Use package:at_client_cli/at_client_cli.dart')"),
        reason: 'the library is marked deprecated, naming where to go; the '
            'analyzer flags no import of it, so the README says so');
  });
}
