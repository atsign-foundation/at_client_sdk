import 'dart:convert';

/// The names an atServer lists capabilities under in its `info` `features`.
///
/// A name, once published, is never reused: a feature an atServer retires
/// stays listed, as [InfoFeatureStatus.retired].
class InfoFeature {
  /// `eph` on notify: a notification no atServer persists.
  static const String notifyEph = 'notify.eph';

  /// `eAtn` on notify: a notification's own expiry.
  static const String notifyEAtn = 'notify.eAtn';

  /// The `notify:all` verb.
  static const String notifyAll = 'notify.all';

  /// `messageType:text` on notify.
  static const String notifyText = 'notify.text';
}

/// The statuses an atServer gives a feature in its `info` `features`, spelt
/// exactly as they travel.
///
/// Each atServer decides the status it gives each feature.
class InfoFeatureStatus {
  static const String preview = 'Preview';
  static const String beta = 'Beta';
  static const String ga = 'GA';

  /// Still works, and will be retired.
  static const String deprecated = 'Deprecated';

  /// Refused.
  static const String retired = 'Retired';
}

/// The features one atServer listed in one `info` reply, read the same way by
/// a client and by an atServer reading a peer.
///
/// A feature counts as present when it is listed with any status but
/// [InfoFeatureStatus.retired]. Statuses are compared exactly, so a status
/// this reader does not know, or none at all, counts as present too. Hold one
/// per connection: [has] warns once per feature for this answer.
class InfoFeatures {
  final Map<String, String?> _statuses;
  final Set<String> _warned = {};

  /// Features listed with the given statuses; null where an entry has none.
  InfoFeatures(Map<String, String?> statuses)
      : _statuses = Map.unmodifiable(statuses);

  /// Reads the `features` of an `info` [reply], with or without its `data:`
  /// prefix: none when it lists no features, or null when it cannot be read.
  static InfoFeatures? parse(String reply) {
    final body = reply.startsWith('data:') ? reply.substring(5) : reply;
    final Object? info;
    try {
      info = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (info is! Map) return null;
    final features = info['features'];
    if (features is! List) return InfoFeatures(const {});
    final statuses = <String, String?>{};
    for (final f in features) {
      if (f is! Map || f['name'] is! String) continue;
      final name = f['name'] as String;
      // NOTE: a name listed twice is absent if either entry says Retired.
      if (statuses[name] == InfoFeatureStatus.retired) continue;
      statuses[name] = f['status'] is String ? f['status'] as String : null;
    }
    return InfoFeatures(statuses);
  }

  /// The status [feature] is listed with, as it travelled, or null when it is
  /// listed with none or not listed.
  String? statusOf(String feature) => _statuses[feature];

  /// Whether [feature] is present.
  ///
  /// When it is present with a status other than [InfoFeatureStatus.ga],
  /// [warn] is called, the first time only, with a message naming it.
  bool has(String feature, {void Function(String message)? warn}) {
    if (!_statuses.containsKey(feature)) return false;
    final status = _statuses[feature];
    if (status == InfoFeatureStatus.retired) return false;
    if (status != InfoFeatureStatus.ga && _warned.add(feature)) {
      warn?.call('Using $feature, which this atServer lists as '
          '${status ?? 'having no status'} rather than GA');
    }
    return true;
  }
}
