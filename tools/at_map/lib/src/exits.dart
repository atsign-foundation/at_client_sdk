import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

import 'analysis.dart';

/// How many enclosing conditions an exit's branch may list.
const int maxBranchConditions = 6;

/// How many characters an exit's branch may hold.
const int maxBranchCharacters = 500;

/// How deep helpers are followed from a path method.
const int maxHelperDepth = 4;

/// A point where control leaves a step's path.
class Exit {
  /// Creates an exit.
  Exit({
    required this.kind,
    required this.guard,
    required this.branch,
    required this.pathNotExpanded,
    required this.symbol,
    required this.chain,
    required this.type,
    required this.messages,
    required this.fixedText,
    required this.path,
    required this.line,
    required this.onPath,
  });

  /// throw, rethrow, return, error or success.
  final String kind;

  /// The innermost condition, negated in an else; null when unconditional.
  final String? guard;

  /// The enclosing conditions, outermost first.
  final List<String> branch;

  /// Whether [branch] was over its bound and left out.
  final bool pathNotExpanded;

  /// The method or function holding the exit.
  final String symbol;

  /// The calls from the path method to [symbol], when it is a helper.
  final List<String> chain;

  /// The thrown type.
  final String? type;

  /// The message expression, one per alternative.
  final List<String> messages;

  /// Each alternative's fixed text: its literal segments.
  final List<List<String>> fixedText;

  /// The file, absolute.
  final String path;

  /// The line, 1-based.
  final int line;

  /// Whether it is on the step's own branch path.
  final bool onPath;
}

/// Every exit found on a path, and the constructs the walker could not
/// follow.
class Inventory {
  /// Creates an inventory.
  Inventory(this.exits, this.incomplete);

  /// Exits in walk order, on and off the path.
  final List<Exit> exits;

  /// Constructs the walker does not handle; non-empty means incomplete.
  final List<String> incomplete;

  /// The exits on the step's own path.
  List<Exit> get onPath => exits.where((e) => e.onPath).toList();
}

/// `!` before [e], wrapping it in parentheses unless it is a primary.
String negate(Expression e) {
  final x = e.unParenthesized;
  if (x is PrefixExpression && x.operator.type == TokenType.BANG) {
    return x.operand.unParenthesized.toSource();
  }
  if (x is SimpleIdentifier ||
      x is PrefixedIdentifier ||
      x is PropertyAccess ||
      x is MethodInvocation ||
      x is IndexExpression ||
      x is FunctionExpressionInvocation ||
      x is BooleanLiteral) {
    return '!${x.toSource()}';
  }
  return '!(${x.toSource()})';
}

class _Try {
  _Try(this.catches);
  final List<CatchClause> catches;
}

class _Ctx {
  _Ctx({
    required this.conds,
    required this.tries,
    required this.onPath,
    required this.helper,
    required this.chain,
    required this.depth,
    required this.symbol,
    required this.path,
    required this.unit,
    required this.next,
    required this.typeSystemOwner,
  });

  final List<String> conds;
  final List<_Try> tries;
  final bool onPath;
  final bool helper;
  final List<String> chain;
  final int depth;
  final String symbol;
  final String path;
  final CompilationUnit unit;

  /// The rest of the path after this method, when walking a path method.
  final List<AstNode> next;
  final LibraryElement? typeSystemOwner;

  _Ctx copy({
    List<String>? conds,
    List<_Try>? tries,
    bool? onPath,
  }) =>
      _Ctx(
        conds: conds ?? this.conds,
        tries: tries ?? this.tries,
        onPath: onPath ?? this.onPath,
        helper: helper,
        chain: chain,
        depth: depth,
        symbol: symbol,
        path: path,
        unit: unit,
        next: next,
        typeSystemOwner: typeSystemOwner,
      );
}

/// Walks a step's path methods for its exits, following helpers within
/// [rootDir].
class ExitWalker {
  /// Creates a walker resolving helpers through [resolver].
  ExitWalker(this.resolver, this.rootDir);

  /// Resolves helpers.
  final Resolver resolver;

  /// Helpers are followed only into files under this directory.
  final String rootDir;

  final List<Exit> _exits = [];
  final Set<String> _incomplete = {};
  final Set<Element> _walking = {};

  /// The inventory of [path]: resolved declarations, entry first, anchor
  /// last.
  Future<Inventory> walk(List<AstNode> path) async {
    _exits.clear();
    _incomplete.clear();
    if (path.isEmpty) return Inventory(const [], const []);
    await _method(
        path.first,
        _ctxFor(path.first,
            conds: const [],
            tries: const [],
            onPath: true,
            helper: false,
            chain: const [],
            depth: 0,
            next: path.sublist(1)));
    return Inventory(List.of(_exits), _incomplete.toList()..sort());
  }

