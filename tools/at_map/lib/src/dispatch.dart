import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

import 'analysis.dart';

/// One at_commons whose `VerbSyntax` a sample is parsed with.
class CommonsVersion {
  /// Creates a version record.
  CommonsVersion(this.version, this.where, this.syntaxOf);

  /// The package version.
  final String version;

  /// Where it comes from: at_server's lock, or this checkout.
  final String where;

  /// The `VerbSyntax` constant named [field], or null when absent.
  final Future<String?> Function(String field) syntaxOf;

  @override
  String toString() => 'at_commons $version ($where)';
}

/// A handler in the atServer's dispatch order.
class Handler {
  /// Creates a handler record.
  Handler(this.element, this.accept, this.syntaxField);

  /// The handler class.
  final InterfaceElement element;

  /// Its `accept` method.
  final MethodDeclaration? accept;

  /// The `VerbSyntax` field its verb parses with.
  final String? syntaxField;

  /// The class name.
  String get name => element.name ?? '?';
}

/// What replaying a sample found under one at_commons version.
class Replay {
  /// Creates a replay record.
  Replay(this.commons, this.handler, this.syntaxField, this.parses, this.error);

  /// The at_commons version.
  final CommonsVersion commons;

  /// The handler dispatch chose, or null when none accepts it.
  final String? handler;

  /// The `VerbSyntax` field of that handler's verb.
  final String? syntaxField;

  /// Whether that syntax accepts the sample.
  final bool parses;

  /// Why the replay could not be made.
  final String? error;
}

/// The atServer's verb dispatch, read from `_loadVerbHandlers` at the pinned
/// SHA.
class Dispatch {
  Dispatch._(this.handlers, this._functions);

  /// Handlers in the order dispatch offers each command to them.
  final List<Handler> handlers;

  final Map<Element, FunctionDeclaration> _functions;

  /// Reads the dispatch table through [resolver].
  static Future<Dispatch> load(Resolver resolver) async {
    final path = p.join(resolver.serverDir, resolver.serverPackage,
        'lib/src/verb/manager/verb_handler_manager.dart');
    final decl = await resolver.declaration(
        path, 'DefaultVerbHandlerManager._loadVerbHandlers');
    final handlers = <Handler>[];
    final functions = <Element, FunctionDeclaration>{};
    if (decl == null) return Dispatch._(handlers, functions);
    final creations = <InstanceCreationExpression>[];
    decl.accept(_Creations(creations));
    for (final c in creations) {
      final cls = c.constructorName.type.element;
      if (cls is! InterfaceElement) continue;
      if (!cls.allSupertypes.any((s) => s.element.name == 'VerbHandler')) {
        continue;
      }
      final acceptEl = cls.lookUpMethod(name: 'accept', library: cls.library);
      final acceptDecl =
          acceptEl == null ? null : await resolver.declarationOf(acceptEl);
      if (acceptDecl != null) {
        final called = <Element>[];
        acceptDecl.accept(_TopLevelCalls(called));
        for (final f in called) {
          if (functions.containsKey(f)) continue;
          final fd = await resolver.declarationOf(f);
          if (fd is FunctionDeclaration) functions[f] = fd;
        }
      }
      handlers.add(Handler(
          cls,
          acceptDecl is MethodDeclaration ? acceptDecl : null,
          await _syntaxField(resolver, cls)));
    }
    return Dispatch._(handlers, functions);
  }

  /// Replays [sample] under each of [versions].
  Future<List<Replay>> replay(
      String sample, List<CommonsVersion> versions) async {
    String? chosen;
    String? field;
    String? error;
    for (final h in handlers) {
      final a = h.accept;
      if (a == null) {
        error = 'cannot read ${h.name}.accept';
        break;
      }
      try {
        if (_Eval(_functions).accept(a, sample)) {
          chosen = h.name;
          field = h.syntaxField;
          break;
        }
      } on _CannotEval catch (e) {
        error = 'cannot replay ${h.name}.accept: ${e.source}';
        break;
      }
    }
    final out = <Replay>[];
    for (final v in versions) {
      var parses = false;
      String? err = error;
      if (chosen != null && field != null && err == null) {
        final syntax = await v.syntaxOf(field);
        if (syntax == null) {
          err = 'VerbSyntax.$field is not in $v';
        } else {
          parses = RegExp(syntax, caseSensitive: false)
              .allMatches(sample)
              .isNotEmpty;
        }
      }
      out.add(Replay(v, chosen, field, parses, err));
    }
    return out;
  }
}

