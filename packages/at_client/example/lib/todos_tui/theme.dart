import 'package:at_client/at_client.dart';
import 'package:nocterm/nocterm.dart';

/// Per-TUI colour helpers. One instance lives on the State class,
/// seeded with the current atSign at init time.
///
/// - [colorForAtSign] assigns a stable colour to each seen atSign by
///   walking a pastel palette in order; the current atSign always
///   gets the accent orange.
/// - [colorForDue] encodes due-date urgency (overdue=red, ≤24h=amber,
///   otherwise green; done items are greyed regardless).
class TodoTheme {
  static const List<int> _palette = [
    27, 33, 39, 63, 69, 75, 76, 82, 99, 105, 129, 135, 141, 148,
    160, 161, 162, 166, 172, 178, 196, 200, 201, 202, 208, 214,
  ];
  final Atsign self;
  final Map<String, int> _assigned = {};
  int _nextIdx = 0;

  TodoTheme(this.self);

  /// Converts an ANSI-256 colour-cube index (16..231) to an RGB Color
  /// using the canonical 6x6x6 cube steps.
  static Color _ansi256ToColor(int idx) {
    if (idx < 16 || idx > 231) return Colors.white;
    final n = idx - 16;
    final r = (n ~/ 36) % 6;
    final g = (n ~/ 6) % 6;
    final b = n % 6;
    const steps = [0, 95, 135, 175, 215, 255];
    return Color.fromRGB(steps[r], steps[g], steps[b]);
  }

  Color colorForAtSign(Atsign a) {
    if (a == self) return const Color.fromRGB(255, 135, 0); // self = orange
    final key = a.toString();
    final idx = _assigned.putIfAbsent(key, () {
      final i = _nextIdx;
      _nextIdx = (_nextIdx + 1) % _palette.length;
      return i;
    });
    return _ansi256ToColor(_palette[idx]);
  }

  TextStyle styleForAtSign(Atsign a, {bool bold = false}) => TextStyle(
    color: colorForAtSign(a),
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
  );

  Color colorForDue(DateTime? due, {required bool done}) {
    if (done) return Colors.gray;
    if (due == null) return Colors.white;
    final diff = due.difference(DateTime.now());
    if (diff.isNegative) return Colors.red;
    if (diff.inHours < 24) return const Color.fromRGB(255, 175, 0);
    return Colors.green;
  }
}
