// JSON keystore — long-lived identity + per-peer ratchet state.
//
// Layout on disk (<name>_keystore.json):
//   {
//     "name": "alice",
//     "identity": { ikDhSk, ikDhPk, ikSigSk, ikSigPk, spkDhSk, spkDhPk,
//                   spkKemSk, spkKemPk, spkSig },
//     "ratchets": { "<peer>": <RatchetState.toJson()>, ... }
//   }

import 'dart:convert';
import 'dart:io';
import 'ratchet.dart';

class Keystore {
  final String name;
  final Identity identity;
  final Map<String, RatchetState> ratchets;

  Keystore({
    required this.name,
    required this.identity,
    Map<String, RatchetState>? ratchets,
  }) : ratchets = ratchets ?? {};

  static String _filename(String name) => '${name}_keystore.json';

  /// Load existing keystore or generate a fresh one.
  static Future<Keystore> loadOrGenerate(String name) async {
    final f = File(_filename(name));
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final identity =
          await Identity.fromPrivateJson(name, j['identity'] as Map<String, dynamic>);
      final ratchets = <String, RatchetState>{};
      final rj = j['ratchets'] as Map<String, dynamic>? ?? {};
      for (final e in rj.entries) {
        ratchets[e.key] = RatchetState.fromJson(e.value as Map<String, dynamic>);
      }
      return Keystore(name: name, identity: identity, ratchets: ratchets);
    }
    final identity = await genIdentity(name);
    final ks = Keystore(name: name, identity: identity);
    await ks.save();
    return ks;
  }

  Future<void> save() async {
    final ratchetsJson = <String, dynamic>{};
    for (final e in ratchets.entries) {
      ratchetsJson[e.key] = await e.value.toJson();
    }
    final j = {
      'name': name,
      'identity': await identity.toPrivateJson(),
      'ratchets': ratchetsJson,
    };
    await File(_filename(name))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(j), flush: true);
  }
}
