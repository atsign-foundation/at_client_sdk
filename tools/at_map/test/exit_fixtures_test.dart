/// The exit walker over fixtures of each guard shape, with what it must
/// list and what it must not.
///
/// Catalogue: features/at_map/sdk_map.feature
library;

import 'package:at_map/at_map.dart';
import 'package:at_map/src/analysis.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  final pkg = p.join(repoRoot(), 'tools/at_map');
  final fixtures = p.join(pkg, 'test/fixtures/exits');
  final file = p.join(fixtures, 'handlers.dart');
  late Resolver resolver;
  setUpAll(() {
    resolver = Resolver(
        sdkDir: pkg,
        serverDir: p.join(pkg, 'no-server'),
        sdkPackages: ['test/fixtures'],
        serverPackage: 'none');
  });

  Future<Inventory> walk(String method) async {
    final decl = await resolver.declaration(file, 'Fixture.$method');
    expect(decl, isNotNull, reason: 'the fixture declares Fixture.$method');
    return ExitWalker(resolver, fixtures).walk([decl!]);
  }

  List<String?> guards(Inventory inv) => inv.exits.map((e) => e.guard).toList();

  test('An else-branch exit carries the negated condition', () async {
    final inv = await walk('ifElse');
    expect(guards(inv), ['!(digestFromClient == expectedDigest)']);
    expect(guards(inv), isNot(contains('digestFromClient == expectedDigest')),
        reason: 'the else is not entered when the condition holds');
  });

  test('A throw caught inside the handler is not an exit', () async {
    final inv = await walk('tryCatch');
    final messages = inv.exits.expand((e) => e.messages).join('\n');
    expect(messages, isNot(contains('caught by the catch-all')));
    expect(messages, contains('not a FormatException'),
        reason: 'a throw the catch clause does not match is still an exit');
  });

  test('A construct the walker does not know marks the inventory incomplete',
      () async {
    final inv = await walk('generator');
    expect(inv.incomplete, ['Yield statement in Fixture.generator'],
        reason: 'the inventory names the construct it did not follow');
    expect(guards(inv), ['x'],
        reason: 'the exits the walker did follow are still listed');
    final known = await walk('elseIf');
    expect(known.incomplete, isEmpty,
        reason: 'a handler using only known constructs is complete');
  });

  test('A path condition over its bound is reported, not expanded', () async {
    final deep = (await walk('deep')).exits.single;
    expect(deep.guard, 'h > 0');
    expect(deep.pathNotExpanded, isTrue);
    expect(deep.branch, isEmpty);
    final shallow = (await walk('shallow')).exits.single;
    expect(shallow.pathNotExpanded, isFalse,
        reason: 'a branch within the bound is expanded');
    expect(shallow.branch, ['a > 0', 'b > 0']);
    expect(shallow.guard, 'c > 0');
  });

  test('An else-if arm carries its own guard under the negation before it',
      () async {
    final inv = await walk('elseIf');
    expect(guards(inv), ['a > 1', 'b > 1']);
    expect(inv.exits[1].branch, ['!(a > 1)']);
    expect(inv.exits[0].branch, isEmpty);
  });

  test(
      'Early returns are exits by what they write, and the final return is not',
      () async {
    final inv = await walk('earlyReturns');
    expect([for (final e in inv.exits) '${e.kind} ${e.guard}'],
        ['success x == null', 'error y', 'return x.isEmpty']);
  });

  test('Each switch case is a guard, and cases sharing a body share one',
      () async {
    final inv = await walk('switches');
    expect(guards(inv), [
      "op case 'a'",
      "op case 'b' || 'c'",
      'default of switch (op)',
    ]);
    expect(inv.exits.map((e) => e.kind), ['throw', 'throw', 'return']);
  });

  test('A throw in a catch and a rethrow are exits under their catch',
      () async {
    final inv = await walk('tryCatch');
    expect(
        inv.exits.map((e) => '${e.kind} ${e.guard}'),
        containsAll(
            ['throw on FormatException', 'rethrow on InvalidSyntaxException']));
    expect(
        inv.exits.where((e) => e.messages.contains("'from a helper'")), isEmpty,
        reason: 'the helper\'s throw is caught by the clause that rethrows '
            'it, so the rethrow is the exit');
  });

  test(
      'Helpers in the class, the file and another file are followed, other '
      'objects are not', () async {
    final inv = await walk('helpers');
    expect(inv.exits.map((e) => '${e.symbol} ${e.guard}'), [
      'Fixture._sameClass n < 0',
      'sameFile n == 7',
      'Fixture.staticHelper n > 100',
      'otherFile n == 13',
    ]);
    expect(inv.exits.last.path, endsWith('helpers.dart'));
    expect(inv.exits.map((e) => e.symbol), isNot(contains('Other.check')),
        reason: 'a method on another object is not the handler\'s helper');
  });

  test('A throw inside a closure marks the inventory incomplete', () async {
    final inv = await walk('closure');
    expect(inv.incomplete, ['throw inside a closure in Fixture.closure'],
        reason: 'an exit the walker cannot attribute is named, so the list '
            'is not read as complete');
  });
}
