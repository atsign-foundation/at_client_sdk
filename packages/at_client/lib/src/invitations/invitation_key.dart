import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart'
    show AESKey, AesGcm256EncryptionAlgo, InitialisationVector;
import 'package:meta/meta.dart' show experimental;

import 'package:at_client/src/invitations/models.dart';

/// An invitation's content key: AES-256-GCM, minted when the invitation is
/// created and released to the invitee only once they have accepted.
@experimental
class InvitationKey {
  final AESKey _key;

  InvitationKey._(this._key);

  /// Mints a fresh random key.
  factory InvitationKey.mint() => InvitationKey._(AESKey.generate(32));

  /// The key as it travels in a [InvitationConnection].
  factory InvitationKey.fromBase64(String key) => InvitationKey._(AESKey(key));

  String get base64 => _key.key;

  /// Encrypts [plaintext], bound to the invitation it belongs to.
  Future<SealedInvitationContent> seal(
    String plaintext, {
    required String inviter,
    required String invitationId,
  }) async {
    final iv = InitialisationVector.random(12);
    final ciphertext = await AesGcm256EncryptionAlgo(_key).encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
      iv: iv,
      aad: _aad(inviter, invitationId),
    );
    return SealedInvitationContent(
      nonce: base64Encode(iv.ivBytes),
      ciphertext: base64Encode(ciphertext),
    );
  }

  /// Decrypts [content], refusing content bound to any other invitation.
  Future<String> open(
    SealedInvitationContent content, {
    required String inviter,
    required String invitationId,
  }) async {
    final plaintext = await AesGcm256EncryptionAlgo(_key).decrypt(
      base64Decode(content.ciphertext),
      iv: InitialisationVector(base64Decode(content.nonce)),
      aad: _aad(inviter, invitationId),
    );
    return utf8.decode(plaintext);
  }

  static Uint8List _aad(String inviter, String invitationId) =>
      Uint8List.fromList(utf8.encode('$inviter/$invitationId'));
}
