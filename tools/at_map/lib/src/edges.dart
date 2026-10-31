import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'analysis.dart';
import 'decls.dart';
import 'source.dart';

/// Every call in [decl]'s body, closures included, by resolved element.
List<(Element, AstNode)> callsIn(AstNode decl) {
  final out = <(Element, AstNode)>[];
  decl.accept(_Calls(out));
  return out;
}

/// The first call in [decl] to the qualified [symbol].
Element? findCall(AstNode decl, String symbol) {
  for (final (e, _) in callsIn(decl)) {
    if (qualifiedName(e) == symbol) return e;
  }
  return null;
}

class _Calls extends RecursiveAstVisitor<void> {
  _Calls(this.out);
  final List<(Element, AstNode)> out;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final e = node.methodName.element;
    if (e != null) out.add((e, node));
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final e = node.element;
    if (e != null) out.add((e, node));
    super.visitFunctionExpressionInvocation(node);
  }
}

/// The field [e] reads, when it is a field or a field's getter.
FieldElement? fieldOf(Element? e) {
  var x = e;
  if (x is PropertyAccessorElement) x = x.variable;
  return x is FieldElement ? x.baseElement : null;
}

Element? _referenced(Expression? e) {
  if (e is SimpleIdentifier) return e.element;
  if (e is PrefixedIdentifier) return e.element;
  if (e is PropertyAccess) return e.propertyName.element;
  return null;
}

/// The method or function a tear-off expression names.
Element? tearOff(Expression e) {
  final el = _referenced(e);
  if (el is MethodElement || el is TopLevelFunctionElement) return el;
  return null;
}

/// A binding of an async hop: who feeds it and who it hands to.
class Binding {
  /// Creates a binding.
  Binding(this.field, this.consumer, this.where);

  /// The field the hop passes through, as `Class.field`.
  final String field;

  /// The method it hands to.
  final Element consumer;

  /// Where the binding is made.
  final String where;
}

String _enclosing(AstNode n) {
  final m = n.thisOrAncestorOfType<MethodDeclaration>();
  final c = n.thisOrAncestorOfType<ConstructorDeclaration>();
  final f = n.thisOrAncestorOfType<FunctionDeclaration>();
  final cls =
      n.thisOrAncestorOfType<ClassDeclaration>()?.namePart.typeName.lexeme;
  if (m != null) return '$cls.${m.name.lexeme}';
  if (c != null) return '$cls.${c.name?.lexeme ?? 'new'}';
  if (f != null) return f.name.lexeme;
  return cls ?? '?';
}

/// Finds the binders that connect two steps when no call does.
class Binders {
  /// Creates a binder search over [tree]'s [libs] through [resolver].
  Binders(this.resolver, this.tree, this.libs);

  /// Resolves candidate files.
  final Resolver resolver;

  /// The root holding them.
  final Tree tree;

  /// Library directories searched.
  final List<String> libs;

  /// Function-typed fields [decl] invokes.
  List<FieldElement> invokedFunctionFields(AstNode decl) {
    final out = <FieldElement>[];
    decl.accept(_FunctionFieldCalls((f) {
      if (f.type is FunctionType) out.add(f);
    }));
    return out;
  }

  /// StreamController fields [decl] adds to.
  List<FieldElement> streamsAddedTo(AstNode decl) {
    final out = <FieldElement>[];
    for (final (_, node) in callsIn(decl)) {
      if (node is! MethodInvocation || node.methodName.name != 'add') continue;
      final f = fieldOf(_referenced(node.realTarget));
      final t = f?.type;
      if (f != null &&
          t is InterfaceType &&
          t.element.name == 'StreamController') {
        out.add(f);
      }
    }
    return out;
  }

  Future<List<CompilationUnit>> _candidates(String token) async {
    final out = <CompilationUnit>[];
    for (final lib in libs) {
      for (final path in tree.filesUnder('$lib/', suffix: '.dart')) {
        final text = tree.read(path);
        if (text == null || !text.contains(token)) continue;
        final u = await resolver.unit(tree.absolute(path));
        if (u != null) out.add(u.unit);
      }
    }
    return out;
  }

  /// Tear-offs bound to the function-typed field [f].
  Future<List<Binding>> functionFieldBindings(FieldElement f) async {
    final out = <Binding>[];
    final name = f.name ?? '';
    for (final u in await _candidates(name)) {
      u.accept(_FieldBinds(
          f,
          (consumer, at) => out.add(Binding(
              '${f.enclosingElement.name}.$name', consumer, _enclosing(at)))));
    }
    return out;
  }

  /// Tear-offs that listen to the StreamController field [f].
  Future<List<Binding>> streamBindings(FieldElement f) async {
    final out = <Binding>[];
    final name = f.name ?? '';
    for (final u in await _candidates(name)) {
      u.accept(_Listens(
          f,
          (consumer, at) => out.add(Binding(
              '${f.enclosingElement.name}.$name', consumer, _enclosing(at)))));
    }
    return out;
  }

  /// The field the declaration [symbol] names in [path], resolved.
  Future<FieldElement?> field(String path, String symbol) async {
    final u = await resolver.unit(tree.absolute(path));
    if (u == null) return null;
    final hits = indexDeclarations(u.unit)[symbol];
    if (hits == null || hits.length != 1) return null;
    final n = hits.single.node;
    if (n is! VariableDeclaration) return null;
    final e = n.declaredFragment?.element;
    return e is FieldElement ? e : null;
  }
}

class _FunctionFieldCalls extends RecursiveAstVisitor<void> {
  _FunctionFieldCalls(this.found);
  final void Function(FieldElement) found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final f = fieldOf(node.methodName.element);
    if (f != null) found(f);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final f = fieldOf(_referenced(node.function));
    if (f != null) found(f);
    super.visitFunctionExpressionInvocation(node);
  }
}

class _FieldBinds extends RecursiveAstVisitor<void> {
  _FieldBinds(this.field, this.found);
  final FieldElement field;
  final void Function(Element consumer, AstNode at) found;

  @override
  void visitNamedArgument(NamedArgument node) {
    final p = node.correspondingParameter;
    if (p is FieldFormalParameterElement &&
        p.field?.baseElement == field.baseElement) {
      final t = tearOff(node.argumentExpression);
      if (t != null) found(t, node);
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (fieldOf(node.writeElement)?.baseElement == field.baseElement) {
      final t = tearOff(node.rightHandSide);
      if (t != null) found(t, node);
    }
    super.visitAssignmentExpression(node);
  }
}

class _Listens extends RecursiveAstVisitor<void> {
  _Listens(this.field, this.found);
  final FieldElement field;
  final void Function(Element consumer, AstNode at) found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'listen' &&
        node.argumentList.arguments.isNotEmpty) {
      final target = node.realTarget;
      Expression? streamOf;
      if (target is PropertyAccess && target.propertyName.name == 'stream') {
        streamOf = target.realTarget;
      } else if (target is PrefixedIdentifier &&
          target.identifier.name == 'stream') {
        streamOf = target.prefix;
      }
      if (fieldOf(_referenced(streamOf))?.baseElement == field.baseElement) {
        final t = tearOff(node.argumentList.arguments.first.argumentExpression);
        if (t != null) found(t, node);
      }
    }
    super.visitMethodInvocation(node);
  }
}
