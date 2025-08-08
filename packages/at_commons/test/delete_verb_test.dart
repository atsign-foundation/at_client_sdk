import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group tests to validate delete verb builder', () {
    test('test to verify deletion command for a local key', () {
      var deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey.isLocal = true
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@bob';

      expect(deleteVerbBuilder.buildCommand(), 'delete:local:phone@bob\n');
    });

    test('test to deletion of shared key', () {
      var deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@bob'
        ..atKey.sharedWith = '@alice';

      expect(deleteVerbBuilder.buildCommand(), 'delete:@alice:phone@bob\n');
    });

    test('test to deletion of public key', () {
      var deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey.metadata.isPublic = true
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@bob';

      expect(deleteVerbBuilder.buildCommand(), 'delete:public:phone@bob\n');
    });

    test('test buildCommand with the force flag', () {
      var deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey.metadata.isPublic = true
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@bob'
        ..force = true;

      expect(
          deleteVerbBuilder.buildCommand(), 'delete:force:public:phone@bob\n');
    });

    test('test getBuilder with the force flag on a public key', () {
      String command = 'delete:force:public:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test('test getBuilder with the force flag on a self key without sharedWith',
        () {
      String command = 'delete:force:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test('test getBuilder with the force flag on a self key with sharedWith',
        () {
      String command = 'delete:force:@bob:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test('test getBuilder with the force flag on a shared key', () {
      String command = 'delete:force:@alice:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test('test getBuilder without the force flag on a public key', () {
      String command = 'delete:public:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test(
        'test getBuilder without the force flag on a self key without sharedWith',
        () {
      String command = 'delete:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test('test getBuilder without the force flag on a self key with sharedWith',
        () {
      String command = 'delete:@bob:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
    test('test getBuilder without the force flag on a shared key', () {
      String command = 'delete:@alice:phone.wavi@bob\n';
      var deleteVerbBuilder = DeleteVerbBuilder.getBuilder(command.trim());
      expect(deleteVerbBuilder.buildCommand(), command);
    });
  });

  group('A group of tests to validate the exceptions', () {
    test('test to verify cached local key throws invalid atkey exception', () {
      expect(
          () => DeleteVerbBuilder()
            ..atKey.metadata.isCached = true
            ..atKey.isLocal = true
            ..atKey.sharedWith = '@alice'
            ..atKey.key = 'phone'
            ..atKey.sharedBy = '@bob',
          throwsA(predicate((dynamic e) => e is InvalidAtKeyException)));
    });

    test(
        'test to verify isPublic set to true with sharedWith populated throws invalid atkey exception',
        () {
      expect(
          () => DeleteVerbBuilder()
            ..atKey.metadata.isPublic = true
            ..atKey.sharedWith = '@alice',
          throwsA(predicate((dynamic e) =>
              e is InvalidAtKeyException &&
              e.message ==
                  'isLocal or isPublic cannot be true when sharedWith is set')));
    });

    test('test to verify Key cannot be null or empty', () {
      var deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey.sharedWith = '@alice'
        ..atKey.key = ''
        ..atKey.sharedBy = '@bob';

      expect(
          () => deleteVerbBuilder.buildCommand(),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtKeyException &&
              e.message == 'Key cannot be null or empty')));
    });
  });
}
