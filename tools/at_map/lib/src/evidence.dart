import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'decls.dart';
import 'source.dart';

/// The fewest fixed characters a message needs before a text match means
/// anything.
const int minFixedText = 12;

/// A string literal in a test file, and the test that holds it.
class TestLiteral {
  /// Creates a literal record.
  TestLiteral(this.path, this.test, this.line, this.text);

  /// The test file, relative to its root.
  final String path;

  /// The enclosing `test(...)` name, or the file when there is none.
  final String test;

  /// Its 1-based line.
  final int line;

  /// Its text, each interpolation replaced by U+0000.
  final String text;
}

/// Whether [path] is a test file of the at_server checkout.
bool isServerTest(String path) =>
    path.endsWith('_test.dart') &&
    (path.startsWith('tests/') || path.contains('/test/'));

/// Every string literal in [tree]'s test files.
List<TestLiteral> testLiterals(Tree tree) {
  final out = <TestLiteral>[];
  for (final path in tree.files().where(isServerTest)) {
    final text = tree.read(path);
    if (text == null) continue;
    final unit = parseUnit(text);
    unit.accept(_Literals(path, unit, out));
  }
  return out;
}

class _Literals extends RecursiveAstVisitor<void> {
  _Literals(this.path, this.unit, this.out);
  final String path;
  final CompilationUnit unit;
  final List<TestLiteral> out;

  String _testName(AstNode n) {
    for (AstNode? x = n; x != null; x = x.parent) {
      if (x is MethodInvocation &&
          (x.methodName.name == 'test' || x.methodName.name == 'testWidgets') &&
          x.argumentList.arguments.isNotEmpty) {
        final a = x.argumentList.arguments.first;
        if (a is StringLiteral && a.stringValue != null) {
          final groups = <String>[];
          for (AstNode? g = x.parent; g != null; g = g.parent) {
            if (g is MethodInvocation &&
                g.methodName.name == 'group' &&
                g.argumentList.arguments.isNotEmpty) {
              final ga = g.argumentList.arguments.first;
              if (ga is StringLiteral && ga.stringValue != null) {
                groups.insert(0, ga.stringValue!);
              }
            }
          }
          return [...groups, a.stringValue!].join(' ');
        }
      }
    }
    return path;
  }

  void _add(AstNode n, String text) => out.add(TestLiteral(path, _testName(n),
      unit.lineInfo.getLocation(n.offset).lineNumber, text));

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.parent is! AdjacentStrings) _add(node, node.value);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.parent is! AdjacentStrings) _add(node, _text(node));
    super.visitStringInterpolation(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _add(node, node.strings.map(_text).join());
    super.visitAdjacentStrings(node);
  }

  String _text(StringLiteral s) {
    if (s is SimpleStringLiteral) return s.value;
    if (s is StringInterpolation) {
      return s.elements
          .map((e) => e is InterpolationString ? e.value : '\u0000')
          .join();
    }
    if (s is AdjacentStrings) return s.strings.map(_text).join();
    return '';
  }
}

/// What the test literals say about one exit.
class Evidence {
  /// Creates an evidence record.
  Evidence(this.status, this.tests);

  /// named, none, or undecided.
  final String status;

  /// The tests whose literals hold the message's fixed text.
  final List<TestLiteral> tests;
}

/// Whether a literal holds every segment of [fixed], in order.
bool _holds(String literal, List<String> fixed) {
  var at = 0;
  for (final seg in fixed) {
    final i = literal.indexOf(seg, at);
    if (i < 0) return false;
    at = i + seg.length;
  }
  return true;
}

/// The evidence for an exit whose message alternatives have [fixedText].
Evidence evidenceFor(List<List<String>> fixedText, List<TestLiteral> literals) {
  final decidable = [
    for (final alt in fixedText)
      [
        for (final s in alt)
          if (s.trim().length >= 3) s.trim()
      ]
  ].where((alt) => alt.fold<int>(0, (n, s) => n + s.length) >= minFixedText);
  if (decidable.isEmpty) return Evidence('undecided', const []);
  final hits = <String, TestLiteral>{};
  for (final alt in decidable) {
    for (final l in literals) {
      if (_holds(l.text, alt)) {
        hits.putIfAbsent('${l.path}\u0000${l.test}', () => l);
      }
    }
  }
  final tests = hits.values.toList()
    ..sort((a, b) => '${a.path}${a.test}'.compareTo('${b.path}${b.test}'));
  return Evidence(tests.isEmpty ? 'none' : 'named', tests);
}
