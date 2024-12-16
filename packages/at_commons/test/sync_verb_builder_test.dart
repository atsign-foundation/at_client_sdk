import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';

void main() {
  test('build sync verb command with defaults values', () {
    var syncVerbBuilder = SyncVerbBuilder()..commitId = -1;
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:-1:limit:25\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });

  test('build sync verb command with regex', () {
    var syncVerbBuilder = SyncVerbBuilder()
      ..regex = '.buzz'
      ..commitId = -1;
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:-1:limit:25:.buzz\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });

  test('build sync verb command with commitId and regex', () {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = 3
      ..regex = '.buzz';
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:3:limit:25:.buzz\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });

  test('build sync stream verb command with regex', () {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = 3
      ..regex = '.buzz'
      ..isPaginated = true
      ..limit = 10;
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:3:limit:10:.buzz\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });

  test('build sync stream verb command', () {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = 3
      ..isPaginated = true
      ..limit = 10;
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:3:limit:10\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });

  test('build sync stream verb command', () {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = -1
      ..isPaginated = true
      ..limit = 5;
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:-1:limit:5\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });

  test('build sync stream verb command with skipDeletes', () {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = -1
      ..isPaginated = true
      ..limit = 5
      ..skipDeletesUntil = 20;
    var command = syncVerbBuilder.buildCommand();
    expect(command, 'sync:from:-1:limit:5:skipDeletesUntil:20\n');
    var regex = RegExp(VerbSyntax.syncFrom);
    command = command.replaceAll('\n', '');
    assert(regex.hasMatch(command));
  });
}
