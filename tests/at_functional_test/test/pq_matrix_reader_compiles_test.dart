import 'package:pq_matrix_scenario/pq_matrix_scenario.dart'
    show readPeerApskAsReleasedReader;
import 'package:test/test.dart';

/// The released arm's reader is written once, against the API at_client
/// 3.14.0 and this tree share, and the released arm compiles it against
/// 3.14.0 only. This file compiles it against this tree, so a change here
/// that breaks it fails to load rather than going unnoticed.
void main() {
  test('the released reader compiles against this tree', () {
    expect(readPeerApskAsReleasedReader, isNotNull);
  });
}