  _Ctx _ctxFor(AstNode decl,
      {required List<String> conds,
      required List<_Try> tries,
      required bool onPath,
      required bool helper,
      required List<String> chain,
      required int depth,
      required List<AstNode> next}) {
    final unit = decl.root as CompilationUnit;
    final el = _declared(decl);
    return _Ctx(
      conds: conds,
      tries: tries,
      onPath: onPath,
      helper: helper,
      chain: chain,
      depth: depth,
      symbol: el == null ? '?' : qualifiedName(el),
      path: el == null ? '' : (sourcePath(el) ?? ''),
      unit: unit,
      next: next,
      typeSystemOwner: unit.declaredFragment?.element,
    );
  }

  Element? _declared(AstNode decl) {
    if (decl is MethodDeclaration) return decl.declaredFragment?.element;
    if (decl is FunctionDeclaration) return decl.declaredFragment?.element;
    if (decl is ConstructorDeclaration) return decl.declaredFragment?.element;
    return null;
  }

  Future<void> _method(AstNode decl, _Ctx c) async {
    final el = _declared(decl);
    if (el != null && !_walking.add(el.baseElement)) return;
    try {
      final FunctionBody? body = decl is MethodDeclaration
          ? decl.body
          : decl is FunctionDeclaration
              ? decl.functionExpression.body
              : decl is ConstructorDeclaration
                  ? decl.body
                  : null;
      if (body is ExpressionFunctionBody) {
        await _expr(body.expression, c);
      } else if (body is BlockFunctionBody) {
        await _block(body.block, c, top: true);
      }
    } finally {
      if (el != null) _walking.remove(el.baseElement);
    }
  }

  Future<void> _block(Block b, _Ctx c, {bool top = false}) async {
    final ss = b.statements;
    var cur = c;
    for (var i = 0; i < ss.length; i++) {
      final s = ss[i];
      await _stmt(s, cur,
          finalReturn: top && i == ss.length - 1, siblings: ss, index: i);
      if (cur.helper &&
          s is IfStatement &&
          s.elseStatement == null &&
          s.caseClause == null &&
          _alwaysReturns(s.thenStatement)) {
        cur = cur.copy(conds: [...cur.conds, negate(s.expression)]);
      }
    }
  }

  /// Whether [s] ends in a return on every path, so a helper's statements
  /// after an `if` holding it run only when its condition is false.
  bool _alwaysReturns(Statement s) {
    if (s is ReturnStatement) return true;
    if (s is Block) {
      return s.statements.isNotEmpty && _alwaysReturns(s.statements.last);
    }
    return false;
  }

  bool _contains(AstNode? n, AstNode? target) {
    if (n == null || target == null) return false;
    final want = _declared(target)?.baseElement;
    if (want == null) return false;
    var found = false;
    n.accept(_CallFinder((e) {
      if (e.baseElement == want) found = true;
    }));
    return found;
  }

  /// Whether an arm is on the path: with no path method still to reach,
  /// every arm is; otherwise only the arm that reaches it.
  bool _armOnPath(_Ctx c, AstNode arm, List<AstNode> arms) {
    if (!c.onPath) return false;
    if (c.helper || c.next.isEmpty) return true;
    final target = c.next.first;
    final any = arms.any((a) => _contains(a, target));
    return !any || _contains(arm, target);
  }

