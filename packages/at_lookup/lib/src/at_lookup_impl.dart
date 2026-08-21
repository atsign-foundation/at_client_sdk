// ignore_for_file: unused_field, deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart' show AtUtils;
import 'package:mutex/mutex.dart';
import 'package:at_chops/at_chops.dart';

/// The `from:` challenge an atServer issues a client, once the `data:` prefix
/// is stripped: `_<uuid><atSign>:<uuid>`.
///
final RegExp _fromChallengeUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// Returns [challenge] when it is a well-formed `from:` challenge issued to
/// [atSign]; throws [UnAuthenticatedException] otherwise.
///
/// [challenge] is the response with any `data:` prefix already stripped.
///
/// Public, not `@visibleForTesting`: authentication is moving out of at_lookup
/// and into at_auth, where the key material is, and the side that signs the
/// challenge is the side that has to refuse a bad one. Duplicating this check
/// there would be the worse answer - two copies of a security control drift,
/// and the one that drifts is the one nobody is looking at.
String validatedFromChallenge(String challenge, String atSign) {
  void refuse(String why) {
    // The challenge itself is not secret — it is a session id and a nonce the
    // server just sent in clear — and naming what arrived is what makes a
    // genuine protocol mismatch diagnosable rather than a silent auth failure.
    throw UnAuthenticatedException(
        'Refusing to sign a malformed from: challenge for $atSign ($why). '
        'Expected `_<uuid><atSign>:<uuid>`, got "$challenge"');
  }

  final int lastColon = challenge.lastIndexOf(':');
  if (lastColon <= 0) {
    refuse('no proof separator');
  }
  if (!_fromChallengeUuid.hasMatch(challenge.substring(lastColon + 1))) {
    refuse('the proof is not a uuid');
  }

  // The atSign this client asked for has to be the one the challenge names, so
  // a challenge minted for somebody else cannot be replayed through it.
  final String head = challenge.substring(0, lastColon);
  final String expected = AtUtils.fixAtSign(atSign);
  if (!head.endsWith(expected)) {
    refuse('it does not name $expected');
  }

  final String sessionId = head.substring(0, head.length - expected.length);
  if (!sessionId.startsWith('_') ||
      !_fromChallengeUuid.hasMatch(sessionId.substring(1))) {
    refuse('the session id is not `_<uuid>`');
  }

  return challenge;
}

class AtLookupImpl implements AtLookUp, AtCommandExecutor, AtLookupMuxable {
  final logger = AtSignLogger('AtLookup');

  /// Listener for reading verb responses from the remote server
  late OutboundMessageListener messageListener;

  OutboundConnection? _connection;

  @override
  OutboundConnection? get connection => _connection;

  @override
  late SecondaryAddressFinder secondaryAddressFinder;

  late String _currentAtSign;

  late String _rootDomain;

  late int _rootPort;

  /// The legacy PKAM credential: a private key and nothing else.
  ///
  /// The message this annotation used to carry - "privateKey reference is no
  /// longer used" - was false. The ladder in [_process] reads this field and
  /// calls authenticate() with it, and before the authenticator seam landed
  /// that was the leg most ladder traffic took.
  @Deprecated('Pass an AtAuthenticator to AtLookUp.withSecureSocket '
      'instead - at_auth builds one from a bare private key with '
      'authenticatorForPrivateKey(). '
      'Removed with the credential ladder in the next major release.')
  String? privateKey;

  @Deprecated('Pass an AtAuthenticator to AtLookUp.withSecureSocket '
      'instead - at_auth builds one that falls back to CRAM with '
      'authenticatorFor(). '
      'Removed with the credential ladder in the next major release.')
  String? cramSecret;

  /// Takes over authentication entirely when set, in place of the
  /// atChops/privateKey/cramSecret ladder below.
  ///
  /// The ladder asks "which credential do I hold?" in at_lookup, which is the
  /// wrong place to ask: at_lookup cannot see an enrollment, a keystore or a
  /// signing algorithm, so every credential it might use has to be handed to
  /// it and stored here first. A caller that sets this hands over one closure
  /// instead, and keeps all of that on its own side. See [AtAuthenticator].
  ///
  /// Both routes work while this exists. The ladder and the fields feeding it
  /// go once every caller supplies an authenticator.
  @override
  AtAuthenticator? authenticator;

  /// Permitted number of milliseconds before connection to atServer
  /// is deemed 'idle' and will be closed. The default is usually set to
  /// 10 minutes i.e. 600,000 milliseconds
  int? outboundConnectionTimeout;

  late SecureSocketConfig _secureSocketConfig;

  late final AtLookupSecureSocketFactory socketFactory;

  late final AtLookupSecureSocketListenerFactory socketListenerFactory;

  late AtLookupOutboundConnectionFactory outboundConnectionFactory;

  /// Represents the client configurations.
  late Map<String, dynamic> _clientConfig;

  // Holds what the deprecated `atChops` accessors set. The type cannot leave
  // while those accessors are part of this class's API, so it goes when the
  // credential ladder does.
  // TODO(4.0): remove with the credential ladder.
  // ignore: deprecated_member_use
  AtChops? _atChops;

