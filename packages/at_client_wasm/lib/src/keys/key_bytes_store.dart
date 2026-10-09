import 'dart:typed_data';

abstract interface class KeyBytesStore {
  Future<Uint8List?> get(String atSign);
  Future<void> put(String atSign, Uint8List bytes);
  Future<void> delete(String atSign);
}

/// The credential id of the passkey that last unlocked an atSign's keys on
/// this device, kept beside its envelope.
abstract interface class CredentialHintStore {
  Future<Uint8List?> credentialId(String atSign);
  Future<void> putCredentialId(String atSign, Uint8List id);
}

class InMemoryKeyBytesStore implements KeyBytesStore {
  final Map<String, Uint8List> _store = {};

  @override
  Future<Uint8List?> get(String atSign) async {
    final bytes = _store[atSign];
    if (bytes == null) return null;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> put(String atSign, Uint8List bytes) async {
    _store[atSign] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String atSign) async {
    _store.remove(atSign);
  }
}
