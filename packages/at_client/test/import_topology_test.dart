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
}
