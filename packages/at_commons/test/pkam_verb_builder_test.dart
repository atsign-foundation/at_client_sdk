import 'package:at_commons/src/verb/pkam_verb_builder.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to validate pkam verb builder', () {
    test('check pkam verb command when signed challenge is set', () {
      var signature = 'abc123';
      var pkamVerbBuilder = PkamVerbBuilder()..signature = signature;
      expect(pkamVerbBuilder.checkParams(), true);
      expect(pkamVerbBuilder.buildCommand(), 'pkam:abc123\n');
    });
    test(
        'check pkam verb command when signed challenge and enrollment id are set',
        () {
      var signature = 'abc123';
      var pkamVerbBuilder = PkamVerbBuilder()
        ..signature = signature
        ..enrollmentlId = '123';
      expect(pkamVerbBuilder.checkParams(), true);
      expect(pkamVerbBuilder.buildCommand(), 'pkam:enrollmentId:123:abc123\n');
    });
    test(
        'the atSign\'s own credential authenticates with no enrollment id on '
        'the wire', () {
      // Raw literals: a released atServer knows the credential only by the
      // absence of an id and refuses `enrollmentId:primary`.
      final bare = PkamVerbBuilder()
        ..signature = 'abc123'
        ..enrollmentlId = 'primary';
      expect(bare.buildCommand(), 'pkam:abc123\n');
      final withAlgos = PkamVerbBuilder()
        ..signature = 'abc123'
        ..signingAlgo = 'rsa2048'
        ..hashingAlgo = 'sha256'
        ..enrollmentlId = 'primary';
      expect(withAlgos.buildCommand(),
          'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:abc123\n');
    });

    test(
        'check pkam verb command when signed challenge and signing/hashing algo are set',
        () {
      var signature = 'abc123';
      var pkamVerbBuilder = PkamVerbBuilder()
        ..signature = signature
        ..signingAlgo = 'rsa2048'
        ..hashingAlgo = 'sha256';
      expect(pkamVerbBuilder.checkParams(), true);
      expect(pkamVerbBuilder.buildCommand(),
          'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:abc123\n');
    });

    test(
        'check pkam verb command when enrollment Id, signed challenge and signing/hashing algo are set',
        () {
      var signature = 'abc123';
      var pkamVerbBuilder = PkamVerbBuilder()
        ..enrollmentlId = '123'
        ..signature = signature
        ..signingAlgo = 'rsa2048'
        ..hashingAlgo = 'sha256';
      expect(pkamVerbBuilder.checkParams(), true);
      expect(pkamVerbBuilder.buildCommand(),
          'pkam:signingAlgo:rsa2048:hashingAlgo:sha256:enrollmentId:123:abc123\n');
    });
  });
}