Future<String?> _syntaxField(Resolver resolver, InterfaceElement cls) async {
  final gv = cls.lookUpMethod(name: 'getVerb', library: cls.library);
  if (gv == null) return null;
  final gvDecl = await resolver.declarationOf(gv);
  final returned = gvDecl == null ? null : _returned(gvDecl);
  final t = returned?.staticType;
  if (t is! InterfaceType) return null;
  final syntax =
      t.element.lookUpMethod(name: 'syntax', library: t.element.library) ??
          t.element.allSupertypes
              .map((s) => s.element
                  .lookUpMethod(name: 'syntax', library: s.element.library))
              .whereType<MethodElement>()
              .firstOrNull;
  if (syntax == null) return null;
  final sDecl = await resolver.declarationOf(syntax);
  final r = sDecl == null ? null : _returned(sDecl);
  if (r is PrefixedIdentifier && r.prefix.name == 'VerbSyntax') {
    return r.identifier.name;
  }
  return null;
}

Expression? _returned(AstNode decl) {
  final body = decl is MethodDeclaration ? decl.body : null;
  if (body is ExpressionFunctionBody) return body.expression;
  if (body is BlockFunctionBody) {
    for (final s in body.block.statements) {
      if (s is ReturnStatement) return s.expression;
    }
  }
  return null;
}

class _Creations extends RecursiveAstVisitor<void> {
  _Creations(this.out);
  final List<InstanceCreationExpression> out;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    out.add(node);
    super.visitInstanceCreationExpression(node);
  }
}

class _CannotEval implements Exception {
  _CannotEval(this.source);
  final String source;
}

class _EnumValue {
  _EnumValue(this.type, this.name);
  final String type;
  final String name;
  @override
  String toString() => '$type.$name';
}

/// Evaluates the small subset of Dart that `accept` methods use.
class _Eval {
  _Eval(this._functions);
  final Map<Element, FunctionDeclaration> _functions;
  int _depth = 0;

  bool accept(MethodDeclaration m, String command) {
    final params = m.parameters?.parameters ?? const [];
    if (params.isEmpty) throw _CannotEval(m.toSource());
    final name = params.first.name!.lexeme;
    final v = _eval(_body(m.body, m), {name: command});
    if (v is! bool) throw _CannotEval(m.body.toSource());
    return v;
  }

