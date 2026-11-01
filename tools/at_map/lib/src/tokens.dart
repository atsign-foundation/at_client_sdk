import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:crypto/crypto.dart';

/// The lexemes of [source] as the Dart scanner splits them; comments,
/// layout and the tokens a parser inserts to recover are not lexemes.
List<String> lexemes(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final out = <String>[];
  for (Token t = unit.beginToken; !t.isEof; t = t.next!) {
    if (!t.isSynthetic) out.add(t.lexeme);
  }
  return out;
}

/// The tokens of [node], first to last, after its doc comment and
/// annotations.
List<Token> nodeTokens(AstNode node) {
  final out = <Token>[];
  final end = node.endToken;
  final first = node is AnnotatedNode
      ? node.firstTokenAfterCommentAndMetadata
      : node.beginToken;
  for (Token? t = first; t != null; t = t.next) {
    out.add(t);
    if (identical(t, end) || t.isEof) break;
  }
  return out;
}

/// The offsets at which [needle] occurs in [haystack], compared lexeme by
/// lexeme.
List<int> tokenMatches(List<Token> haystack, List<String> needle) {
  final hits = <int>[];
  if (needle.isEmpty) return hits;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j].lexeme != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) hits.add(haystack[i].offset);
  }
  return hits;
}

/// A short sha256 of [tokens]' lexemes, so layout and comments do not count;
/// [skip] is left out, which is how a rename keeps its hash.
String tokenHash(Iterable<Token> tokens, {Token? skip}) {
  final b = StringBuffer();
  for (final t in tokens) {
    if (identical(t, skip)) continue;
    b
      ..write(t.lexeme)
      ..write(' ');
  }
  return sha256.convert(utf8.encode(b.toString())).toString().substring(0, 16);
}

/// The full sha256 of [text].
String textHash(String text) => sha256.convert(utf8.encode(text)).toString();
