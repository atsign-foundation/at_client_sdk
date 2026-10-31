import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// A declaration found by its qualified name: `Class.member`, `Class`, or a
/// top-level name.
class Decl {
  /// Creates a declaration record.
  Decl(this.name, this.node, this.nameToken);

  /// The qualified name.
  final String name;

  /// The declaring node.
  final AstNode node;

  /// The token that names it, left out of its body hash.
  final Token? nameToken;
}

/// Every declaration in [unit], by qualified name; a name declared twice maps
/// to every declaration of it.
Map<String, List<Decl>> indexDeclarations(CompilationUnit unit) {
  final out = <String, List<Decl>>{};
  void add(String name, AstNode node, Token? nameToken) =>
      (out[name] ??= []).add(Decl(name, node, nameToken));

  void members(String container, List<ClassMember> ms) {
    for (final m in ms) {
      if (m is MethodDeclaration) {
        add('$container.${m.name.lexeme}', m, m.name);
      } else if (m is ConstructorDeclaration) {
        add('$container.${m.name?.lexeme ?? 'new'}', m, m.name);
      } else if (m is FieldDeclaration) {
        for (final v in m.fields.variables) {
          add('$container.${v.name.lexeme}', v, v.name);
        }
      }
    }
  }

  for (final d in unit.declarations) {
    if (d is ClassDeclaration) {
      final name = d.namePart.typeName.lexeme;
      add(name, d, d.namePart.typeName);
      members(name, d.body.members);
    } else if (d is MixinDeclaration) {
      add(d.name.lexeme, d, d.name);
      members(d.name.lexeme, d.body.members);
    } else if (d is EnumDeclaration) {
      final name = d.namePart.typeName.lexeme;
      add(name, d, d.namePart.typeName);
      members(name, d.body.members);
    } else if (d is ExtensionDeclaration && d.name != null) {
      add(d.name!.lexeme, d, d.name);
      members(d.name!.lexeme, d.body.members);
    } else if (d is FunctionDeclaration) {
      add(d.name.lexeme, d, d.name);
    } else if (d is TopLevelVariableDeclaration) {
      for (final v in d.variables.variables) {
        add(v.name.lexeme, v, v.name);
      }
    }
  }
  return out;
}

/// Parses [content] without resolving it.
CompilationUnit parseUnit(String content) =>
    parseString(content: content, throwIfDiagnostics: false).unit;

/// The executable body of [node], for a method or a function.
FunctionBody? bodyOf(AstNode node) {
  if (node is MethodDeclaration) return node.body;
  if (node is FunctionDeclaration) return node.functionExpression.body;
  if (node is ConstructorDeclaration) return node.body;
  return null;
}

/// The first token of [node] after its doc comment and annotations.
Token firstCodeToken(AstNode node) => node is AnnotatedNode
    ? node.firstTokenAfterCommentAndMetadata
    : node.beginToken;
