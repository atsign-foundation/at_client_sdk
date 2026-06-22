import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pq_demo_6/openssl.dart';
import '../lib/ratchet_tree.dart';

void main() {
  late Crypto c;
  setUp(() => c = Crypto.load());

  test('addLeaf returns sequential leaf indices', () {
    final tree = RatchetTree.empty();
    final (pk0, _) = c.xwing.keygen();
    final (pk1, _) = c.xwing.keygen();
    expect(tree.addLeaf(pk0), 0);
    expect(tree.addLeaf(pk1), 1);
    expect(tree.numLeaves, 2);
  });

  test('commitPath for solo group returns empty path + commitSecret', () {
    final tree = RatchetTree.empty();
    final (pk, _) = c.xwing.keygen();
    tree.addLeaf(pk);
    final ctx = Uint8List.fromList('ctx'.codeUnits);
    final (path, cs) = tree.commitPath(c, 0, c.rand.bytes(32), ctx);
    expect(path.nodes, isEmpty);
    expect(cs.length, 32);
  });

  test('commitPath for 2-leaf tree has nodes', () {
    final tree = RatchetTree.empty();
    final (pk0, _) = c.xwing.keygen();
    final (pk1, _) = c.xwing.keygen();
    tree.addLeaf(pk0);
    tree.addLeaf(pk1);
    final ctx = Uint8List.fromList('ctx'.codeUnits);
    final (path, cs) = tree.commitPath(c, 0, c.rand.bytes(32), ctx);
    expect(path.nodes, isNotEmpty);
    expect(cs.length, 32);
  });

  test('treeHash changes after addLeaf', () {
    final tree = RatchetTree.empty();
    final (pk0, _) = c.xwing.keygen();
    final (pk1, _) = c.xwing.keygen();
    tree.addLeaf(pk0);
    final h1 = tree.treeHash(c);
    tree.addLeaf(pk1);
    final h2 = tree.treeHash(c);
    expect(h1, isNot(equals(h2)));
  });

  test('JSON round-trip preserves numLeaves', () {
    final tree = RatchetTree.empty();
    final (pk, _) = c.xwing.keygen();
    tree.addLeaf(pk);
    final tree2 = RatchetTree.fromJson(tree.toJson());
    expect(tree2.numLeaves, 1);
  });
}
