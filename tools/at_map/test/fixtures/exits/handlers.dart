/// Guard shapes the exit walker's tests run it over.
library;

import 'helpers.dart';

/// What a handler answers.
class Response {
  /// The answer.
  String? data;

  /// Whether the answer is an error.
  bool isError = false;

  /// The error's text.
  String? errorMessage;
}

/// A refusal of authentication.
class UnAuthenticatedException implements Exception {
  /// Creates the exception.
  UnAuthenticatedException(this.message);

  /// Why.
  final String message;
}

/// A refusal of a command's shape.
class InvalidSyntaxException implements Exception {
  /// Creates the exception.
  InvalidSyntaxException(this.message);

  /// Why.
  final String message;
}

/// Another object, whose methods are not the handler's helpers.
class Other {
  /// Throws, but is never followed.
  void check() {
    throw StateError('never followed');
  }
}

/// One handler method per guard shape.
class Fixture {
  /// Another object.
  final Other other = Other();

  /// What the last call did.
  String last = '';

  /// A throw in an else.
  void ifElse(String digestFromClient, String expectedDigest) {
    if (digestFromClient == expectedDigest) {
      last = 'ok';
    } else {
      throw UnAuthenticatedException('digest mismatch');
    }
  }

  /// Throws in an if and an else-if.
  void elseIf(int a, int b) {
    if (a > 1) {
      throw InvalidSyntaxException('a too big');
    } else if (b > 1) {
      throw InvalidSyntaxException('b too big');
    } else {
      last = 'fine';
    }
  }

  /// A success written, an error written and a plain return, each early.
  void earlyReturns(Response response, String? x, bool y) {
    if (x == null) {
      response.data = 'data:success';
      return;
    }
    if (y) {
      response.isError = true;
      response.errorMessage = 'refused';
      return;
    }
    if (x.isEmpty) return;
    response.data = 'done';
    return;
  }

  /// Throws in switch cases, two sharing a body.
  void switches(String op) {
    switch (op) {
      case 'a':
        throw InvalidSyntaxException('case a');
      case 'b':
      case 'c':
        throw InvalidSyntaxException('case b or c');
      default:
        return;
    }
  }

  /// Throws inside try blocks, caught and not.
  void tryCatch(String s) {
    try {
      throw InvalidSyntaxException('caught by the catch-all');
    } catch (e) {
      last = 'handled';
    }
    try {
      throw InvalidSyntaxException('not a FormatException');
    } on FormatException {
      last = 'wrong type';
    }
    try {
      int.parse(s);
    } on FormatException catch (e) {
      throw InvalidSyntaxException('bad number: ${e.message}');
    }
    try {
      _throwsAlways();
    } on InvalidSyntaxException {
      rethrow;
    }
  }

  /// Calls helpers of every kind.
  void helpers(int n) {
    _sameClass(n);
    sameFile(n);
    Fixture.staticHelper(n);
    otherFile(n);
    other.check();
  }

  void _sameClass(int n) {
    if (n < 0) throw InvalidSyntaxException('negative');
  }

  /// A static helper.
  static void staticHelper(int n) {
    if (n > 100) throw InvalidSyntaxException('too large');
  }

  void _throwsAlways() {
    throw InvalidSyntaxException('from a helper');
  }

  /// A generator, whose yield the walker does not handle.
  Iterable<int> generator(bool x) sync* {
    if (x) throw InvalidSyntaxException('before the yield');
    yield 1;
  }

  /// A throw eight conditions deep.
  void deep(int a, int b, int c, int d, int e, int f, int g, int h) {
    if (a > 0) {
      if (b > 0) {
        if (c > 0) {
          if (d > 0) {
            if (e > 0) {
              if (f > 0) {
                if (g > 0) {
                  if (h > 0) {
                    throw InvalidSyntaxException('deep');
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  /// A throw three conditions deep.
  void shallow(int a, int b, int c) {
    if (a > 0) {
      if (b > 0) {
        if (c > 0) {
          throw InvalidSyntaxException('shallow');
        }
      }
    }
  }
}

/// A helper in the same file.
void sameFile(int n) {
  if (n == 7) throw InvalidSyntaxException('seven');
}
