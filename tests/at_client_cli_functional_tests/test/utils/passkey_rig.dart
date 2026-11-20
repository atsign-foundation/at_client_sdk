import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart'
    show AESKey, AesGcm256EncryptionAlgo, HkdfSha256, InitialisationVector;
import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart' show InMemoryAtClientStorage;
import 'package:at_client/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_lookup/at_lookup_io.dart';

import 'virtualenv_ports.dart';

/// The virtualenv's atDirectory.
AtRootDomain get veRoot =>
    AtRootDomain('vip.ve.atsign.zone', virtualenvRootPort);

/// One line on the wire: a command a connection sent, or a line it received.
typedef WireLine = ({int connection, bool sent, String text, DateTime at});

/// Opens every connection over TLS, numbering them from 0, and keeps each
/// command sent and each line received.
///
/// [dropOn] cuts the network instead of sending the first command it
/// matches, as a process that loses its network there does: that command and
/// every later one never reach the atServer, each write throws
/// [AtIOException], and each connect throws [SecondaryConnectException] until
/// [severed] is cleared, as [AtTransport.add] and [AtTransportFactory.connect]
/// promise.
class WireTap implements AtTransportFactory {
  final AtTransportFactory _inner =
      SecureSocketTransportFactory(secureSocketConfig: SecureSocketConfig());

  final lines = <WireLine>[];

  /// The commands the cut network dropped.
  final dropped = <String>[];

  bool Function(String command)? dropOn;

  /// Runs after each line, sent or received, is added to [lines].
  void Function()? onLine;

  void _add(WireLine line) {
    lines.add(line);
    onLine?.call();
  }

  /// Whether the network is cut.
  var severed = false;

  var _connections = 0;

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    if (severed) {
      throw SecondaryConnectException(
          'network cut, as the test arranged: $host:$port');
    }
    return _Tapped(this, _connections++,
        await _inner.connect(host, port, timeout: timeout));
  }

  /// Every command sent, in order.
  List<WireLine> get sent => [
        for (final l in lines)
          if (l.sent) l
      ];

  /// The first line connection [connection] received after line [after].
  WireLine? replyTo(int after, int connection) {
    for (var i = after + 1; i < lines.length; i++) {
      final l = lines[i];
      if (!l.sent && l.connection == connection && l.text.contains(':')) {
        return l;
      }
    }
    return null;
  }

  /// The index in [lines] of the first command sent at or after [from] that
  /// [matches], or -1.
  int indexOfSent(bool Function(String command) matches, {int from = 0}) {
    for (var i = from; i < lines.length; i++) {
      if (lines[i].sent && matches(lines[i].text)) return i;
    }
    return -1;
  }

  /// [lines] as text, one per line, for a failure message.
  String transcript() => [
        for (final l in lines)
          '${l.connection}${l.sent ? '>' : '<'} ${_clip(l.text)}'
      ].join('\n');

  static String _clip(String s) =>
      s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

class _Tapped implements AtTransport {
  _Tapped(this._tap, this._id, this._inner) {
    _in = _inner.inbound.map((bytes) {
      _received(bytes);
      return bytes;
    });
  }

  final WireTap _tap;
  final int _id;
  final AtTransport _inner;
  late final Stream<List<int>> _in;
  var _partial = '';

  void _received(List<int> bytes) {
    final text = _partial + utf8.decode(bytes, allowMalformed: true);
    final parts = text.split('\n');
    _partial = parts.removeLast();
    for (final line in parts) {
      _tap._add((connection: _id, sent: false, text: line, at: DateTime.now()));
    }
  }

  @override
  Stream<List<int>> get inbound => _in;

  @override
  void add(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trimRight();
    final drop = _tap.dropOn;
    if (!_tap.severed && drop != null && drop(text)) {
      _tap
        ..severed = true
        ..dropOn = null;
    }
    if (_tap.severed) {
      _tap.dropped.add(text);
      _inner.destroy();
      throw AtIOException('network cut, as the test arranged');
    }
    _tap._add((connection: _id, sent: true, text: text, at: DateTime.now()));
    _inner.add(bytes);
  }

  @override
  Future<void> flush() => _inner.flush();

  @override
  void destroy() => _inner.destroy();

  @override
  bool get isOpen => _inner.isOpen;

  @override
  String get description => _inner.description;
}

/// A platform's passkeys: each registration makes a credential whose PRF
/// output is fixed by [salt] and its id, and an assertion answers for the
/// last one registered unless it is narrowed to another.
class VePasskeyPort implements PasskeyPort, UnknownCredentialSignal {
  VePasskeyPort(this.salt);

  /// A port holding only [credentialId], whose PRF output is [prf].
  VePasskeyPort.holding(Uint8List credentialId, Uint8List prf) : salt = 0 {
    credentials[credentialId.single] = prf;
    current = credentialId.single;
  }

  final int salt;

