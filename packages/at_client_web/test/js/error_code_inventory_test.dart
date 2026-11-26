// The source-scanning half of the error-code inventory: it reads Dart source
// with `dart:io`, so it runs on the VM only. The table itself and the
// table-driven mapping test live in `error_code_inventory.dart` and
// `error_codes_test.dart`, which both run under the browser too.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'error_code_inventory.dart';

/// The exception modules on a bridge path: this package's own file, then the
/// at_commons, at_client, at_auth and at_lookup modules that declare the
/// exceptions a session or its client hands the bridge. A class added to any
/// of them that is an exception must be added to [exceptionInventory], which
/// pins its code; one that is not fails both tests below.
const _exceptionSources = [
  'lib/src/exceptions.dart',
  '../at_commons/lib/src/exception/at_exceptions.dart',
  '../at_commons/lib/src/exception/at_client_exceptions.dart',
  '../at_commons/lib/src/exception/at_server_exceptions.dart',
  '../at_commons/lib/src/exception/stopped_exception.dart',
  '../at_client/lib/src/lifecycle/at_connection.dart',
  '../at_client/lib/src/lifecycle/pending_enrollment.dart',
  '../at_client/lib/src/storage/at_client_storage.dart',
  '../at_client/lib/src/enroll/enrollment_conveyance.dart',
  '../at_client/lib/src/passkey/at_server_at_keys_io.dart',
  '../at_client/lib/src/passkey/passkey_custody.dart',
  '../at_auth/lib/src/exception/at_auth_exceptions.dart',
  '../at_auth/lib/src/passkey/passkey_port.dart',
  '../at_auth/lib/src/passkey/prf_support.dart',
  '../at_auth/lib/src/passkey/passkey_record.dart',
  '../at_auth/lib/src/keys/io/at_keys_unusable.dart',
  '../at_auth/lib/src/keys/serialization/assurance.dart',
  '../at_lookup/lib/src/exception/at_lookup_exception.dart',
];

/// A class declaration and the rest of its header, so an exception is told
/// from the other classes a module declares.
final _classDeclaration = RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+(\w+)([^\n]*)',
    multiLine: true);

final _extendsException = RegExp(r'\bextends\s+[\w.]*(?:Exception|Error)\b');
final _implementsException =
    RegExp(r'\bimplements\s+[^\n{]*\b(?:Exception|Error)\b');

/// Every exception class the [paths] declare, by name.
Set<String> _declaredExceptions(Iterable<String> paths) => {
      for (final path in paths)
        for (final m
            in _classDeclaration.allMatches(File(path).readAsStringSync()))
          if (!m.group(1)!.startsWith('_') &&
              (_extendsException.hasMatch(m.group(2)!) ||
                  _implementsException.hasMatch(m.group(2)!)))
            m.group(1)!,
    };

void main() {
  test('every exception the package declares is in the inventory', () {
    final declared = _declaredExceptions(const ['lib/src/exceptions.dart']);
    expect(declared.difference(inventoryTypes), isEmpty,
        reason: 'every declared exception needs an inventory instance');
  });

  test('every exception a dependency module declares is in the inventory', () {
    final declared = _declaredExceptions(_exceptionSources);
    expect(declared.difference(inventoryTypes), isEmpty,
        reason: 'every reachable third-party exception needs a code in the '
            'inventory; add the type and the code it maps to');
  });
}
