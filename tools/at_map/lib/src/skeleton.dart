import 'package:analyzer/dart/ast/ast.dart';

import 'decls.dart';

String _short(String s, [int max = 90]) {
  final one = s.replaceAll(RegExp(r'\s+'), ' ');
  return one.length <= max ? one : '${one.substring(0, max - 1)}…';
}

bool _isLogging(Expression e) =>
    RegExp(r'^(_?logger|_log|_logger|logSwallowed|print)\b')
        .hasMatch(e.toSource());

String _calls(Expression e) {
  final names = <String>[];
  void walk(AstNode n) {
    if (n is FunctionExpression) return;
    for (final c in n.childEntities) {
      if (c is AstNode) walk(c);
    }
    if (n is MethodInvocation) {
      final t = n.target?.toSource();
      names.add(t == null
          ? n.methodName.name
          : '${_short(t, 30)}.${n.methodName.name}');
    } else if (n is InstanceCreationExpression) {
      names.add('new ${n.constructorName.type.name.lexeme}');
    }
  }

  walk(e);
  return names.join(', ');
}

/// Pseudo-code for [decl]: its control flow, calls, throws and returns,
/// without logging.
String skeleton(AstNode decl) {
  final out = StringBuffer();
  final body = bodyOf(decl);
  if (body is BlockFunctionBody) {
    _emit(body.block, 0, out);
  } else if (body is ExpressionFunctionBody) {
    final c = _calls(body.expression);
    out.writeln('return ${c.isEmpty ? _short(body.expression.toSource()) : c}');
  }
  return out.toString();
}

void _emit(Statement s, int depth, StringBuffer out) {
  final pad = '  ' * depth;
  if (s is Block) {
    for (final t in s.statements) {
      _emit(t, depth, out);
    }
  } else if (s is IfStatement) {
    final then = StringBuffer();
    _emit(s.thenStatement, depth + 1, then);
    final otherwise = StringBuffer();
    final e = s.elseStatement;
    if (e != null) _emit(e, depth + 1, otherwise);
    if (then.isEmpty && otherwise.isEmpty) return;
    out
      ..writeln('${pad}if ${_short(s.expression.toSource())}:')
      ..write(then);
    if (otherwise.isNotEmpty) {
      out
        ..writeln('${pad}else:')
        ..write(otherwise);
    }
  } else if (s is SwitchStatement) {
    out.writeln('${pad}switch ${_short(s.expression.toSource())}:');
    for (final m in s.members) {
      final label = m is SwitchCase
          ? 'case ${_short(m.expression.toSource(), 50)}'
          : m is SwitchPatternCase
              ? 'case ${_short(m.guardedPattern.toSource(), 50)}'
              : 'default';
      out.writeln('$pad  $label:');
      for (final t in m.statements) {
        _emit(t, depth + 2, out);
      }
    }
  } else if (s is TryStatement) {
    out.writeln('${pad}try:');
    _emit(s.body, depth + 1, out);
    for (final c in s.catchClauses) {
      out.writeln('${pad}on ${c.exceptionType?.toSource() ?? 'any'}:');
      _emit(c.body, depth + 1, out);
    }
    final f = s.finallyBlock;
    if (f != null) {
      out.writeln('${pad}finally:');
      _emit(f, depth + 1, out);
    }
  } else if (s is ForStatement) {
    out.writeln('${pad}loop ${_short(s.forLoopParts.toSource(), 60)}:');
    _emit(s.body, depth + 1, out);
  } else if (s is WhileStatement) {
    out.writeln('${pad}loop while ${_short(s.condition.toSource(), 60)}:');
    _emit(s.body, depth + 1, out);
  } else if (s is DoStatement) {
    out.writeln('${pad}loop:');
    _emit(s.body, depth + 1, out);
  } else if (s is ReturnStatement) {
    final e = s.expression;
    out.writeln(
        '${pad}return${e == null ? '' : ' ${_short(e.toSource(), 70)}'}');
  } else if (s is ExpressionStatement) {
    final e = s.expression;
    if (e is ThrowExpression) {
      final x = e.expression;
      out.writeln('${pad}throw '
          '${x is InstanceCreationExpression ? x.constructorName.type.name.lexeme : _short(x.toSource(), 40)}');
    } else if (e is RethrowExpression) {
      out.writeln('${pad}rethrow');
    } else if (!_isLogging(e)) {
      if (e is AssignmentExpression) {
        final c = _calls(e.rightHandSide);
        final aw =
            e.rightHandSide.toSource().startsWith('await ') ? 'await ' : '';
        out.writeln('$pad${_short(e.leftHandSide.toSource(), 40)} = '
            '$aw${c.isEmpty ? _short(e.rightHandSide.toSource(), 50) : c}');
      } else {
        final c = _calls(e);
        if (c.isNotEmpty) {
          final aw = e is AwaitExpression ? 'await ' : '';
          out.writeln('$pad$aw$c');
        }
      }
    }
  } else if (s is VariableDeclarationStatement) {
    for (final v in s.variables.variables) {
      final init = v.initializer;
      if (init == null) continue;
      final c = _calls(init);
      if (c.isEmpty) continue;
      final aw = init is AwaitExpression ? 'await ' : '';
      out.writeln('$pad${v.name.lexeme} = $aw$c');
    }
  }
}
