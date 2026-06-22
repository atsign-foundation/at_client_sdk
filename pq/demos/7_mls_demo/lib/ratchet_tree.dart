import 'dart:convert';
import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart';
import 'mls_crypto.dart';

class TreeNode {
  Uint8List? hpkePk; // X-Wing PK (1216 B); null = blank
  bool isBlank;
  TreeNode({this.hpkePk, this.isBlank = false});
}

class HpkeCiphertext {
  final Uint8List enc; // X-Wing ciphertext (1120 B)
  final Uint8List ct;
  final Uint8List tag;
  HpkeCiphertext({required this.enc, required this.ct, required this.tag});

  Map<String, dynamic> toJson() => {
        'enc': base64Encode(enc),
        'ct': base64Encode(ct),
        'tag': base64Encode(tag),
      };
  factory HpkeCiphertext.fromJson(Map<String, dynamic> j) => HpkeCiphertext(
        enc: base64Decode(j['enc'] as String),
        ct: base64Decode(j['ct'] as String),
        tag: base64Decode(j['tag'] as String),
      );
}

class CommitPathNode {
  final Uint8List nodePk;
  final List<HpkeCiphertext> encryptedPathSecrets;
  CommitPathNode({required this.nodePk, required this.encryptedPathSecrets});

  Map<String, dynamic> toJson() => {
        'nodePk': base64Encode(nodePk),
        'encryptedPathSecrets':
            encryptedPathSecrets.map((e) => e.toJson()).toList(),
      };
  factory CommitPathNode.fromJson(Map<String, dynamic> j) => CommitPathNode(
        nodePk: base64Decode(j['nodePk'] as String),
        encryptedPathSecrets: (j['encryptedPathSecrets'] as List)
            .map((e) => HpkeCiphertext.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CommitPath {
  final List<CommitPathNode> nodes;
  CommitPath(this.nodes);

  Map<String, dynamic> toJson() =>
      {'nodes': nodes.map((n) => n.toJson()).toList()};
  factory CommitPath.fromJson(Map<String, dynamic> j) => CommitPath(
        (j['nodes'] as List)
            .map((e) =>
                CommitPathNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RatchetTree {
  final List<TreeNode> _nodes;
  int _numLeaves;

  RatchetTree._(this._nodes, this._numLeaves);

  factory RatchetTree.empty() => RatchetTree._([], 0);

  factory RatchetTree.fromJson(Map<String, dynamic> j) {
    final numLeaves = j['numLeaves'] as int;
    final nodeList = (j['nodes'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      final pk = m['hpkePk'] as String?;
      return TreeNode(
        hpkePk: pk == null ? null : base64Decode(pk),
        isBlank: m['isBlank'] as bool,
      );
    }).toList();
    return RatchetTree._(nodeList, numLeaves);
  }

  Map<String, dynamic> toJson() => {
        'numLeaves': _numLeaves,
        'nodes': _nodes
            .map((n) => {
                  'hpkePk':
                      n.hpkePk == null ? null : base64Encode(n.hpkePk!),
                  'isBlank': n.isBlank,
                })
            .toList(),
      };

  int get numLeaves => _numLeaves;

  int leafNodeIndex(int leafIndex) => 2 * leafIndex;

  // RFC 9420 §7.1: level = trailing 1-bits for odd nodes; 0 for even (leaves).
  int _level(int x) {
    if ((x & 1) == 0) return 0;
    var k = 0;
    while (((x >> k) & 1) == 1) k++;
    return k;
  }

  // RFC 9420 parent formula: (x | (1<<k)) ^ (b << (k+1))
  int _parentOf(int n) {
    final k = _level(n);
    final b = (n >> (k + 1)) & 1;
    return (n | (1 << k)) ^ (b << (k + 1));
  }

  List<int> _directPath(int leafIndex, int w) {
    final path = <int>[];
    var n = leafNodeIndex(leafIndex);
    final root = _rootIndex(w);
    while (n != root) {
      n = _parentOf(n);
      path.add(n);
    }
    return path;
  }

  List<int> _copath(int leafIndex, int w) {
    final path = <int>[];
    var n = leafNodeIndex(leafIndex);
    final root = _rootIndex(w);
    while (n != root) {
      final p = _parentOf(n);
      final lvl = _level(p);
      final left = p - (1 << (lvl - 1));
      final right = p + (1 << (lvl - 1));
      path.add(n == left ? right : left);
      n = p;
    }
    return path;
  }

  int _rootIndex(int w) {
    if (w <= 1) return 0;
    var p = 1;
    while (p < w) p <<= 1;
    return (p >> 1) - 1;
  }

  Uint8List? _resolve(int nodeIdx) {
    if (nodeIdx >= _nodes.length) return null;
    final node = _nodes[nodeIdx];
    if (!node.isBlank && node.hpkePk != null) return node.hpkePk;
    final lvl = _level(nodeIdx);
    if (lvl == 0) return null;
    final leftChild = nodeIdx - (1 << (lvl - 1));
    final rightChild = nodeIdx + (1 << (lvl - 1));
    return _resolve(leftChild) ?? _resolve(rightChild);
  }

  int addLeaf(Uint8List leafPk) {
    final leafIdx = _numLeaves;
    _numLeaves++;
    final totalNodes = 2 * _numLeaves - 1;
    while (_nodes.length < totalNodes) {
      _nodes.add(TreeNode(isBlank: true));
    }
    _nodes[leafNodeIndex(leafIdx)] = TreeNode(hpkePk: leafPk);
    if (_numLeaves > 1) {
      final w = totalNodes;
      for (final n in _directPath(leafIdx, w)) {
        if (n < _nodes.length) _nodes[n] = TreeNode(isBlank: true);
      }
    }
    return leafIdx;
  }

  void removeLeaf(int leafIdx) {
    final ni = leafNodeIndex(leafIdx);
    if (ni < _nodes.length) _nodes[ni] = TreeNode(isBlank: true);
    if (_numLeaves > 1) {
      for (final n in _directPath(leafIdx, 2 * _numLeaves - 1)) {
        if (n < _nodes.length) _nodes[n] = TreeNode(isBlank: true);
      }
    }
  }

  (CommitPath, Uint8List) commitPath(
      Crypto c, int myLeafIndex, Uint8List newLeafSecret, Uint8List groupContextBytes) {
    if (_numLeaves <= 1) {
      // Solo group: no path to compute
      final commitSecret = deriveSecret(c.hmac, newLeafSecret, 'path');
      return (CommitPath([]), commitSecret);
    }

    final w = 2 * _numLeaves - 1;
    final direct = _directPath(myLeafIndex, w);
    final copath = _copath(myLeafIndex, w);

    final pathNodes = <CommitPathNode>[];
    Uint8List pathSecret = newLeafSecret;

    for (var i = 0; i < direct.length; i++) {
      pathSecret = deriveSecret(c.hmac, pathSecret, 'path');
      // Node keypair is deterministically derived from pathSecret so all members
      // can verify the node pk from the CommitPath without storing the sk.
      final nodeSeed = deriveSecret(c.hmac, pathSecret, 'node');
      final seed96 = c.hkdf.derive(Uint8List(32), nodeSeed,
          Uint8List.fromList(utf8.encode('xwing-node-seed')), 96);
      final (nodePk, _) = c.xwing.keygenFromSeed(seed96);

      final nodeIdx = direct[i];
      if (nodeIdx < _nodes.length) _nodes[nodeIdx] = TreeNode(hpkePk: nodePk);

      final encPks = <HpkeCiphertext>[];
      if (i < copath.length) {
        final targetPk = _resolve(copath[i]);
        if (targetPk != null) {
          final (enc, ct, tag) =
              c.hpke.seal(targetPk, groupContextBytes, groupContextBytes, pathSecret);
          encPks.add(HpkeCiphertext(enc: enc, ct: ct, tag: tag));
        }
      }

      pathNodes.add(CommitPathNode(nodePk: nodePk, encryptedPathSecrets: encPks));
    }

    final commitSecret = deriveSecret(c.hmac, pathSecret, 'path');
    return (CommitPath(pathNodes), commitSecret);
  }

  Uint8List applyCommitPath(
      Crypto c,
      int senderLeafIdx,
      CommitPath path,
      int myLeafIdx,
      Uint8List myLeafSk,
      Uint8List groupContextBytes) {
    if (_numLeaves <= 1 || path.nodes.isEmpty) {
      return deriveSecret(c.hmac, Uint8List(32), 'path');
    }

    final w = 2 * _numLeaves - 1;
    final senderDirect = _directPath(senderLeafIdx, w);
    final senderCopath = _copath(senderLeafIdx, w);
    final myNodeIdx = leafNodeIndex(myLeafIdx);

    int? decryptLevel;
    for (var i = 0; i < senderCopath.length; i++) {
      if (_isInSubtree(myNodeIdx, senderCopath[i], w)) {
        decryptLevel = i;
        break;
      }
    }

    Uint8List pathSecret;
    if (decryptLevel == null) {
      pathSecret = Uint8List(32);
    } else {
      final node = path.nodes[decryptLevel];
      if (node.encryptedPathSecrets.isEmpty) {
        pathSecret = Uint8List(32);
      } else {
        final hpkeCt = node.encryptedPathSecrets.first;
        pathSecret = c.hpke.open(
            myLeafSk, hpkeCt.enc, groupContextBytes, groupContextBytes, hpkeCt.ct, hpkeCt.tag);
      }
    }

    var ps = pathSecret;
    final startLevel = (decryptLevel ?? -1) + 1;
    for (var i = startLevel; i < senderDirect.length; i++) {
      ps = deriveSecret(c.hmac, ps, 'path');
    }

    // Update parent PKs from CommitPath
    for (var i = 0; i < senderDirect.length && i < path.nodes.length; i++) {
      final nodeIdx = senderDirect[i];
      if (nodeIdx < _nodes.length) {
        _nodes[nodeIdx] = TreeNode(hpkePk: path.nodes[i].nodePk);
      }
    }

    return deriveSecret(c.hmac, ps, 'path');
  }

  bool _isInSubtree(int nodeIdx, int subtreeRoot, int w) {
    final lvl = _level(subtreeRoot);
    if (lvl == 0) return nodeIdx == subtreeRoot;
    final half = 1 << (lvl - 1);
    return nodeIdx >= subtreeRoot - half && nodeIdx <= subtreeRoot + half;
  }

  List<({bool isBlank, Uint8List? pk})> leafInfo() =>
      List.generate(_numLeaves, (i) {
        final ni = leafNodeIndex(i);
        if (ni < _nodes.length) return (isBlank: _nodes[ni].isBlank, pk: _nodes[ni].hpkePk);
        return (isBlank: true, pk: null);
      });

  Uint8List treeHash(Crypto c) {
    final buf = BytesBuilder();
    for (var i = 0; i < _numLeaves; i++) {
      final ni = leafNodeIndex(i);
      if (ni < _nodes.length && _nodes[ni].hpkePk != null) {
        buf.add(_nodes[ni].hpkePk!);
      } else {
        buf.add(Uint8List(32));
      }
    }
    return c.sha256.hash(buf.takeBytes());
  }
}