  /// The PRF output of each credential, by its one-byte id.
  final credentials = <int, Uint8List>{};
  int? current;

  /// The credentials the platform was told are unknown.
  final signalled = <Uint8List>[];

  @override
  Future<PasskeyCreation> create(
      {required String atSign,
      required DateTime enrolledAt,
      required String deviceName}) async {
    final id = credentials.length + 1;
    credentials[id] = Uint8List.fromList(
        List.generate(32, (i) => (i * 13 + id * 29 + salt * 7) & 0xff));
    current = id;
    return (credentialId: Uint8List.fromList([id]), prfEnabled: true);
  }

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    final id = allowCredential?.single ?? current;
    final prf = credentials[id];
    if (id == null || prf == null) {
      throw PasskeyCeremonyException('NotAllowedError');
    }
    return (
      credentialId: Uint8List.fromList([id]),
      prfFirst: Uint8List.fromList(prf)
    );
  }

  @override
  Future<void> signalUnknownCredential(Uint8List credentialId) async =>
      signalled.add(credentialId);
}

/// A device's passkey hints, in memory.
class MemoryHints implements PasskeyHintStore {
  final credentials = <String, Uint8List>{};
  final ids = <String, String>{};

  @override
  Future<Uint8List?> credentialId(String atSign) async => credentials[atSign];

  @override
  Future<void> putCredentialId(String atSign, Uint8List id) async =>
      credentials[atSign] = id;

  @override
  Future<String?> enrollmentId(String atSign) async => ids[atSign];

  @override
  Future<void> putEnrollmentId(String atSign, String id) async =>
      ids[atSign] = id;

  @override
  Future<void> putHint(
      String atSign, Uint8List credentialId, String enrollmentId) async {
    credentials[atSign] = credentialId;
    ids[atSign] = enrollmentId;
  }
}

/// A setup lock over one process: runs of one name take turns.
class LocalSetupLock implements SetupLock {
  final _tails = <String, Future<void>>{};

  @override
  Future<T> run<T>(String name, Future<T> Function() body) async {
    final before = _tails[name] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[name] = done.future;
    await before;
    try {
      return await body();
    } finally {
      done.complete();
    }
  }
}

/// A [RecordSealer] over AES-GCM-256 with a raw key held in memory.
class _AesGcmSealer implements RecordSealer {
  /// Takes ownership of [key]: [close] zeroes it. Each call builds the
  /// at_chops algo from the key's base64, a `String` nothing can zero.
  _AesGcmSealer(Uint8List key) : _key = key;

  final Uint8List _key;
  bool _closed = false;

  AesGcm256EncryptionAlgo get _algo {
    if (_closed) throw StateError('_AesGcmSealer is closed');
    return AesGcm256EncryptionAlgo(AESKey(base64Encode(_key)));
  }

  @override
  Future<Uint8List> seal(
          Uint8List iv, List<int> plaintext, List<int> aad) async =>
      _algo.encrypt(Uint8List.fromList(plaintext),
          iv: InitialisationVector(iv), aad: aad);

  @override
  Future<Uint8List> open(
      Uint8List iv, Uint8List ciphertext, List<int> aad) async {
    final algo = _algo;
    try {
      return await algo.decrypt(ciphertext,
          iv: InitialisationVector(iv), aad: aad);
    } on AtDecryptionException {
      throw PasskeyRecordAuthenticationException();
    }
  }

  @override
  void close() {
    _closed = true;
    _key.fillRange(0, _key.length, 0);
  }
}

/// A [PasskeyKeyDeriver] over HKDF-SHA256 (empty salt, info
/// `<label>|<canonical atSign>`), as the browser's derives with WebCrypto.
class HkdfPasskeyKeyDeriver implements PasskeyKeyDeriver {
  const HkdfPasskeyKeyDeriver();

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final canonical = atSign.toAtsign();
    Uint8List expand(String label) => HkdfSha256.deriveKey(prf.output,
        info: utf8.encode('$label|$canonical'), length: 32);
    String hexOf(String label) {
      final bytes = expand(label);
      try {
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }

    final derivation = (
      lookupHex: hexOf(recordIdLabel),
      ns: hexOf(recordNsLabel),
      authSeed: expand(recordAuthSeedLabel),
      sealer: _AesGcmSealer(expand(recordSealLabel)) as RecordSealer,
    );
    prf.wipe();
    return derivation;
  }
}

/// The vault and pointer name a passkey whose PRF output is [prf] derives
/// for [atSign]; the caller closes the vault.
Future<({PasskeyVault vault, String lookupHex, String ns, Uint8List authSeed})>
    deriveFor(Uint8List prf, String atSign) async {
  final derivation = await const HkdfPasskeyKeyDeriver()
      .derive(PrfSecret(Uint8List.fromList(prf)), atSign);
  return (
    vault: PasskeyVault(derivation, atSign: atSign),
    lookupHex: derivation.lookupHex,
    ns: derivation.ns,
    authSeed: Uint8List.fromList(derivation.authSeed),
  );
}