  Expression _body(FunctionBody body, AstNode at) {
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody &&
        body.block.statements.length == 1 &&
        body.block.statements.single is ReturnStatement) {
      final e = (body.block.statements.single as ReturnStatement).expression;
      if (e != null) return e;
    }
    throw _CannotEval(at.toSource());
  }

  Object? _eval(Expression e, Map<String, Object?> env) {
    if (++_depth > 200) throw _CannotEval(e.toSource());
    try {
      return _evalInner(e, env);
    } finally {
      _depth--;
    }
  }

  Object? _evalInner(Expression e, Map<String, Object?> env) {
    if (e is ParenthesizedExpression) return _eval(e.expression, env);
    if (e is SimpleStringLiteral) return e.value;
    if (e is BooleanLiteral) return e.value;
    if (e is AdjacentStrings) {
      return [for (final s in e.strings) _str(_eval(s, env), s)].join();
    }
    if (e is StringInterpolation) {
      final b = StringBuffer();
      for (final el in e.elements) {
        if (el is InterpolationString) {
          b.write(el.value);
        } else if (el is InterpolationExpression) {
          final v = _eval(el.expression, env);
          b.write(v is _EnumValue ? v.toString() : _str(v, el.expression));
        }
      }
      return b.toString();
    }
    if (e is PrefixExpression && e.operator.type == TokenType.BANG) {
      return !_bool(_eval(e.operand, env), e);
    }
    if (e is BinaryExpression) {
      final op = e.operator.type;
      if (op == TokenType.AMPERSAND_AMPERSAND) {
        return _bool(_eval(e.leftOperand, env), e) &&
            _bool(_eval(e.rightOperand, env), e);
      }
      if (op == TokenType.BAR_BAR) {
        return _bool(_eval(e.leftOperand, env), e) ||
            _bool(_eval(e.rightOperand, env), e);
      }
      if (op == TokenType.EQ_EQ || op == TokenType.BANG_EQ) {
        final l = _eval(e.leftOperand, env);
        final r = _eval(e.rightOperand, env);
        final eq =
            l.toString() == r.toString() && l.runtimeType == r.runtimeType;
        return op == TokenType.EQ_EQ ? eq : !eq;
      }
      throw _CannotEval(e.toSource());
    }
    if (e is SimpleIdentifier) {
      if (env.containsKey(e.name)) return env[e.name];
      return _const(e.element, e);
    }
    if (e is PrefixedIdentifier) {
      final el = e.element;
      final v = _enumOrConst(el, e);
      if (v != null) return v;
      return _property(_eval(e.prefix, env), e.identifier.name, e);
    }
    if (e is PropertyAccess) {
      final el = e.propertyName.element;
      final v = _enumOrConst(el, e);
      if (v != null) return v;
      return _property(_eval(e.realTarget, env), e.propertyName.name, e);
    }
    if (e is MethodInvocation) {
      final args = e.argumentList.arguments;
      final target = e.realTarget;
      if (target != null) {
        final t = _eval(target, env);
        final a = [for (final x in args) _eval(x.argumentExpression, env)];
        if (t is String) {
          switch (e.methodName.name) {
            case 'startsWith':
              return t.startsWith(_str(a.single, e));
            case 'endsWith':
              return t.endsWith(_str(a.single, e));
            case 'contains':
              return t.contains(_str(a.single, e));
            case 'split':
              return t.split(_str(a.single, e));
            case 'toLowerCase':
              return t.toLowerCase();
            case 'toUpperCase':
              return t.toUpperCase();
            case 'trim':
              return t.trim();
          }
        }
        throw _CannotEval(e.toSource());
      }
      final el = e.methodName.element;
      if (el is TopLevelFunctionElement) {
        final decl = _functions[el.baseElement];
        if (decl == null) throw _CannotEval(e.toSource());
        final params =
            decl.functionExpression.parameters?.parameters ?? const [];
        if (params.length != args.length) throw _CannotEval(e.toSource());
        final inner = <String, Object?>{
          for (var i = 0; i < params.length; i++)
            params[i].name!.lexeme: _eval(args[i].argumentExpression, env)
        };
        return _eval(_body(decl.functionExpression.body, decl), inner);
      }
      throw _CannotEval(e.toSource());
    }
    throw _CannotEval(e.toSource());
  }

  Object? _enumOrConst(Element? el, Expression e) {
    var x = el;
    if (x is PropertyAccessorElement) x = x.variable;
    if (x is FieldElement && x.isEnumConstant) {
      return _EnumValue(x.enclosingElement.name ?? '?', x.name ?? '?');
    }
    if (x is VariableElement && x.isConst) return _const(x, e);
    return null;
  }

  Object? _const(Element? el, Expression e) {
    var x = el;
    if (x is PropertyAccessorElement) x = x.variable;
    if (x is VariableElement) {
      final v = x.computeConstantValue();
      final s = v?.toStringValue();
      if (s != null) return s;
      final b = v?.toBoolValue();
      if (b != null) return b;
    }
    throw _CannotEval(e.toSource());
  }

  Object? _property(Object? target, String name, Expression e) {
    if (target is List) {
      if (name == 'last') return target.last;
      if (name == 'first') return target.first;
    }
    if (target is String && name == 'length') return target.length;
    throw _CannotEval(e.toSource());
  }

  String _str(Object? v, Expression e) {
    if (v is String) return v;
    throw _CannotEval(e.toSource());
  }

  bool _bool(Object? v, Expression e) {
    if (v is bool) return v;
    throw _CannotEval(e.toSource());
  }
}

class _TopLevelCalls extends RecursiveAstVisitor<void> {
  _TopLevelCalls(this.out);
  final List<Element> out;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final e = node.methodName.element;
    if (e is TopLevelFunctionElement) out.add(e.baseElement);
    super.visitMethodInvocation(node);
  }
}
