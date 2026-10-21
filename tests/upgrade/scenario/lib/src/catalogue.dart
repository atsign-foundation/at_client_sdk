import 'package:at_commons/at_commons.dart' show AtKey, Metadata;

/// The shapes an app's record can take.
enum RecordKind { self, shared, public, local }

/// One record the seed writes and every later phase reads back.
class RecordSpec {
  final String name;
  final RecordKind kind;

  /// A `String`, or a `List<int>` for a binary record.
  final Object value;

  const RecordSpec(this.name, this.kind, this.value);

  /// A new key for this record on every call, so no phase inherits metadata
  /// another phase's read left on a key it shared.
  AtKey keyFor(
      {required String me, required String peer, required String namespace}) {
    switch (kind) {
      case RecordKind.local:
        return AtKey.local(name, me, namespace: namespace).build();
      case RecordKind.self:
        return AtKey()
          ..key = name
          ..namespace = namespace
          ..sharedBy = me;
      case RecordKind.shared:
        return AtKey()
          ..key = name
          ..namespace = namespace
          ..sharedBy = me
          ..sharedWith = peer;
      case RecordKind.public:
        return AtKey()
          ..key = name
          ..namespace = namespace
          ..sharedBy = me
          ..metadata = (Metadata()..isPublic = true);
    }
  }
}

/// Every record the seed writes: one of each kind, plus a value with a
/// newline and a binary one, the two shapes stored encoded.
const catalogue = <RecordSpec>[
  RecordSpec('upgself', RecordKind.self, 'a self value'),
  RecordSpec('upgselflines', RecordKind.self, 'line one\nline two'),
  RecordSpec('upgbinary', RecordKind.self, <int>[0, 1, 2, 250, 251, 252]),
  RecordSpec('upgshared', RecordKind.shared, 'shared with the peer'),
  RecordSpec('upgpublic', RecordKind.public, 'a public value'),
  RecordSpec('upglocal', RecordKind.local, 'a local value'),
  RecordSpec(
      'upglocallines', RecordKind.local, 'local line one\nlocal line two'),
];

/// Written as the seeding client stops, so the next version may find it still
/// waiting to be pushed.
const pending =
    RecordSpec('upgpending', RecordKind.self, 'written as the client stopped');

/// The collection the seed writes an item and a read receipt in.
String collectionNamespace(String namespace) => 'items.$namespace';

/// The item this atSign owns and shares with the peer.
const myItemId = 'mine';

/// The item the peer owns and shares with this atSign, which it reads.
const peerItemId = 'theirs';

/// How long every collection item lives.
const itemLifetime = Duration(days: 7);
