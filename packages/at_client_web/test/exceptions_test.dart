// Scenarios: features/at_client_web/exceptions.feature. Each test is named
// after its scenario.
@TestOn('vm')
library;

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_web/at_client_web.dart' as web;
import 'package:at_client_web/src/exceptions.dart';
import 'package:test/test.dart';

const _exceptionsFile = 'lib/src/exceptions.dart';
const _mappingFiles = {'lib/src/js/bridge.dart', 'lib/src/js/error_codes.dart'};

List<File> _libFiles() => [
      for (final e in Directory('lib').listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) e
    ];

String _path(File f) => f.path.replaceAll(r'\', '/');

/// Matches a class declaration and captures its name and the clause that
/// follows up to the body.
final _classDecl = RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+(\w+)([^{;]*)',
    multiLine: true);

final _bridgeCodes = {
  'invalid_argument',
  'enrollment_in_flight',
  'pkam_refused',
  'offline',
  // `timeout` is a code but also an ordinary field name in the package
  // (`passkey_creation_options.dart`), so the literal scan cannot own it;
  // error_codes_test pins the code.
  'onboarding_incomplete',
  'enrollment_conveyance_failed',
  'enrollment_denied',
  'closed',
  'unsupported',
  'bad_key',
  'notify_failed',
  'internal',
};

void main() {
  test(
      'every exception the package declares is declared in lib/src/exceptions.dart',
      () {
    final misplaced = <String>[];
    for (final file in _libFiles()) {
      final source = file.readAsStringSync();
      for (final m in _classDecl.allMatches(source)) {
        final name = m.group(1)!;
        final clause = m.group(2)!;
        final supers = RegExp(r'\b(?:extends|implements|with)\s+([\w\s,<>?]+)')
            .allMatches(clause)
            .expand((s) => s.group(1)!.split(','))
            .map((t) => t.trim().split(RegExp(r'[<\s]')).first);
        final isException = name.endsWith('Exception') ||
            supers.any((t) => t.endsWith('Exception') || t == 'Exception');
        if (isException && _path(file) != _exceptionsFile) {
          misplaced.add('$name in ${_path(file)}');
        }
      }
    }
    expect(misplaced, isEmpty);
  });

  test('every exception the package declares is an AtException', () {
    final declared = <Object>[
      InvalidArgumentException('x'),
      InvalidKeyException(KeyRefusal.sharedWithMissing),
      ManageAccessRequiredException(),
      NotifyFailedException(NotifyFailure.sendFailed),
      EnrollmentInFlightException(),
      SessionClosedException(),
      SessionAlreadyOpenException('@alice'),
      PortalSessionOfflineException(
          '@alice', AtConnectionState.offline(AtConnectionCause.unreachable)),
      UnsupportedKeyMaterialException('@alice'),
      UnsupportedOperationException(UnsupportedOperation.secureContext),
      SetupLockTimeoutException('lock'),
      IndexedDbException('QuotaExceededError'),
      JsCollectionsError(CollectionFailure.failed),
    ];
    final source = File(_exceptionsFile).readAsStringSync();
    final classes = {
      for (final m in _classDecl.allMatches(source)) m.group(1)!
    };
    expect(classes, hasLength(declared.length));
    for (final error in declared) {
      var caught = false;
      try {
        throw error;
      } on AtException {
        caught = true;
      }
      expect(caught, isTrue, reason: '${error.runtimeType}');
    }
  });

  test('the exceptions file reaches no web-only API', () {
    final seen = <String>{};
    void visit(String path) {
      if (!seen.add(path)) return;
      final source = File(path).readAsStringSync();
      final imports =
          RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true)
              .allMatches(source)
              .map((m) => m.group(1)!);
      for (final uri in imports) {
        expect(uri, isNot(startsWith('dart:js_interop')), reason: path);
        expect(uri, isNot('dart:html'), reason: path);
        expect(uri, isNot(startsWith('package:web/')), reason: path);
        if (uri.startsWith('package:')) continue;
        expect(
            uri, isNot(matches(RegExp(r'(^|/)(js|session|collections|keys)/'))),
            reason: path);
        if (!uri.startsWith('dart:')) {
          visit(File(path).parent.uri.resolve(uri).toFilePath());
        }
      }
    }

    visit(_exceptionsFile);
  });

  test('the barrels export every exception they exported before', () {
    final base = File('lib/at_client_web.dart').readAsStringSync();
    for (final name in [
      'PortalSessionOfflineException',
      'UnsupportedKeyMaterialException'
    ]) {
      expect(base, contains(name));
    }
    final browser = File('lib/at_client_web_web.dart').readAsStringSync();
    for (final name in [
      'SetupLockTimeoutException',
      'IndexedDbException',
      'PasskeyCeremonyException',
      'PasskeyRecordAuthenticationException',
      'PrfUnavailableException',
      'UnsupportedPasskeyRecordException',
      'AtServerAtKeysLockedException',
      'AtServerAtKeysWriteException',
      'MissingAtKeysDocumentException',
      'PasskeyLostException',
      'PasskeyOnboardingIncompleteException',
      'PkamRefusedException',
      'PublicKeyMismatchException',
    ]) {
      expect(browser, contains(name));
    }
    // The trunk name resolves through the base barrel alone.
    expect(web.PortalSessionOfflineException, isNotNull);
    expect(web.UnsupportedKeyMaterialException, isNotNull);
  });

  test('only the bridge and its code mapping name an error code', () {
    for (final file in _libFiles()) {
      final path = _path(file);
      if (_mappingFiles.contains(path)) continue;
      final source = file.readAsStringSync();
      for (final m in RegExp(r'''(['"])([^'"\n]*)\1''').allMatches(source)) {
        final literal = m.group(2)!;
        expect(_bridgeCodes, isNot(contains(literal)),
            reason: '$path holds "$literal"');
        expect(literal, isNot(startsWith('COLLECTION_')), reason: path);
      }
      if (path.startsWith('lib/src/collections/') ||
          path.startsWith('lib/src/session/')) {
        expect(source, isNot(contains('js/bridge.dart')), reason: path);
        expect(source, isNot(contains('error_codes.dart')), reason: path);
      }
    }
  });

  test(
      'an item id on an exception is folded to lower case once, where it is built',
      () {
    expect(InvalidArgumentException('x', id: 'ItEm-A').id, 'item-a');
    expect(JsCollectionsError(CollectionFailure.notFound, id: 'ItEm-A').id,
        'item-a');
    expect(InvalidArgumentException('x').id, isNull);
    expect(foldItemId('ItEm-A'), 'item-a');
  });

  test('the closed message and the message bound have one owner', () {
    expect(SessionClosedException().message, sessionClosedMessage);
    expect(maxErrorMessageLength, 128);
  });

  test('the offline exception keeps the state error in its text', () {
    final withError = PortalSessionOfflineException(
        '@alice',
        AtConnectionState.offline(AtConnectionCause.unreachable,
            error: StateError('sentinel-detail')));
    expect(withError.toString(), endsWith(': Bad state: sentinel-detail'),
        reason: 'the state error follows the cause, as it did on trunk');

    final withoutError = PortalSessionOfflineException(
        '@alice', AtConnectionState.offline(AtConnectionCause.unreachable));
    expect(withoutError.toString(), isNot(contains('sentinel')));
    expect(
        withoutError.toString(),
        'PortalSessionOfflineException: @alice did not come online '
        '(unreachable)');
  });
}
