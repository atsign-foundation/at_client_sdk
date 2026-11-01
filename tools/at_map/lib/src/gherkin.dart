/// A scenario read from a feature file.
class Scenario {
  /// Creates a scenario.
  Scenario(this.title, this.line, this.steps);

  /// Its title.
  final String title;

  /// Its 1-based line.
  final int line;

  /// Its step lines, keyword included, with their 1-based lines.
  final List<(String, int)> steps;
}

final _scenario = RegExp(
    r'^\s*(Scenario Outline|Scenario Template|Scenario|Example):\s*(.*?)\s*$');
final _boundary = RegExp(r'^\s*(Feature|Rule|Background|Examples|Scenarios):');
final _step = RegExp(r'^\s*(Given|When|Then|And|But|\*)\s');

/// The scenarios of a feature file.
List<Scenario> scenarios(String feature) {
  final out = <Scenario>[];
  String? title;
  var line = 0;
  var steps = <(String, int)>[];
  var inExamples = false;
  final lines = feature.split('\n');
  void flush() {
    if (title != null) out.add(Scenario(title!, line, steps));
    title = null;
    steps = [];
  }

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final m = _scenario.firstMatch(l);
    if (m != null) {
      flush();
      title = m.group(2);
      line = i + 1;
      inExamples = false;
      continue;
    }
    if (_boundary.hasMatch(l)) {
      if (l.trimLeft().startsWith('Examples') ||
          l.trimLeft().startsWith('Scenarios')) {
        inExamples = true;
      } else {
        flush();
      }
      continue;
    }
    if (title != null && !inExamples && _step.hasMatch(l)) {
      steps.add((l.trim(), i + 1));
    }
  }
  flush();
  return out;
}

List<String> _words(String s) =>
    s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Where [clause] matched in [feature]'s scenario [title], or why it did
/// not match exactly once.
({int? line, String? error}) matchClause(
    String feature, String title, String clause) {
  final hits = scenarios(feature).where((s) => s.title == title).toList();
  if (hits.isEmpty) return (line: null, error: 'no scenario titled "$title"');
  if (hits.length > 1) {
    return (line: null, error: 'scenario "$title" is titled twice');
  }
  final want = _words(clause);
  final matched = [
    for (final (text, line) in hits.single.steps)
      if (_listEquals(_words(text), want)) line
  ];
  if (matched.length != 1) {
    return (
      line: null,
      error: 'clause "$clause" occurs ${matched.length} times in scenario '
          '"$title", want 1'
    );
  }
  return (line: matched.single, error: null);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
