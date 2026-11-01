import 'package:at_client/src/enroll/authorised_namespaces.dart'
    show grantCovering;
import 'package:test/test.dart';

/// The access a set of grants gives a key, which the local access check reads,
/// row by row as the atServer's own check answers each shape.
void main() {
  final rows =
      <({String why, Map<String, String> grants, String key, String? access})>[
    (
      why: 'a dotted grant covers a key whose name ends with it',
      grants: {'cmp.rotation': 'rw'},
      key: 'x.cmp.rotation@bob',
      access: 'rw'
    ),
    (
      why: 'a dotted grant covers a public key under it',
      grants: {'cmp.rotation': 'rw'},
      key: 'public:__nskey.cmp.rotation@bob',
      access: 'rw'
    ),
    (
      why: 'a dotted grant covers a key shared with another atSign',
      grants: {'cmp.rotation': 'r'},
      key: '@alice:x.cmp.rotation@bob',
      access: 'r'
    ),
    (
      why: 'a dotted grant does not cover the key named cmp in rotation',
      grants: {'cmp.rotation': 'rw'},
      key: 'cmp.rotation@bob',
      access: null
    ),
    (
      why: 'a dotted grant does not cover a key beside it',
      grants: {'cmp.rotation': 'rw'},
      key: 'x.other.rotation@bob',
      access: null
    ),
    (
      why: 'a dotted grant does not cover a key above it',
      grants: {'cmp.rotation': 'rw'},
      key: 'x.rotation@bob',
      access: null
    ),
    (
      why: 'a grant matches only at a dot',
      grants: {'mp.rotation': 'rw'},
      key: 'x.cmp.rotation@bob',
      access: null
    ),
    (
      why: 'any dot-bounded tail of a dotted key name is covered',
      grants: {'b.cmp.rotation': 'r'},
      key: 'a.b.cmp.rotation@bob',
      access: 'r'
    ),
    (
      why: 'a grant equal to the whole key name does not cover it',
      grants: {'a.b.cmp.rotation': 'r'},
      key: 'a.b.cmp.rotation@bob',
      access: null
    ),
    (
      why: 'a grant on the last segment wins over a dotted grant',
      grants: {'cmp.rotation': 'rw', 'rotation': 'r'},
      key: 'x.cmp.rotation@bob',
      access: 'r'
    ),
    (
      why: 'of two dotted grants, the first listed wins',
      grants: {'b.c': 'r', 'a.b.c': 'rw'},
      key: 'z.a.b.c@bob',
      access: 'r'
    ),
    (
      why: 'of two dotted grants, the first listed wins, either way round',
      grants: {'a.b.c': 'rw', 'b.c': 'r'},
      key: 'z.a.b.c@bob',
      access: 'rw'
    ),
    (
      why: 'a grant naming the namespace wins over *',
      grants: {'*': 'r', 'rotation': 'rw'},
      key: 'x.rotation@bob',
      access: 'rw'
    ),
    (
      why: 'a grant naming the namespace wins over *, even when it gives less',
      grants: {'*': 'rw', 'rotation': 'r'},
      key: 'x.rotation@bob',
      access: 'r'
    ),
    (
      why: 'a dotted grant wins over *',
      grants: {'*': 'r', 'cmp.rotation': 'rw'},
      key: 'x.cmp.rotation@bob',
      access: 'rw'
    ),
    (
      why: '* answers for a key no grant covers',
      grants: {'*': 'r', 'wavi': 'rw'},
      key: 'x.cmp.rotation@bob',
      access: 'r'
    ),
    (
      why: 'a key with no namespace is answered by * alone',
      grants: {'phone': 'rw'},
      key: 'phone@bob',
      access: null
    ),
    (
      why: 'a key with no namespace takes *',
      grants: {'*': 'r'},
      key: 'phone@bob',
      access: 'r'
    ),
    (
      why: 'a key with an empty namespace is answered by * alone',
      grants: {'phone': 'rw'},
      key: 'phone.@bob',
      access: null
    ),
    (
      why: 'a grant is compared as it is spelled',
      grants: {'Cmp.Rotation': 'rw'},
      key: 'x.cmp.rotation@bob',
      access: null
    ),
    (
      why: 'a key that does not parse is answered by * alone',
      grants: {'*': 'r', 'phone': 'rw'},
      key: 'phone',
      access: 'r'
    ),
    (
      why: 'a key that does not parse, with no *, has no access',
      grants: {'phone': 'rw'},
      key: 'phone',
      access: null
    ),
  ];

  group('Given the grants an enrollment holds', () {
    for (final row in rows) {
      test('when the key is ${row.key} under ${row.grants}, then ${row.why}',
          () {
        expect(grantCovering(row.grants, row.key)?.access, row.access);
      });
    }
  });
}
