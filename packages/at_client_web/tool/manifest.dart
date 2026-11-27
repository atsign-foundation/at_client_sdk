// Publishes the bridge's closed sets as one JSON manifest: the exported
// surface and the error codes a rejection
// can carry. The constants are the definition; `bridge-manifest.json` is
// this script's exact output, and `test/js/manifest_test.dart` fails when the
// committed file and the constants drift apart.
//
// Run with no arguments to write the manifest to stdout, or with
// `--out PATH` to write the same bytes to PATH atomically (PATH.tmp then a
// rename). Any other argument is refused. The script reads no environment
// variable: a release's manifest bytes must not depend on `TARGET`.

import 'dart:convert';
import 'dart:io';

import 'package:at_client_web/src/exceptions.dart' show maxErrorMessageLength;
import 'package:at_client_web/src/js/bridge_surface.dart'
    show bridgeSurface, createOptions, envelopes, statuses;
import 'package:at_client_web/src/js/error_codes.dart'
    show atErrorCodes, collectionErrorCodes;

/// The manifest format. Adding a top-level key or a list entry bumps this;
/// renaming or removing one is a breaking manifest change. It counts released
/// manifests, not commits, so later changes on this branch do not bump it
/// again until a manifest is released.
const _schemaVersion = 2;

const _usage = 'usage: dart tool/manifest.dart\n'
    '       dart tool/manifest.dart --out PATH';

void main(List<String> args) {
  String? out;
  if (args.isNotEmpty) {
    if (args[0] == '--out') {
      if (args.length != 2 || args[1].isEmpty) {
        stderr.writeln('manifest: --out needs a path');
        stderr.writeln(_usage);
        exit(1);
      }
      out = args[1];
    } else {
      stderr.writeln('manifest: unexpected argument ${args.join(' ')}');
      stderr.writeln(_usage);
      exit(1);
    }
  }

  _checkList('collectionErrorCodes', collectionErrorCodes);
  _checkList('errorCodes', atErrorCodes);
  for (final MapEntry(key: form, value: options) in createOptions.entries) {
    _checkList('createOptions[$form]', options);
  }
  for (final MapEntry(key: name, value: fields) in envelopes.entries) {
    _checkList('envelopes[$name]', fields);
  }
  _checkList('statuses', statuses);
  if (bridgeSurface.isEmpty) _fail('bridgeSurface is empty');
  for (final MapEntry(key: owner, value: members) in bridgeSurface.entries) {
    _checkList('surface[$owner]', members);
  }

  final overlap = atErrorCodes.toSet().intersection(
        collectionErrorCodes.toSet(),
      );
  if (overlap.isNotEmpty) {
    _fail(
      'errorCodes and collectionErrorCodes overlap: '
      '${(overlap.toList()..sort()).join(', ')}',
    );
  }

  final manifest = <String, Object?>{
    'bounds': {'maxErrorMessageLength': maxErrorMessageLength},
    'collectionErrorCodes': collectionErrorCodes,
    'createOptions': createOptions,
    'envelopes': envelopes,
    'errorCodes': atErrorCodes,
    'schemaVersion': _schemaVersion,
    'statuses': statuses,
    'surface': _sortedMap(bridgeSurface),
  };
  final text = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';

  if (out == null) {
    stdout.write(text);
    return;
  }
  final temp = File('$out.tmp');
  temp.writeAsStringSync(text, flush: true);
  temp.renameSync(out);
}

/// [source] with its keys sorted, so the constant's authoring order cannot
/// change the bytes. Each member list is already sorted, which `_checkList`
/// enforces, so this is the one sort the output applies.
Map<String, List<String>> _sortedMap(Map<String, List<String>> source) => {
      for (final key in source.keys.toList()..sort()) key: source[key]!,
    };

/// Exits 1 unless [name]'s values are non-empty, strictly ascending and
/// therefore duplicate-free.
void _checkList(String name, List<String> values) {
  if (values.isEmpty) _fail('$name is empty');
  for (var i = 1; i < values.length; i++) {
    final order = values[i - 1].compareTo(values[i]);
    if (order == 0) _fail('$name has a duplicate: ${values[i]}');
    if (order > 0) {
      _fail('$name is not sorted: ${values[i - 1]} then ${values[i]}');
    }
  }
}

Never _fail(String message) {
  stderr.writeln('manifest self-check failed: $message');
  exit(1);
}
