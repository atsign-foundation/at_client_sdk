/// The instance fields a class body declares, in the shapes a field takes in
/// this tree: with or without a default, `late`, `final`, a generic, function
/// or record type, a default on the next line, a trailing comment. Getters,
/// operators, methods, statics and externals are not fields. Not read: a
/// default holding a `;`, two names in one declaration, a type wrapped across
/// lines. [declarationShapes] pins the reach, and the operator there is `==`,
/// whose `=` must not read as a default.
///
/// A test classifying every field of a class reads the class body from its
/// source and compares it with this, so a field added later turns that test
/// red until it is placed.
Set<String> fieldsDeclaredIn(String body) => RegExp(
        r'^  (?!static |return |external )(?![^;=]*\b(?:get|operator)\s)'
        r'(?:late\s+|final\s+)*[A-Za-z_(][\w<>,?() ]*?\s+([a-zA-Z_]\w*)'
        r'(?:\s*=(?!=)\s*[^;]+)?;\s*(?://.*)?$',
        multiLine: true)
    .allMatches(body)
    .map((m) => m.group(1)!)
    .toSet();

/// A class body declaring a field in every shape, beside members that are
/// not fields.
const declarationShapes = '''
  bool plain = false;
  String? nullable;
  Map<String, dynamic>? generic;
  late String? lateField;
  final String? finalField = null;
  Duration? splitDefault =
      const Duration(days: 8);
  int? withComment; // why
  void Function()? callback;
  (int, String)? pair;
  int get notAField => 0;
  static const String notOne = 'x';
  external int notEither;
  bool operator ==(Object other) => true;
  Map<String, dynamic> toJson() => {};
  String toString() => 'x';
''';