/// A browser's passkey custody, against the virtualenv, with every
/// connection through [tap] and the client the browser opens.
class PasskeyRig {
  PasskeyRig({int salt = 0, VePasskeyPort? port})
      : port = port ?? VePasskeyPort(salt);

  final tap = WireTap();
  final VePasskeyPort port;
  final setupLock = LocalSetupLock();

  late final SecondaryAddressFinder finder =
      CacheableSecondaryAddressFinder(veRoot.rootDomain, veRoot.rootPort);

  AtLookUpFactory get lookUps => (
          {required String atSign,
          required AtRootDomain rootDomain,
          required AtAuthenticator? authenticator,
          SecondaryAddressFinder? secondaryAddressFinder}) =>
      AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: rootDomain,
          authenticator: authenticator,
          transport: AtLookupTransport(transportFactory: tap),
          secondaryAddressFinder: secondaryAddressFinder ?? finder);

  /// What the browser's session opener does, against the virtualenv.
  Future<AtClient> openClient(
      {required AtLookupMuxable lookUp,
      required String atSign,
      required String enrollmentId,
      required WrittenAtKeysIo keysIo}) async {
    final client = await Atsign(atSign).open(
        keys: keysIo,
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..rootDomain = veRoot.rootDomain
          ..rootPort = veRoot.rootPort
          ..remoteLocalPref = RemoteLocalPref.remoteOnly
          ..monitorAutoStart = false,
        namespace: 'wavi',
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
        atLookUp: lookUp,
        lookUps: lookUps,
        secondaryAddressFinder: finder);
    if (!client.connection.current.isOnline) {
      await client.stop();
      throw StateError('the client of $atSign opened offline');
    }
    return client;
  }

  AtAuthEnrollmentGateway gateway() => AtAuthEnrollmentGateway(
      lookUps: lookUps,
      finder: finder,
      root: veRoot,
      app: 'wavi',
      device: 'vetest',
      clientOpener: openClient);

  /// A custody over [gateway], by default this rig's own.
  PasskeyCustody custody(
      {PasskeyHintStore? hints, EnrollmentGateway? gateway}) {
    final store = hints ?? MemoryHints();
    return PasskeyCustody(
        prf: PasskeyPrf(port),
        deriver: const HkdfPasskeyKeyDeriver(),
        pointerReader: LookupEnrollmentPointerReader(
            lookUps: lookUps,
            rootDomain: veRoot,
            secondaryAddressFinder: finder),
        gateway: gateway ?? this.gateway(),
        credentials: store,
        enrollmentIds: store,
        setupLock: setupLock,
        setupLockPrefix: 'vetest:setup');
  }

  /// The PRF output of the credential the port answers for now.
  Uint8List get currentPrf => port.credentials[port.current]!;

  /// The enrollment id the pointer of the passkey whose PRF is [prf] names.
  Future<String> pointedEnrollmentId(String atSign, Uint8List prf) async {
    final keys = await deriveFor(prf, atSign);
    try {
      final pointer = await LookupEnrollmentPointerReader(
              lookUps: lookUps,
              rootDomain: veRoot,
              secondaryAddressFinder: finder)
          .get(atSign, keys.lookupHex, ns: keys.ns);
      if (pointer == null) throw StateError('no pointer for $atSign');
      return (await keys.vault
          .open(PasskeyRecordType.eid, pointer))['enrollmentId'] as String;
    } finally {
      keys.vault.close();
    }
  }

  /// The @keys document of [enrollmentId] as the atServer holds it, read on
  /// a connection of its own and opened with the passkey whose PRF is [prf].
  Future<Map<String, dynamic>> storedDocument(
      String atSign, String enrollmentId, Uint8List prf) async {
    final keys = await deriveFor(prf, atSign);
    try {
      final session = await gateway().authenticate(
          atSign: atSign,
          enrollmentId: enrollmentId,
          apkamKeyPair: await apkamKeyPairFromSeed(keys.authSeed));
      try {
        final sealed = await session.documents.get(atSign, enrollmentId);
        if (sealed == null) throw StateError('no document for $enrollmentId');
        return await keys.vault.open(PasskeyRecordType.atkeys, sealed);
      } finally {
        await session.close();
      }
    } finally {
      keys.vault.close();
    }
  }
}

/// The reply [atSign]'s atServer gives an unauthenticated `lookup` of its
/// public record [key]: a value as `data:...`, or the error text.
Future<String> publicLookupReply(String atSign, String key) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign, rootDomain: veRoot, authenticator: null);
  try {
    return '${await lookUp.executeCommand('lookup:$key$atSign\n')}';
  } on Exception catch (e) {
    return '$e';
  } finally {
    await lookUp.close();
  }
}