  /// Prefer [AtLookUp.withSecureSocket].
  ///
  /// This takes a `String, int` root pair where [AtRootDomain] validates the
  /// port and knows about proxy addresses, it accepts key material at_lookup
  /// no longer needs, and it hands back a concrete type where a caller only
  /// ever needs an interface.
  ///
  /// The warnings this raises at every construction site ARE the deliverable:
  /// they are the mechanical list of what still has to move. `dart analyze`
  /// reports them as `info`, so nothing breaks while the list is worked
  /// through.
  @Deprecated('Use AtLookUp.withSecureSocket, which returns an '
      'AtLookupMuxable. Removed in the next major release.')
  AtLookupImpl(String atSign, String rootDomain, int rootPort,
      {this.privateKey,
      this.cramSecret,
      SecondaryAddressFinder? secondaryAddressFinder,
      SecureSocketConfig? secureSocketConfig,
      Map<String, dynamic>? clientConfig,
      AtLookupSecureSocketFactory? secureSocketFactory,
      AtLookupSecureSocketListenerFactory? socketListenerFactory,
      AtLookupOutboundConnectionFactory? outboundConnectionFactory}) {
    _currentAtSign = atSign;
    _rootDomain = rootDomain;
    _rootPort = rootPort;
    this.secondaryAddressFinder = secondaryAddressFinder ??
        CacheableSecondaryAddressFinder(rootDomain, rootPort);
    _secureSocketConfig = secureSocketConfig ?? SecureSocketConfig();
    // Stores the client configurations.
    // If client configurations are not available, defaults to empty map
    _clientConfig = clientConfig ?? {};
    socketFactory = secureSocketFactory ?? AtLookupSecureSocketFactory();
    this.socketListenerFactory =
        socketListenerFactory ?? AtLookupSecureSocketListenerFactory();
    this.outboundConnectionFactory =
        outboundConnectionFactory ?? AtLookupOutboundConnectionFactory();
  }

  @Deprecated('use CacheableSecondaryAddressFinder')
  static Future<String?> findSecondary(
      String atsign, String? rootDomain, int rootPort) async {
    // temporary change to preserve backward compatibility and change the callers later on to use
    // SecondaryAddressFinder.findSecondary
    return (await CacheableSecondaryAddressFinder(rootDomain!, rootPort)
            .findSecondary(atsign))
        .toString();
  }

  @override
  Future<bool> delete(String key,
      {String? sharedWith, bool isPublic = false}) async {
    var builder = DeleteVerbBuilder()
      ..atKey = (AtKey()
        ..key = key
        ..sharedWith = sharedWith
        ..sharedBy = _currentAtSign
        ..metadata = (Metadata()..isPublic = isPublic));
    var deleteResult = await executeVerb(builder);
    return deleteResult.isNotEmpty; //replace with call back
  }