  Future<void> _stmt(Statement s, _Ctx c,
      {bool finalReturn = false,
      List<Statement> siblings = const [],
      int index = 0}) async {
    if (s is Block) {
      await _block(s, c);
    } else if (s is IfStatement) {
      final cond = s.caseClause == null
          ? s.expression.toSource()
          : '${s.expression.toSource()} ${s.caseClause!.toSource()}';
      final neg = s.caseClause == null ? negate(s.expression) : '!($cond)';
      await _expr(s.expression, c);
      final arms = <AstNode>[
        s.thenStatement,
        if (s.elseStatement != null) s.elseStatement!
      ];
      await _stmt(
          s.thenStatement,
          c.copy(
              conds: [...c.conds, cond],
              onPath: _armOnPath(c, s.thenStatement, arms)));
      final e = s.elseStatement;
      if (e != null) {
        await _stmt(e,
            c.copy(conds: [...c.conds, neg], onPath: _armOnPath(c, e, arms)));
      }
    } else if (s is SwitchStatement) {
      await _expr(s.expression, c);
      final subject = s.expression.toSource();
      final pending = <String>[];
      var isDefault = false;
      for (final m in s.members) {
        if (m is SwitchDefault) {
          isDefault = true;
        } else if (m is SwitchCase) {
          pending.add(m.expression.toSource());
        } else if (m is SwitchPatternCase) {
          pending.add(m.guardedPattern.toSource());
        }
        if (m.statements.isEmpty) continue;
        final label = isDefault
            ? 'default of switch ($subject)'
            : '$subject case ${pending.join(' || ')}';
        final onPath = c.onPath &&
            (c.helper ||
                c.next.isEmpty ||
                !s.members.any((x) => _contains(x, c.next.first)) ||
                _contains(m, c.next.first));
        final inner = c.copy(conds: [...c.conds, label], onPath: onPath);
        for (var i = 0; i < m.statements.length; i++) {
          await _stmt(m.statements[i], inner, siblings: m.statements, index: i);
        }
        pending.clear();
        isDefault = false;
      }
    } else if (s is TryStatement) {
      await _block(s.body, c.copy(tries: [...c.tries, _Try(s.catchClauses)]));
      for (final cc in s.catchClauses) {
        final label = cc.exceptionType == null
            ? 'catch'
            : 'on ${cc.exceptionType!.toSource()}';
        await _block(cc.body, c.copy(conds: [...c.conds, label]));
      }
      final f = s.finallyBlock;
      if (f != null) await _block(f, c);
    } else if (s is ForStatement) {
      final parts = s.forLoopParts;
      String? cond;
      if (parts is ForEachParts) {
        await _expr(parts.iterable, c);
        final v = parts is ForEachPartsWithDeclaration
            ? parts.loopVariable.name.lexeme
            : parts is ForEachPartsWithIdentifier
                ? parts.identifier.name
                : parts is ForEachPartsWithPattern
                    ? parts.pattern.toSource()
                    : '?';
        cond = 'each $v in ${parts.iterable.toSource()}';
      } else if (parts is ForParts) {
        if (parts.condition != null) {
          await _expr(parts.condition!, c);
          cond = parts.condition!.toSource();
        }
      }
      await _stmt(s.body, cond == null ? c : c.copy(conds: [...c.conds, cond]));
    } else if (s is WhileStatement) {
      await _expr(s.condition, c);
      final cond = s.condition.toSource();
      await _stmt(
          s.body, cond == 'true' ? c : c.copy(conds: [...c.conds, cond]));
    } else if (s is DoStatement) {
      await _stmt(s.body, c);
      await _expr(s.condition, c);
    } else if (s is LabeledStatement) {
      await _stmt(s.statement, c);
    } else if (s is ReturnStatement) {
      if (s.expression != null) await _expr(s.expression!, c);
      if (c.helper || finalReturn) return;
      _record(c, s,
          kind: _returnKind(siblings, index), type: null, messages: const []);
    } else if (s is ExpressionStatement) {
      final e = s.expression;
      if (e is ThrowExpression) {
        await _expr(e.expression, c);
        _throw(c, e);
      } else if (e is RethrowExpression) {
        _rethrow(c, e);
      } else {
        await _expr(e, c);
      }
    } else if (s is VariableDeclarationStatement) {
      for (final v in s.variables.variables) {
        if (v.initializer != null) await _expr(v.initializer!, c);
      }
    } else if (s is PatternVariableDeclarationStatement) {
      await _expr(s.declaration.expression, c);
    } else if (s is BreakStatement ||
        s is ContinueStatement ||
        s is EmptyStatement ||
        s is AssertStatement ||
        s is FunctionDeclarationStatement) {
      return;
    } else {
      _incomplete.add('${_construct(s)} in ${c.symbol}');
    }
  }

