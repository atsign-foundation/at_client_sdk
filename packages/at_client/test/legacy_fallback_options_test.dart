import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/request_options.dart'
    show useRemoteAtServerIfSet;
import 'package:test/test.dart';

import 'test_utils/declared_fields.dart';

/// A put that falls back to legacy encryption goes out under a copy of its
/// [PutRequestOptions] with the provider pinned to legacy. Every other field is
/// the caller's request and travels with the copy: one the copy leaves out
/// becomes its default on exactly the writes that fell back, which is how a
/// remote `noCommit` put came to be committed. The namespace key a share was
/// to be sealed to is dropped, since legacy encryption seals to none. A field
/// this package adds turns the first test red until it is placed in one set
/// or another.
void main() {
  const carried = {
    '_useRemoteAtServer',
    'shouldEncrypt',
    'alreadyEncrypted',
    'noCommit',
  };
  const replaced = {'cryptoProviderId', 'sealToNamespace'};
  const ignored = <String>{};

  final fields = <String, Object? Function(PutRequestOptions)>{
    '_useRemoteAtServer': useRemoteAtServerIfSet,
    'shouldEncrypt': (o) => o.shouldEncrypt,
    'alreadyEncrypted': (o) => o.alreadyEncrypted,
    'noCommit': (o) => o.noCommit,
    'cryptoProviderId': (o) => o.cryptoProviderId,
    'sealToNamespace': (o) => o.sealToNamespace,
  };

  /// The instance fields `class PutRequestOptions` declares or inherits from
  /// `RequestOptions`, read from their source.
  Set<String> declaredOptionFields() {
    final source =
        File('lib/src/client/request_options.dart').readAsStringSync();
    String bodyOf(String declaration) =>
        RegExp('^${RegExp.escape(declaration)} \\{\\n(.*?)^\\}',
                multiLine: true, dotAll: true)
            .firstMatch(source)!
            .group(1)!;
    return {
      ...fieldsDeclaredIn(bodyOf('abstract class RequestOptions')),
      ...fieldsDeclaredIn(
          bodyOf('class PutRequestOptions extends RequestOptions')),
    };
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
      'provider and the namespace key to seal to', () {
    final given = PutRequestOptions()
      ..useRemoteAtServer = true
      ..shouldEncrypt = false
      ..alreadyEncrypted = true
      ..noCommit = true
      ..cryptoProviderId = 'requested-provider'
      ..sealToNamespace = 'todos.demos';
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
    expect(copy.sealToNamespace, isNull,
        reason: 'legacy encryption seals to no namespace key');
    expect(given.cryptoProviderId, 'requested-provider',
        reason: 'the caller\'s object may be shared, and one write\'s '
            'fallback must not become every later write\'s default');
  });

  test(
      'a legacy fallback of options that leave useRemoteAtServer unset leaves '
      'it unset, so the copy still follows remoteLocalPref', () {
    final given = PutRequestOptions();
    expect(useRemoteAtServerIfSet(given), isNull,
        reason: 'the control: it was never set');

    final copy = AtClientImpl.copyOptionsForLegacyFallback(given);

    expect(useRemoteAtServerIfSet(copy), isNull,
        reason: 'copying the getter\'s false would pin the fallback write '
            'local under remoteOnly');
  });
}
