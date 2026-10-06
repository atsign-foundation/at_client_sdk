import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// A put that falls back to legacy encryption goes out under a copy of its
/// [PutRequestOptions] with the provider pinned to legacy. Every other field is
/// the caller's request and travels with the copy: one the copy leaves out
/// becomes its default on exactly the writes that fell back, which is how a
/// remote `noCommit` put came to be committed. A field this package adds turns
/// the first test red until it is placed in one set or another.
void main() {
  const carried = {
    'useRemoteAtServer',
    'shouldEncrypt',
    'alreadyEncrypted',
    'noCommit',
  };
  const replaced = {'cryptoProviderId'};
  const ignored = {'storeSharedKeyEncryptedMetadata'};

  final fields = <String, Object? Function(PutRequestOptions)>{
    'useRemoteAtServer': (o) => o.useRemoteAtServer,
    'shouldEncrypt': (o) => o.shouldEncrypt,
    'alreadyEncrypted': (o) => o.alreadyEncrypted,
    'noCommit': (o) => o.noCommit,
    'cryptoProviderId': (o) => o.cryptoProviderId,
    // ignore: deprecated_member_use_from_same_package
    'storeSharedKeyEncryptedMetadata': (o) => o.storeSharedKeyEncryptedMetadata,
  };

  /// The instance fields a class body declares, in every shape a field can
  /// take: with or without a default, `late`, `final`, a generic type with
  /// commas, a default on the next line. Getters, operators, methods and
  /// statics are not fields. `declarationShapes` below pins the reach, and
  /// the operator there is `==`, whose `=` must not read as a default.
  Set<String> fieldsDeclaredIn(String body) => RegExp(
          r'^  (?!static |return )(?![^;=]*\b(?:get|operator)\s)'
          r'(?:late\s+|final\s+)*[A-Za-z_][\w<>,? ]*?\s+([a-zA-Z_]\w*)'
          r'(?:\s*=(?!=)\s*[^;]+)?;$',
          multiLine: true)
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();

  /// A class body declaring a field in every shape, beside members that are
  /// not fields.
  const declarationShapes = '''
  bool plain = false;
  String? nullable;
  Map<String, dynamic>? generic;
  late String? lateField;
  final String? finalField = null;
  Duration? splitDefault =
      const Duration(days: 8);
  int get notAField => 0;
  static const String notOne = 'x';
  bool operator ==(Object other) => true;
  Map<String, dynamic> toJson() => {};
  String toString() => 'x';
''';

  test('the parse finds a field in every shape it can be declared in', () {
    expect(
        fieldsDeclaredIn(declarationShapes),
        {
          'plain',
          'nullable',
          'generic',
          'lateField',
          'finalField',
          'splitDefault',
        },
        reason: 'a shape missing here is one a new field could hide in');
  });

  /// The instance fields `class PutRequestOptions` declares, read from its
  /// source.
  Set<String> declaredOptionFields() {
    final source =
        File('lib/src/client/request_options.dart').readAsStringSync();
    final body = RegExp(
            r'^class PutRequestOptions extends RequestOptions \{\n(.*?)^\}',
            multiLine: true,
            dotAll: true)
        .firstMatch(source)!
        .group(1)!;
    return fieldsDeclaredIn(body);
  }

  test('every PutRequestOptions field is classified exactly once', () {
    final declared = declaredOptionFields();

    expect(declared, contains('noCommit'),
        reason: 'the control: the parse finds PutRequestOptions\' own fields');
    expect(fields.keys.toSet(), declared,
        reason: 'one getter per declared field, so the test below reads them '
            'all');
    expect(carried.intersection(replaced), isEmpty);
    expect(carried.union(replaced).intersection(ignored), isEmpty);
    expect(declared, carried.union(replaced).union(ignored),
        reason: 'a field neither carried nor replaced on purpose is one the '
            'fallback silently resets');
  });

  test(
      'a legacy fallback keeps the caller\'s request and changes only the '
      'provider', () {
    final given = PutRequestOptions()
      ..useRemoteAtServer = true
      ..shouldEncrypt = false
      ..alreadyEncrypted = true
      ..noCommit = true
      ..cryptoProviderId = 'requested-provider';
    final unset = PutRequestOptions();
    for (final name in carried.union(replaced)) {
      expect(fields[name]!(given), isNot(fields[name]!(unset)),
          reason: 'the control: $name is set away from its default, so the '
              'checks below can tell carried from reset');
    }

    final copy = AtClientImpl.copyOptionsForLegacyFallback(given);

    for (final name in carried) {
      expect(fields[name]!(copy), fields[name]!(given),
          reason: '$name is the caller\'s request; falling back changes the '
              'scheme, not what was asked for');
    }
    expect(copy.cryptoProviderId, legacyCryptoProviderId);
    expect(given.cryptoProviderId, 'requested-provider',
        reason: 'the caller\'s object may be shared, and one write\'s '
            'fallback must not become every later write\'s default');
  });
}