  String _construct(AstNode n) {
    final name = n.runtimeType.toString().replaceAll('Impl', '');
    return name.replaceAllMapped(
        RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
  }

  String _returnKind(List<Statement> siblings, int index) {
    for (var i = index - 1; i >= 0; i--) {
      final s = siblings[i];
      if (s is! ExpressionStatement) break;
      final e = s.expression;
      final assigned = e is AssignmentExpression
          ? e.leftHandSide
          : e is CascadeExpression
              ? e.target
              : null;
      if (assigned == null) continue;
      String? field;
      Expression? target;
      if (assigned is PrefixedIdentifier) {
        field = assigned.identifier.name;
        target = assigned.prefix;
      } else if (assigned is PropertyAccess) {
        field = assigned.propertyName.name;
        target = assigned.target;
      }
      final t = target?.staticType;
      if (t is InterfaceType && t.element.name == 'Response') {
        if (field == 'data') return 'success';
        if (field == 'isError' ||
            field == 'errorMessage' ||
            field == 'errorCode') {
          return 'error';
        }
      }
    }
    return 'return';
  }

  /// Walks [e] for helper calls, the next path method, and throws nested in
  /// the expression.
  Future<void> _expr(Expression e, _Ctx c) async {
    final calls = <AstNode>[];
    final throws = <ThrowExpression>[];
    final closures = <FunctionExpression>[];
    e.accept(_ExprScan(calls, throws, closures));
    for (final f in closures) {
      final inner = <ThrowExpression>[];
      f.accept(_Throws(inner));
      if (inner.isNotEmpty) {
        _incomplete.add('throw inside a closure in ${c.symbol}');
      }
      if (!c.helper && c.next.isNotEmpty && _contains(f, c.next.first)) {
        _incomplete.add('path call inside a closure in ${c.symbol}');
      }
    }
    for (final t in throws) {
      final parent = t.parent;
      String? guard;
      if (parent is ConditionalExpression) {
        guard = identical(parent.thenExpression, t)
            ? parent.condition.toSource()
            : negate(parent.condition);
      } else if (parent is BinaryExpression &&
          parent.operator.type == TokenType.QUESTION_QUESTION &&
          identical(parent.rightOperand, t)) {
        guard = '${parent.leftOperand.toSource()} == null';
      } else if (parent is SwitchExpressionCase) {
        final sw = parent.parent as SwitchExpression;
        guard = '${sw.expression.toSource()} case '
            '${parent.guardedPattern.toSource()}';
      } else if (parent is ExpressionFunctionBody) {
        guard = null;
      } else {
        _incomplete.add('throw inside an expression in ${c.symbol}');
        continue;
      }
      _throw(guard == null ? c : c.copy(conds: [...c.conds, guard]), t);
    }
    for (final call in calls) {
      final el = _target(call);
      if (el == null) continue;
      if (c.next.isNotEmpty &&
          !c.helper &&
          el.baseElement == _declared(c.next.first)?.baseElement) {
        final next = c.next.first;
        await _method(
            next,
            _ctxFor(next,
                conds: c.conds,
                tries: c.tries,
                onPath: c.onPath,
                helper: false,
                chain: const [],
                depth: 0,
                next: c.next.sublist(1)));
        continue;
      }
      if (!_isHelperCall(call, el) || c.depth >= maxHelperDepth) continue;
      final decl = await resolver.declarationOf(el);
      if (decl == null) continue;
      await _method(
          decl,
          _ctxFor(decl,
              conds: c.conds,
              tries: c.tries,
              onPath: c.onPath,
              helper: true,
              chain: [
                ...c.chain,
                if (c.chain.isEmpty) c.symbol,
                qualifiedName(el)
              ],
              depth: c.depth + 1,
              next: const []));
    }
  }

  Element? _target(AstNode call) {
    if (call is MethodInvocation) return call.methodName.element;
    if (call is FunctionExpressionInvocation) return call.element;
    return null;
  }

  bool _isHelperCall(AstNode call, Element el) {
    if (el is! MethodElement && el is! TopLevelFunctionElement) return false;
    final path = sourcePath(el);
    if (path == null || !p.isWithin(rootDir, path)) return false;
    if (call is! MethodInvocation) return false;
    final target = call.target;
    if (target == null ||
        target is ThisExpression ||
        target is SuperExpression) {
      return true;
    }
    if (el is MethodElement && el.isStatic) return true;
    if (target is SimpleIdentifier && target.element is PrefixElement) {
      return true;
    }
    return false;
  }

  void _throw(_Ctx c, ThrowExpression t) {
    final thrown = t.expression;
    final type = thrown.staticType;
    if (_caught(c, type)) return;
    final (messages, fixed) = _message(thrown);
    _record(c, t,
        kind: 'throw',
        type: thrown is InstanceCreationExpression
            ? thrown.constructorName.type.name.lexeme
            : type?.getDisplayString(),
        messages: messages,
        fixed: fixed);
  }

  void _rethrow(_Ctx c, RethrowExpression r) {
    final clause = r.thisOrAncestorOfType<CatchClause>();
    final type = clause?.exceptionType?.type;
    final outer = clause == null
        ? c.tries
        : c.tries.where((t) => !t.catches.contains(clause)).toList();
    if (_caught(c.copy(tries: outer), type)) return;
    _record(c, r,
        kind: 'rethrow',
        type: clause?.exceptionType?.toSource(),
        messages: const []);
  }

  bool _caught(_Ctx c, DartType? type) {
    final ts = c.typeSystemOwner?.typeSystem;
    for (final t in c.tries) {
      for (final cc in t.catches) {
        final on = cc.exceptionType?.type;
        if (on == null || on.isDartCoreObject) return true;
        if (type == null || ts == null || type is DynamicType) continue;
        if (ts.isSubtypeOf(type, on)) return true;
      }
    }
    return false;
  }

  (List<String>, List<List<String>>) _message(Expression thrown) {
    if (thrown is! InstanceCreationExpression) return (const [], const []);
    final args = thrown.argumentList.arguments;
    Expression? m;
    for (final a in args) {
      if (a is NamedArgument) {
        if (a.name.lexeme == 'message') m = a.argumentExpression;
      } else {
        m ??= a.argumentExpression;
      }
    }
    if (m == null) return (const [], const []);
    final alts = <Expression>[];
    void split(Expression x) {
      final u = x.unParenthesized;
      if (u is ConditionalExpression) {
        split(u.thenExpression);
        split(u.elseExpression);
      } else {
        alts.add(u);
      }
    }

    split(m);
    return (
      [for (final a in alts) a.toSource()],
      [for (final a in alts) fixedSegments(a)]
    );
  }

  void _record(_Ctx c, AstNode at,
      {required String kind,
      required String? type,
      required List<String> messages,
      List<List<String>> fixed = const []}) {
    final all = c.conds;
    final guard = all.isEmpty ? null : all.last;
    final branch = all.isEmpty ? <String>[] : all.sublist(0, all.length - 1);
    final over = branch.length > maxBranchConditions ||
        branch.fold<int>(0, (n, s) => n + s.length) > maxBranchCharacters;
    _exits.add(Exit(
      kind: kind,
      guard: guard,
      branch: over ? const [] : branch,
      pathNotExpanded: over,
      symbol: c.symbol,
      chain: c.chain,
      type: type,
      messages: messages,
      fixedText: fixed,
      path: c.path,
      line: c.unit.lineInfo.getLocation(at.offset).lineNumber,
      onPath: c.onPath,
    ));
  }
}

/// The literal segments of a message expression; empty when none can be
/// read without running it.
List<String> fixedSegments(Expression e) {
  final x = e.unParenthesized;
  if (x is SimpleStringLiteral) return [x.value];
  if (x is AdjacentStrings) {
    return [for (final s in x.strings) ...fixedSegments(s)];
  }
  if (x is StringInterpolation) {
    return [
      for (final el in x.elements)
        if (el is InterpolationString && el.value.isNotEmpty) el.value
    ];
  }
  if (x is BinaryExpression && x.operator.type == TokenType.PLUS) {
    return [...fixedSegments(x.leftOperand), ...fixedSegments(x.rightOperand)];
  }
  Element? el;
  if (x is SimpleIdentifier) el = x.element;
  if (x is PrefixedIdentifier) el = x.element;
  if (x is PropertyAccess) el = x.propertyName.element;
  if (el is PropertyAccessorElement) el = el.variable;
  if (el is VariableElement) {
    final v = el.computeConstantValue()?.toStringValue();
    if (v != null) return [v];
  }
  return const [];
}

/// Collects calls and throws in an expression, not entering closures.
class _ExprScan extends RecursiveAstVisitor<void> {
  _ExprScan(this.calls, this.throws, this.closures);
  final List<AstNode> calls;
  final List<ThrowExpression> throws;
  final List<FunctionExpression> closures;

  @override
  void visitFunctionExpression(FunctionExpression node) => closures.add(node);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    calls.add(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    super.visitFunctionExpressionInvocation(node);
    calls.add(node);
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    super.visitThrowExpression(node);
    throws.add(node);
  }
}

/// Collects every throw under a node.
class _Throws extends RecursiveAstVisitor<void> {
  _Throws(this.out);
  final List<ThrowExpression> out;

  @override
  void visitThrowExpression(ThrowExpression node) {
    out.add(node);
    super.visitThrowExpression(node);
  }
}

/// Reports the element of every call under a node, closures included.
class _CallFinder extends RecursiveAstVisitor<void> {
  _CallFinder(this.found);
  final void Function(Element) found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final e = node.methodName.element;
    if (e != null) found(e);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final e = node.element;
    if (e != null) found(e);
    super.visitFunctionExpressionInvocation(node);
  }
}