  @override
  Future<String> llookup(String key,
      {String? sharedBy, String? sharedWith, bool isPublic = false}) async {
    LLookupVerbBuilder builder;
    if (sharedWith != null) {
      builder = LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = key
          ..sharedBy = _currentAtSign
          ..sharedWith = sharedWith
          ..metadata = (Metadata()..isPublic = isPublic));
    } else if (isPublic && sharedBy == null && sharedWith == null) {
      builder = LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'public:$key'
          ..sharedBy = _currentAtSign);
    } else {
      builder = LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = key
          ..sharedBy = _currentAtSign);
    }
    var llookupResult = await executeVerb(builder);
    llookupResult = VerbUtil.getFormattedValue(llookupResult);
    return llookupResult;
  }

  @override
  Future<String> lookup(String key, String sharedBy,
      {bool auth = true,
      bool verifyData = false,
      bool metadata = false}) async {
    var builder = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = key
        ..sharedBy = sharedBy)
      ..auth = auth
      ..operation = metadata == true ? 'all' : null;
    if (verifyData == false) {
      var lookupResult = await executeVerb(builder);
      lookupResult = VerbUtil.getFormattedValue(lookupResult);
      return lookupResult;
    }
    //verify data signature if verifyData is set to true
    try {
      builder = LookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = key
          ..sharedBy = sharedBy)
        ..auth = false
        ..operation = 'all';
      String? lookupResult = await executeVerb(builder);
      lookupResult = lookupResult.replaceFirst(RegExp(r'^data:'), '');
      var resultJson = json.decode(lookupResult);
      logger.finer(resultJson);

      String? publicKeyResult = '';
      if (auth) {
        publicKeyResult = await plookup('publickey', sharedBy);
      } else {
        var publicKeyLookUpBuilder = LookupVerbBuilder()
          ..atKey = (AtKey()
            ..key = 'publickey'
            ..sharedBy = sharedBy);
        publicKeyResult = await executeVerb(publicKeyLookUpBuilder);
      }
      publicKeyResult = publicKeyResult.replaceFirst(RegExp(r'^data:'), '');
      logger.finer('public key of $sharedBy :$publicKeyResult');

      var dataSignature = resultJson['metaData']['dataSignature'];
      var value = resultJson['data'];
      value = VerbUtil.getFormattedValue(value);
      logger.finer('value: $value dataSignature:$dataSignature');
      // RSA SHA-256 verify via at_chops (wraps the same crypton
      // RSAPublicKey.verifySHA256Signature).
      // TODO(4.0): not part of the credential ladder, so this one outlives
      // it. at_chops directs it to RsaSignatureAlgo — but that class pins a
      // modulus size per instance, and this verifies a PEER's key, whose
      // size we do not control: rsa2048() returns false for a 4096-bit key
      // that verifies here today. Choose the instance by the key, or keep a
      // size-agnostic verify.
      // ignore: deprecated_member_use
      var isDataValid = PkamSigningAlgo(null, HashingAlgoType.sha256).verify(
          Uint8List.fromList(utf8.encode(value)), base64Decode(dataSignature),
          publicKey: publicKeyResult);
      logger.finer('data verify result: $isDataValid');
      return 'data:$value';
    } on Exception catch (e) {
      logger.severe(
          'Error while verify public data for key: $key sharedBy: $sharedBy exception:${e.toString()}');
      return 'data:null';
    }
  }

  @override
  Future<String> plookup(String key, String sharedBy) async {
    var builder = PLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = key
        ..sharedBy = sharedBy);
    var plookupResult = await executeVerb(builder);
    plookupResult = VerbUtil.getFormattedValue(plookupResult);
    return plookupResult;
  }

  @override
  Future<List<String>> scan(
      {String? regex,
      String? sharedBy,
      bool auth = true,
      bool showHiddenKeys = false}) async {
    var builder = ScanVerbBuilder()
      ..sharedBy = sharedBy
      ..regex = regex
      ..auth = auth
      ..showHiddenKeys = showHiddenKeys;
    var scanResult = await executeVerb(builder);
    if (scanResult.isNotEmpty) {
      scanResult = scanResult.replaceFirst(RegExp(r'^data:'), '');
    }
    return (scanResult.isNotEmpty) ? List.from(jsonDecode(scanResult)) : [];
  }

  @override
  Future<bool> update(String key, String value,
      {String? sharedWith, Metadata? metadata}) async {
    var builder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = key
        ..sharedBy = _currentAtSign
        ..sharedWith = sharedWith)
      ..value = value;
    if (metadata != null) {
      builder.atKey.metadata = metadata;
      if (metadata.isHidden) {
        builder.atKey.key = '_$key';
      }
    }
    var putResult = await executeVerb(builder);
    return putResult.isNotEmpty;
  }

  Future<void> createConnection() async {
    if (!isConnectionAvailable()) {
      if (_connection != null) {
        // Clean up the connection before creating a new one
        logger.finer('Closing old connection');
        await _closeConnection();
      }
      logger.info('Creating new connection');
      //1. find secondary url for atsign from lookup library
      SecondaryAddress secondaryAddress =
          await secondaryAddressFinder.findSecondary(_currentAtSign);
      var host = secondaryAddress.host;
      var port = secondaryAddress.port;
      //2. create a connection to secondary server
      await createOutBoundConnection(
          host, port.toString(), _currentAtSign, _secureSocketConfig);
      //3. listen to server response
      messageListener = socketListenerFactory.createListener(_connection!);
      // Re-established on every connection, because createConnection builds a
      // fresh listener each time. Installed only when somebody has asked for
      // the stream: with no controller there is nowhere to put a notification,
      // and routing one into a void drops it silently.
      if (_notificationController != null) {
        messageListener.onNotification = _routeNotification;
        messageListener.onDisconnect = _onNotificationConnectionLost;
      }
      messageListener.listen();
      logger.info('New connection created OK');
    }
  }

  /// Executes the command returned by [VerbBuilder] build command on a remote secondary server.
  /// Catches any exception and throws [AtLookUpException]
  @override
  Future<String> executeVerb(VerbBuilder builder,
      {@Deprecated('Inert: nothing reads it. The verb always executes '
          'on the remote atServer; there is no sync behaviour here '
          'to control. Removed in 4.0.')
      sync = false}) async {
    String verbResult = '';
    try {
      if (builder is UpdateVerbBuilder) {
        verbResult = await _update(builder);
      } else if (builder is DeleteVerbBuilder) {
        verbResult = await _delete(builder);
      } else if (builder is LookupVerbBuilder) {
        verbResult = await _lookup(builder);
      } else if (builder is LLookupVerbBuilder) {
        verbResult = await _llookup(builder);
      } else if (builder is PLookupVerbBuilder) {
        verbResult = await _plookup(builder);
      } else if (builder is ScanVerbBuilder) {
        verbResult = await _scan(builder);
      } else if (builder is StatsVerbBuilder) {
        verbResult = await _stats(builder);
      } else if (builder is ConfigVerbBuilder) {
        verbResult = await _config(builder);
      } else if (builder is NotifyVerbBuilder) {
        verbResult = await _notify(builder);
      } else if (builder is NotifyStatusVerbBuilder) {
        verbResult = await _notifyStatus(builder);
      } else if (builder is NotifyListVerbBuilder) {
        verbResult = await _notifyList(builder);
      } else if (builder is NotifyAllVerbBuilder) {
        verbResult = await _notifyAll(builder);
      } else if (builder is SyncVerbBuilder) {
        verbResult = await _sync(builder);
      } else if (builder is NotifyRemoveVerbBuilder) {
        verbResult = await _notifyRemove(builder);
      } else if (builder is NotifyFetchVerbBuilder) {
        verbResult = await _notifyFetch(builder);
      } else if (builder is EnrollVerbBuilder) {
        verbResult = await _enroll(builder);
      }
    } on Exception catch (e) {
      logger.severe('Error in remote verb execution ${e.toString()}');
      var errorCode = AtLookUpExceptionUtil.getErrorCode(e);
      throw AtLookUpException(errorCode, e.toString());
    }
    return _verbResponseHandler(verbResult);
  }

  String _verbResponseHandler(String verbResult) {
    // If connection time-out, do not return empty verbResult;
    // throw AtLookupException.
    if (verbResult.isEmpty) {
      throw AtLookUpException('AT0014', 'Request timed out');
    }
    // Response starting with "data:", represents successfully processing of verb
    // return the response.
    if (verbResult.startsWith('data:')) {
      return verbResult;
    }
    if (verbResult.startsWith('error:')) {
      _errorResponseHandler(verbResult);
    }
    return verbResult;
  }

  void _errorResponseHandler(String verbResult) {
    verbResult = verbResult.replaceFirst(RegExp('^error:'), '');
    // Setting the errorCode and errorDescription to default values.
    var errorCode = 'AT0014';
    var errorDescription = 'Unknown server error';
    try {
      var errorMap = jsonDecode(verbResult);
      errorCode = errorMap['errorCode'];
      errorDescription = errorMap['errorDescription'];
    } on FormatException {
      // Catching the FormatException to preserve backward compatibility - responses without jsonEncoding.
      // TODO: Can we remove the below catch block in next release once all the servers are migrated to new version.
      if (verbResult.contains('-')) {
        errorCode = verbResult.substring(0, verbResult.indexOf('-'));
        errorDescription = verbResult.substring(verbResult.indexOf('-') + 1);
      } else {
        errorDescription += ": $verbResult";
      }
    }

    throw AtLookUpException(errorCode, errorDescription);
  }

  Future<String> _update(UpdateVerbBuilder builder) async {
    String atCommand;
    if (builder.operation == AtConstants.updateMeta) {
      atCommand = builder.buildCommandForMeta();
    } else {
      atCommand = builder.buildCommand();
    }
    logger.finer('update to remote: $atCommand');
    return await _process(atCommand, auth: true);
  }

  Future<String> _notify(NotifyVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    logger.finer('notify to remote: $atCommand');
    return await _process(atCommand, auth: true);
  }

  Future<String> _scan(ScanVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: builder.auth);
  }

  Future<String> _stats(StatsVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _config(ConfigVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _notifyStatus(NotifyStatusVerbBuilder builder) async {
    var command = builder.buildCommand();
    return await _process(command, auth: true);
  }

  Future<String> _notifyList(NotifyListVerbBuilder builder) async {
    var command = builder.buildCommand();
    return await _process(command, auth: true);
  }

  Future<String> _notifyAll(NotifyAllVerbBuilder builder) async {
    var command = builder.buildCommand();
    return await _process(command, auth: true);
  }

  Future<String> _notifyRemove(NotifyRemoveVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _notifyFetch(NotifyFetchVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _sync(SyncVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _enroll(EnrollVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    if (builder.operation == EnrollOperationEnum.request) {
      return _process(atCommand, auth: false);
    }
    return await _process(atCommand, auth: true);
  }

  @override
  Future<String?> executeCommand(String atCommand, {bool auth = false}) async {
    String verbResponse = await _process(atCommand, auth: auth);
    return _verbResponseHandler(verbResponse);
  }

  /// Records on the connection the identity it has just authenticated as, so
  /// a later caller can tell which enrollment a live socket holds rather than
  /// which one the next authentication would use.
  void _recordAuthentication({String? enrollmentId}) {
    final metaData = _connection!.getMetaData()!;
    metaData.isAuthenticated = true;
    metaData.authenticatedAsEnrollmentId = enrollmentId;
    metaData.authenticatedAt = DateTime.now().toUtc();
  }

  final Mutex _pkamAuthenticationMutex = Mutex();

  @override
  Future<String> readResponse(
          {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) =>
      messageListener.read(
          maxWaitMilliSeconds: maxWaitMilliSeconds,
          transientWaitTimeMillis: transientWaitTimeMillis);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    await _sendCommand(command);
    return messageListener.read(
        maxWaitMilliSeconds: maxWaitMilliSeconds,
        transientWaitTimeMillis: transientWaitTimeMillis);
  }

  /// Runs [authenticate] against this connection, under the same mutex the
  /// ladder's own methods take.
  ///
  /// [enrollmentId] is what gets recorded on the connection. It is a parameter
  /// rather than always this object's field because the two can differ: a
  /// caller reaching [pkamAuthenticate] names the enrollment in that call,
  /// while a verb going through [_process] has only the field to go on.
  Future<void> _authenticateWith(AtAuthenticator authenticate,
      {String? enrollmentId}) async {
    await createConnection();
    try {
      await _pkamAuthenticationMutex.acquire();
      if (_connection!.getMetaData()!.isAuthenticated) {
        return;
      }
      if (!await authenticate(this)) {
        throw UnAuthenticatedException(
            'Failed connecting to $_currentAtSign.'
            ' The authenticator reported failure');
      }
      // The enrollment id still comes from the caller or this object, because
      // the ladder still needs the field. When the ladder goes, so does the
      // field, and the authenticator - which is the side that knows the
      // enrollment - becomes the only thing that can supply it.
      _recordAuthentication(enrollmentId: enrollmentId ?? this.enrollmentId);
    } finally {
      _pkamAuthenticationMutex.release();
    }
  }

  /// Generates digest using from verb response and [privateKey] and performs a PKAM authentication to
  /// secondary server. This method is executed for all verbs that requires authentication.
  /// @Deprecated('Use method pkamAuthenticate') Commenting deprecation since it causes issue in dart analyze in the caller
  Future<bool> authenticate(String? privateKey) async {
    if (privateKey == null) {
      throw UnAuthenticatedException('Private key not passed');
    }
    await createConnection();
    try {
      await _pkamAuthenticationMutex.acquire();
      if (!_connection!.getMetaData()!.isAuthenticated) {
        await _sendCommand((FromVerbBuilder()
              ..atSign = _currentAtSign
              ..clientConfig = _clientConfig)
            .buildCommand());
        var fromResponse = await (messageListener.read());
        logger.finer('from result:$fromResponse');
        if (fromResponse.isEmpty) {
          return false;
        }
        fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');
        fromResponse = validatedFromChallenge(fromResponse, _currentAtSign);
        logger.finer('fromResponse $fromResponse');
        // RSA SHA-256 sign via at_chops (wraps the same crypton
        // RSAPrivateKey.createSHA256Signature; only the private key is used).
        // TODO(4.0): remove with the privateKey ladder credential this method
        // exists to serve. If it outlives the ladder instead, RsaSignatureAlgo
        // produces identical signature bytes for a 2048-bit key — but refuses
        // any other modulus size, which this path never checked, so a
        // caller-supplied 3072- or 4096-bit key that authenticates today
        // would start throwing.
        // ignore: deprecated_member_use
        var sha256signature = PkamSigningAlgo(
                // ignore: deprecated_member_use
                AtPkamKeyPair.create('', privateKey),
                HashingAlgoType.sha256)
            .sign(Uint8List.fromList(utf8.encode(fromResponse)));
        var signature = base64Encode(sha256signature);
        logger.finer('Sending command pkam:$signature');
        await _sendCommand('pkam:$signature\n');
        var pkamResponse = await messageListener.read();
        if (pkamResponse == 'data:success') {
          logger.info('auth success');
          _recordAuthentication();
        } else {
          throw UnAuthenticatedException(
              'Failed connecting to $_currentAtSign. $pkamResponse');
        }
      }
      return _connection!.getMetaData()!.isAuthenticated;
    } finally {
      _pkamAuthenticationMutex.release();
    }
  }

  @override
  Future<bool> pkamAuthenticate({String? enrollmentId}) async {
    // Prefer an injected authenticator here too, not only in [_process].
    // at_auth reaches this method directly rather than through a verb, so a
    // seam wired only into [_process] would leave the authenticate() path
    // still running the ladder - the seam would look connected and do nothing
    // on the one call that matters most.
    if (authenticator != null) {
      await _authenticateWith(authenticator!, enrollmentId: enrollmentId);
      return _connection!.getMetaData()!.isAuthenticated;
    }
    await createConnection();
    try {
      await _pkamAuthenticationMutex.acquire();
      if (!_connection!.getMetaData()!.isAuthenticated) {
        await _sendCommand((FromVerbBuilder()
              ..atSign = _currentAtSign
              ..clientConfig = _clientConfig)
            .buildCommand());
        var fromResponse = await (messageListener.read());
        logger.finer('from result:$fromResponse');
        if (fromResponse.isEmpty) {
          return false;
        }
        fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');
        fromResponse = validatedFromChallenge(fromResponse, _currentAtSign);
        logger.finer('fromResponse $fromResponse');
        logger.finer(
            'signingAlgoType: $signingAlgoType hashingAlgoType:$hashingAlgoType');
        // TODO(4.0): remove with the credential ladder; at_chops directs this
        // to calling an AtSigningAlgorithm implementation directly.
        // ignore: deprecated_member_use
        final atSigningInput = AtSigningInput(fromResponse)
          ..signingAlgoType = signingAlgoType
          ..hashingAlgoType = hashingAlgoType
          // ignore: deprecated_member_use
          ..signingMode = AtSigningMode.pkam;
        var signingResult = _atChops!.sign(atSigningInput);
        var pkamBuilder = PkamVerbBuilder()
          ..signingAlgo = signingAlgoType.name
          ..hashingAlgo = hashingAlgoType.name
          ..enrollmentlId = enrollmentId
          ..signature = signingResult.result;
        logger.finer('pkamCommand:${pkamBuilder.buildCommand()}');
        await _sendCommand(pkamBuilder.buildCommand());

        var pkamResponse = await messageListener.read();
        if (pkamResponse == 'data:success') {
          logger.info('auth success');
          _recordAuthentication(enrollmentId: enrollmentId);
        } else {
          throw UnAuthenticatedException(
              'Failed connecting to $_currentAtSign. $pkamResponse');
        }
      }
      return _connection!.getMetaData()!.isAuthenticated;
    } finally {
      _pkamAuthenticationMutex.release();
    }
  }

  final Mutex _cramAuthenticationMutex = Mutex();

  @override
  Future<bool> cramAuthenticate(String secret) async {
    await createConnection();
    try {
      await _cramAuthenticationMutex.acquire();
      if (!_connection!.getMetaData()!.isAuthenticated) {
        await _sendCommand((FromVerbBuilder()
              ..atSign = _currentAtSign
              ..clientConfig = _clientConfig)
            .buildCommand());
        var fromResponse = await messageListener.read(
            transientWaitTimeMillis: 4000, maxWaitMilliSeconds: 10000);
        logger.info('from result:$fromResponse');
        if (fromResponse.isEmpty) {
          return false;
        }
        fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');
        var digestInput = '$secret$fromResponse';
        var bytes = utf8.encode(digestInput);
        // SHA-512 hex digest via at_chops (= sha512.convert(bytes).toString()).
        var digest = SHA512HashingAlgo().hash(bytes);
        await _sendCommand('cram:$digest\n');
        var cramResponse = await messageListener.read(
            transientWaitTimeMillis: 4000, maxWaitMilliSeconds: 10000);
        if (cramResponse == 'data:success') {
          logger.info('auth success');
          _recordAuthentication();
        } else {
          throw UnAuthenticatedException('Auth failed');
        }
      }
      return _connection!.getMetaData()!.isAuthenticated;
    } finally {
      _cramAuthenticationMutex.release();
    }
  }

  @Deprecated('use AtLookup().cramAuthenticate()')
  // ignore: non_constant_identifier_names
  Future<bool> authenticate_cram(String? secret) async {
    secret ??= cramSecret;
    if (secret == null) {
      throw UnAuthenticatedException('Cram secret not passed');
    }
    return await cramAuthenticate(secret);
  }

  Future<String> _plookup(PLookupVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _lookup(LookupVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: builder.auth);
  }

  Future<String> _llookup(LLookupVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _delete(DeleteVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(
      atCommand,
      auth: true,
    );
  }

  /// Ensures that a new request isn't sent until either response has been received from previous
  /// request, or response wasn't received due to timeout or other exception
  Mutex requestResponseMutex = Mutex();

  Future<String> _process(String command, {bool auth = false}) async {
    try {
      await requestResponseMutex.acquire();

      if (auth && _isAuthRequired()) {
        if (authenticator != null) {
          await _authenticateWith(authenticator!);
        } else if (_atChops != null) {
          logger.finer('calling pkam using atchops');
          await pkamAuthenticate(enrollmentId: enrollmentId);
        } else if (privateKey != null) {
          logger.finer('calling pkam without atchops');
          await authenticate(privateKey);
        } else if (cramSecret != null) {
          await cramAuthenticate(cramSecret!);
        } else {
          throw UnAuthenticatedException(
              'Unable to perform atLookup auth. atChops object is not set');
        }
      }
      try {
        await _sendCommand(command);
        var result = await messageListener.read();
        return result;
      } on Exception catch (e) {
        logger.severe('Exception in sending to server, ${e.toString()}');
        rethrow;
      }
    } finally {
      requestResponseMutex.release();
    }
  }

  bool _isAuthRequired() {
    return !isConnectionAvailable() ||
        !(_connection!.getMetaData()!.isAuthenticated);
  }

  Future<bool> createOutBoundConnection(String host, String port,
      String toAtSign, SecureSocketConfig secureSocketConfig) async {
    try {
      SecureSocket secureSocket =
          await socketFactory.createSocket(host, port, secureSocketConfig);
      _connection =
          outboundConnectionFactory.createOutboundConnection(secureSocket);
      if (outboundConnectionTimeout != null) {
        _connection!.setIdleTime(outboundConnectionTimeout);
      }
    } on SocketException {
      throw SecondaryConnectException(
          'unable to connect to atServer for $toAtSign on $host:$port');
    }
    return true;
  }

  @override
  bool isConnectionAvailable() {
    return _connection != null && !_connection!.isInValid();
  }

  bool isInValid() {
    return _connection!.isInValid();
  }

  @override
  Future<void> close() async {
    await _closeConnection();
  }

  /// Closes the connection and fails whatever was waiting on it.
  ///
  /// Every close goes through here rather than calling `_connection.close()`
  /// directly, because a close leaves a request in flight with nowhere for its
  /// response to arrive from. [OutboundMessageListener.read] cannot see that on
  /// its own, so it waits out its transient budget - and it is holding
  /// [requestResponseMutex] while it does, which stalls the NEXT request on
  /// this instance for the same 30 seconds.
  ///
  /// That is not hypothetical: it is what made an atSign switch stall the
  /// request that followed it, because `AtClientImpl.stop()` destroys the
  /// outgoing client's socket while its startup work is still in flight, and
  /// the same AtLookupImpl is handed back when that atSign is switched to
  /// again.
  ///
  /// The listener aborts on `onDone` as well, and in Dart a local
  /// `Socket.destroy()` does deliver one - measured - so the two routes
  /// usually agree. This one is still needed, and not merely as belt and
  /// braces: **a PAUSED subscription delivers no done event**, also measured,
  /// and this class pauses the socket to push back-pressure at the atServer
  /// during notification delivery. Closing while paused reaches the abort
  /// through here and through nothing else.
  Future<void> _closeConnection() async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    // `messageListener` is `late` and assigned in [createConnection] - which is
    // also where `_connection` is assigned, so a non-null connection means
    // there is a listener to tell.
    messageListener.abortPendingRequests();
    await connection.close();
  }

  // ---------------------------------------------------------------------
  // AtLookupMuxable - the second framing, on a connection of its own.
  // See the warning on [AtLookupMuxable]: sharing one socket with verb
  // traffic is NOT safe today, because no atServer implements the flag that
  // was supposed to make it safe.
  // ---------------------------------------------------------------------

  /// Created on first read of [notifications], not in the constructor.
  ///
  /// Its existence is what tells [createConnection] to install the framing
  /// seam, so a lookup nobody asked notifications of behaves exactly as it
  /// always did - including leaving a stray notification in the buffer, which
  /// is pinned by test as the behaviour the seam exists to fix.
  StreamController<String>? _notificationController;

  bool _isNotifying = false;

  // --- reconnect, reauth and heartbeat -----------------------------------
  //
  // Owned here because this object holds the socket. at_client's Monitor
  // carries an identical [1,2,3,5,8,13,21,34] delay list; both cannot own
  // reconnection, and on a connection that also carries verb traffic a
  // Monitor-owned reconnect would be healing a socket it does not own for a
  // subsystem that is not it.

  /// Delays between reconnect attempts. The last is repeated indefinitely.
  static const List<Duration> notificationReconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 21),
    Duration(seconds: 34),
  ];

  /// How often a quiet notification connection is probed, and how long the
  /// probe waits. Settable so a test does not have to wait 30 seconds.
  @override
  Duration heartbeatInterval = const Duration(seconds: 30);

  @override
  Duration heartbeatResponseTimeout = const Duration(seconds: 10);

  String? _notifyRegex;
  int? _notifyLastNotificationTime;
  bool _notifySelfNotifications = true;

  int _reconnectIx = 0;
  bool _reconnecting = false;
  Timer? _heartbeatTimer;

  /// Whether a reconnect is in flight. Visible so a test can assert the loop
  /// is running rather than inferring it from a delay.
  @override
  bool get isReconnectingNotifications => _reconnecting;

  StreamController<bool>? _connectionUpController;

  @override
  Stream<bool> get notificationConnectionUp {
    _connectionUpController ??= StreamController<bool>.broadcast();
    return _connectionUpController!.stream;
  }

  void _emitConnectionUp(bool up) {
    final controller = _connectionUpController;
    if (controller == null || controller.isClosed) return;
    controller.add(up);
  }

  void _onNotificationConnectionLost() {
    if (!_isNotifying || _reconnecting) return;
    // `warning`: the subscriber cannot see this any other way, and a silent
    // reconnect looks identical to an atServer that has simply gone quiet.
    logger.warning(
        'Notification connection to $_currentAtSign lost - reconnecting');
    _emitConnectionUp(false);
    _stopHeartbeat();
    unawaited(_reconnectNotifications());
  }

  Future<void> _reconnectNotifications() async {
    _reconnecting = true;
    try {
      while (_isNotifying) {
        final delay = notificationReconnectDelays[
            min(_reconnectIx, notificationReconnectDelays.length - 1)];
        _reconnectIx++;
        logger.info('Reconnecting notifications in ${delay.inSeconds}s '
            '(attempt $_reconnectIx)');
        await Future.delayed(delay);
        // Re-checked after the delay, not only before it: stopNotifications
        // can land while this is sleeping, and reconnecting after that would
        // resurrect a connection the caller asked to be rid of.
        if (!_isNotifying) return;
        try {
          await _openNotificationStream();
          logger.info('Notification connection re-established');
          _reconnectIx = 0;
          _startHeartbeat();
          _emitConnectionUp(true);
          return;
        } catch (e) {
          logger.warning('Reconnect attempt $_reconnectIx failed: $e');
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer(heartbeatInterval, _heartbeat);
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Probe a quiet connection with `noop:0`.
  ///
  /// ⚠️ This makes the notification connection carry verb traffic, which is
  /// the arrangement [AtLookupMuxable] warns about: no atServer implements the
  /// `multiplexed` interlock, so a notification written between this command
  /// and its reply is absorbed into the reply rather than routed. The window
  /// is one short round trip every [heartbeatInterval], and it is the same
  /// exposure at_client's Monitor has had all along - this moves that
  /// behaviour, it does not add it. It closes when an atServer implements the
  /// flag.
  Future<void> _heartbeat() async {
    if (!_isNotifying) return;
    try {
      await requestResponseMutex.acquire();
      try {
        await _sendCommand('noop:0\n');
        await messageListener.read(
            maxWaitMilliSeconds: heartbeatResponseTimeout.inMilliseconds,
            transientWaitTimeMillis: heartbeatResponseTimeout.inMilliseconds);
      } finally {
        requestResponseMutex.release();
      }
      _heartbeatTimer = Timer(heartbeatInterval, _heartbeat);
    } catch (e) {
      logger.info('Notification heartbeat failed ($e) - closing the '
          'connection so it reconnects');
      // Closing is what starts recovery: the socket going away drives the
      // listener's onDone, which is wired to [_onNotificationConnectionLost].
      await _closeConnection();
    }
  }

  @override
  bool get isNotifying => _isNotifying;

  @override
  Stream<String> get notifications {
    _notificationController ??= StreamController<String>(
      // Back-pressure that reaches the far end. A listener that stops reading
      // stops the socket, so bytes pile up in the kernel buffer and TCP closes
      // the window on the atServer - rather than being absorbed here without
      // bound until the byte buffer overflows.
      onPause: () => _setNotificationDelivery(paused: true),
      onResume: () => _setNotificationDelivery(paused: false),
    );
    // A connection may already exist - `notifications` can be read after the
    // first verb - so the seam is installed here too, not only on connect.
    if (_connection != null) {
      messageListener.onNotification = _routeNotification;
    }
    return _notificationController!.stream;
  }

  /// [messageListener] is `late` and is assigned only inside
  /// [createConnection], immediately after `_connection`. So a null
  /// `_connection` is exactly the case where touching it throws a
  /// `LateInitializationError` - and the controller can be paused before
  /// anything has connected.
  void _setNotificationDelivery({required bool paused}) {
    if (_connection == null) return;
    if (paused) {
      messageListener.pauseDelivery();
    } else {
      messageListener.resumeDelivery();
    }
  }

  void _routeNotification(String notification) {
    final controller = _notificationController;
    if (controller == null || controller.isClosed) {
      // `warning`, not `finer`. A silently dropped notification is
      // indistinguishable from one the atServer never sent, so the failure
      // gets attributed to the sender. Nothing retries this.
      logger.warning('Notification DROPPED for $_currentAtSign - the stream is '
          '${controller == null ? "not open" : "closed"}: $notification');
      return;
    }
    controller.add(notification);
  }

  @override
  Future<void> startNotifications({
    String? regex,
    int? lastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    if (_isNotifying) {
      logger.info('startNotifications: already notifying, nothing sent');
      return;
    }
    // Reading this getter is what creates the controller and installs the
    // seam, so it must happen before `monitor:` goes out - otherwise the first
    // notifications arrive with nowhere to go.
    notifications;

    // Remembered, because reconnecting has to re-issue the SAME monitor:. A
    // reconnect that dropped the regex would start delivering everything, and
    // one that dropped the watermark would replay from the beginning.
    _notifyRegex = regex;
    _notifyLastNotificationTime = lastNotificationTime;
    _notifySelfNotifications = selfNotificationsEnabled;

    await _openNotificationStream();
    _isNotifying = true;
    _reconnectIx = 0;
    _startHeartbeat();
    _emitConnectionUp(true);
  }

  /// Connect, authenticate if required, and send `monitor:`.
  ///
  /// Shared by [startNotifications] and the reconnect loop, so a reconnected
  /// connection is established exactly as the first one was. Anything else and
  /// the two paths drift, with the difference only visible after an outage.
  Future<void> _openNotificationStream() async {
    await requestResponseMutex.acquire();
    try {
      await createConnection();
      if (_isAuthRequired()) {
        if (authenticator != null) {
          await _authenticateWith(authenticator!, enrollmentId: enrollmentId);
        } else {
          throw UnAuthenticatedException(
              'monitor requires authentication and no authenticator is set');
        }
      }
      final command = (MonitorVerbBuilder()
            ..regex = _notifyRegex
            ..lastNotificationTime = _notifyLastNotificationTime
            ..selfNotificationsEnabled = _notifySelfNotifications)
          .buildCommand();
      // ⚠️ `multiplexed` is deliberately NOT set. It is accepted by the shared
      // verb syntax and read by no atServer, so setting it would advertise a
      // safety property that does not exist. See [AtLookupMuxable].
      logger.info('SENDING: ${command.trim()}');
      await _connection!.write(command);
    } finally {
      requestResponseMutex.release();
    }
  }

  @override
  Future<void> stopNotifications() async {
    // First, and deliberately: this flag is what the reconnect loop reads to
    // decide whether to keep trying. Closing the connection before clearing it
    // would trip the disconnect handler into reconnecting the very connection
    // this method is tearing down.
    _isNotifying = false;
    _stopHeartbeat();
    _emitConnectionUp(false);
    await _closeConnection();
    final controller = _notificationController;
    _notificationController = null;
    // NOT awaited, and that is the point. `close()` on a single-subscription
    // controller returns its `done` future, which completes only once a
    // subscriber has received the done event - so a caller that started
    // notifications and never listened would hang here forever. Start-then-stop
    // with no subscriber is a legal caller, and awaiting this deadlocked four
    // tests for thirty seconds each before it was caught.
    unawaited(controller?.close() ?? Future<void>.value());
    final up = _connectionUpController;
    _connectionUpController = null;
    unawaited(up?.close() ?? Future<void>.value());
  }

  Future<void> _sendCommand(String command) async {
    await createConnection();
    logger.finer('SENDING: $command');
    await _connection!.write(command);
  }

  @Deprecated('Pass an AtAuthenticator to AtLookUp.withSecureSocket '
      'instead - at_auth builds one with authenticatorForChops(). '
      'Removed with the credential ladder in the next major release.')
  @override
  set atChops(AtChops? atChops) {
    _atChops = atChops;
  }

  @Deprecated('Pass an AtAuthenticator to AtLookUp.withSecureSocket '
      'instead - at_auth builds one with authenticatorForChops(). '
      'Removed with the credential ladder in the next major release.')
  @override
  AtChops? get atChops => _atChops;

  /// To use a specific signing algorithm other than default one for pkam auth, set the [SigningAlgoType] and [HashingAlgoType]
  @Deprecated('Pass the hashing algorithm to the AtAuthenticator that at_auth '
      'builds - authenticatorForChops() takes signingAlgo and hashingAlgo. '
      'Removed with the credential ladder in the next major release.')
  @override
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;

  @Deprecated('Pass the signing algorithm to the AtAuthenticator that at_auth '
      'builds - authenticatorForChops() takes signingAlgo and hashingAlgo. '
      'Removed with the credential ladder in the next major release.')
  @override
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  @Deprecated('Pass the enrollment id to the AtAuthenticator that at_auth '
      'builds. To ask "which enrollment am I", read your own client state - '
      'not this field, and not '
      'AtConnectionMetaData.authenticatedAsEnrollmentId, which is what the '
      'live connection authenticated as rather than what the next '
      'authentication will use. '
      'Removed with the credential ladder in the next major release.')
  @override
  String? enrollmentId;
}

class AtLookupSecureSocketFactory {
  const AtLookupSecureSocketFactory();

  Future<SecureSocket> createSocket(
      String host, String port, SecureSocketConfig socketConfig,
      {Duration? timeout}) async {
    return await SecureSocketUtil.createSecureSocket(host, port, socketConfig,
        timeout: timeout);
  }
}

class AtLookupSecureSocketListenerFactory {
  const AtLookupSecureSocketListenerFactory();

  OutboundMessageListener createListener(
      OutboundConnection outboundConnection) {
    return OutboundMessageListener(outboundConnection);
  }
}

class AtLookupOutboundConnectionFactory {
  const AtLookupOutboundConnectionFactory();

  OutboundConnection createOutboundConnection(SecureSocket secureSocket) {
    return OutboundConnectionImpl(secureSocket);
  }
}
