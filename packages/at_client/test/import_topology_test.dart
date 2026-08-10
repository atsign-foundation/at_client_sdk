import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The public barrels are export surface only: no file under `lib/src` may
/// import them. A src file importing a barrel creates an import cycle with
/// everything the barrel exports (the barrel exports the impl layer, the
/// impl layer imports the subsystems), which is what kept the PQ subsystem
/// entangled with the whole package. The sweep that established this
/// invariant is `docs/projects/pq/decisions.md` section 61; a violation here
/// is a new barrel import, and the fix is a concrete
/// `package:at_client/src/...` import of what the file actually uses.
void main() {
  test('no file under lib/src imports a public barrel', () {
    final barrels = {
      p.canonicalize('lib/at_client.dart'),
      p.canonicalize('lib/at_client_mixins.dart'),
    };
    final directive =
        RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
    final violations = <String>[];

    final files = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    var checked = 0;
    for (final file in files) {
      checked++;
      for (final m in directive.allMatches(file.readAsStringSync())) {
        final uri = m.group(1)!;
        String? resolved;
        if (uri.startsWith('package:at_client/')) {
          resolved = p.canonicalize(
              p.join('lib', uri.substring('package:at_client/'.length)));
        } else if (!uri.contains(':')) {
          resolved = p.canonicalize(p.join(p.dirname(file.path), uri));
        }
        if (resolved != null && barrels.contains(resolved)) {
          violations.add('${file.path} -> $uri');
        }
      }
    }

    expect(checked, greaterThan(100),
        reason: 'the walk must actually reach lib/src');
    expect(violations, isEmpty,
        reason: 'lib/src files must import concrete src files, '
            'never a public barrel');
  });

  test('the enrollment service cannot reach the client impl', () {
    // AtClientImpl constructs and calls EnrollmentServiceImpl; the reverse
    // reach — the service impl's import closure containing the client impl —
    // is the AtClientImpl↔EnrollmentServiceImpl cycle the bootstrap work
    // cut. The edges that used to close it were incidental: a dartdoc-only
    // import in at_client_preference, and a deprecated ignored
    // AtClientManager parameter on NotificationServiceImpl.create.
    final closure = _importClosure('lib/src/service/enrollment_service_impl.dart');
    expect(closure, isNot(contains(p.canonicalize('lib/src/client/at_client_impl.dart'))),
        reason: 'the impl may depend on the service, never the reverse');
    expect(closure, isNot(contains(p.canonicalize('lib/src/manager/at_client_manager.dart'))),
        reason: 'the manager constructs clients; nothing below it may '
            'import it back');
    // A positive control: the closure walk must actually walk.
    expect(closure, contains(p.canonicalize('lib/src/crypto/crypto.dart')));
  });

  test('the secret-sharing substrate cannot reach the enrollment service', () {
    // The service layer composes the substrate (the conveyance seals through
    // it); the substrate reaching back up — the old self-wired privilege
    // gate constructing EnrollmentServiceImpl — was the cycle the injected
    // privilege resolver cut.
    final closure =
        _importClosure('lib/src/secret_sharing/at_client_secret_sharing.dart');
    expect(
        closure,
        isNot(
            contains(p.canonicalize('lib/src/service/enrollment_service_impl.dart'))),
        reason: 'privilege resolution reaches the substrate by injection, '
            'never by the substrate importing the service layer');
    // A positive control: the closure walk must actually walk.
    expect(closure,
        contains(p.canonicalize('lib/src/secret_sharing/pairwise_secret_sharing.dart')));
  });
}

/// Canonicalized transitive at_client-internal import closure of [root].
///
/// Follows relative directives as well as `package:at_client/` ones — a
/// forbidden edge spelled `import '../client/at_client_impl.dart'` is the
/// same edge, and a walker blind to it would guard only one spelling.
Set<String> _importClosure(String root) {
  final directive = RegExp(
      r'''^\s*(?:import|export)\s+['"](package:at_client/|(?!package:|dart:))([^'"]+)['"]''',
      multiLine: true);
  final seen = <String>{};
  final stack = [p.canonicalize(root)];
  while (stack.isNotEmpty) {
    final file = stack.removeLast();
    if (!seen.add(file)) continue;
    final f = File(file);
    if (!f.existsSync()) continue;
    for (final m in directive.allMatches(f.readAsStringSync())) {
      final target = m.group(1) == 'package:at_client/'
          ? p.join('lib', m.group(2)!)
          : p.join(p.dirname(file), m.group(2)!);
      stack.add(p.canonicalize(target));
    }
  }
  return seen;
}
