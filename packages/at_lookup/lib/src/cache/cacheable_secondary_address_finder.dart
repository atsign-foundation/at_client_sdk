import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/util/lookup_util.dart';
import 'package:at_utils/at_logger.dart';

class CacheableSecondaryAddressFinder implements SecondaryAddressFinder {
  static const Duration defaultCacheDuration = Duration(hours: 1);

  final Map<String, SecondaryAddressCacheEntry> _map = {};
  final _logger = AtSignLogger('AtServerAddressCacheImpl');

  final String _rootDomain;
  final int _rootPort;
  late SecondaryUrlFinder _secondaryFinder;

  CacheableSecondaryAddressFinder(this._rootDomain, this._rootPort,
      {SecondaryUrlFinder? secondaryFinder, SecureSocketConfig? socketConfig}) {
    _secondaryFinder = secondaryFinder ??
        SecondaryUrlFinder(_rootDomain, _rootPort, socketConfig: socketConfig);
  }

  bool cacheContains(String atSign) {
    return _map.containsKey(stripAtSignFromAtSign(atSign));
  }

  /// Returns the expiry time of this entry in millisecondsSinceEpoch, or null if this atSign is not in cache
  int? getCacheExpiryTime(String atSign) {
    atSign = stripAtSignFromAtSign(atSign);
    if (_map.containsKey(atSign)) {
      return _map[atSign]!.expiresAt;
    } else {
      return null;
    }
  }

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    atSign = stripAtSignFromAtSign(atSign);

    // Convert the timeout into an absolute deadline once, then thread it down so
    // the retry loop, the connect and the response-wait all share ONE budget.
    final DateTime deadline = DateTime.now().add(
        AtNetworkTimeouts.cap(timeout ?? AtNetworkTimeouts.defaultTimeout));

    if (_cacheIsEmptyOrExpired(atSign)) {
      // _updateCache will either populate the cache, or throw an exception
      await _updateCache(atSign, defaultCacheDuration, deadline);
    }
    if (_map.containsKey(atSign)) {
      // should always be true, since _updateCache will throw an exception if it fails
      return _map[atSign]!.secondaryAddress;
    } else {
      // but just in case, we'll throw an exception if it's not
      throw Exception(
          "Failed to find atServer address for $atSign in atDirectory, in a theoretically impossible way");
    }
  }

  bool _cacheIsEmptyOrExpired(String atSign) {
    if (_map.containsKey(atSign)) {
      SecondaryAddressCacheEntry entry = _map[atSign]!;
      if (entry.expiresAt < DateTime.now().millisecondsSinceEpoch) {
        // expiresAt is in the past - cache has expired
        return true;
      } else {
        // cache has not yet expired
        return false;
      }
    } else {
      // cache is empty
      return true;
    }
  }

  static String stripAtSignFromAtSign(String atSign) {
    if (atSign.startsWith('@')) {
      atSign = atSign.replaceFirst('@', '');
    }
    return atSign;
  }

  static String getNotFoundExceptionMessage(String atSign) {
    return 'No entry in atDirectory for $atSign';
  }

  static String getFailedToLookUpExceptionMessage(String atSign) {
    return 'Failed attempt to lookup atServer address for $atSign';
  }

  Future<void> _updateCache(
      String atSign, Duration cacheFor, DateTime deadline) async {
    try {
      String? secondaryUrl =
          await _secondaryFinder.findSecondaryUrl(atSign, deadline: deadline);
      if (secondaryUrl == null ||
          secondaryUrl.isEmpty ||
          secondaryUrl == 'data:null') {
        throw SecondaryNotFoundException(getNotFoundExceptionMessage(atSign));
      }
      var secondaryInfo = LookUpUtil.getSecondaryInfo(secondaryUrl);
      String secondaryHost = secondaryInfo[0];
      int secondaryPort = int.parse(secondaryInfo[1]);

      SecondaryAddress addr = SecondaryAddress(secondaryHost, secondaryPort);
      _map[atSign] = SecondaryAddressCacheEntry(
          addr, DateTime.now().add(cacheFor).millisecondsSinceEpoch);
    } on AtException {
      rethrow;
    } on Exception catch (e) {
      _logger.severe(
          '${getFailedToLookUpExceptionMessage(atSign)} - ${e.toString()}');
      throw AtException(e.toString());
    }
  }
}

class SecondaryAddressCacheEntry {
  final SecondaryAddress secondaryAddress;

  /// milliseconds since epoch
  final int expiresAt;

  SecondaryAddressCacheEntry(this.secondaryAddress, this.expiresAt);
}

/// When SecondaryUrlFinder tries to lookup the atServer's address from an
/// atDirectory, it may encounter intermittent failures for various reasons -
/// 'network weather', service glitches, etc.
///
/// In order to be resilient to such failures, we implement retries.
///
/// The static variable [retryDelaysMillis] controls
/// (a) how many retries are done, and
/// (b) the delay before each retry
class SecondaryUrlFinder {
  final String _rootDomain;
  final int _rootPort;
  late final AtLookupSecureSocketFactory _socketFactory;
  late final SecureSocketConfig _socketConfig;

  SecondaryUrlFinder(this._rootDomain, this._rootPort,
      {AtLookupSecureSocketFactory? socketFactory,
      SecureSocketConfig? socketConfig}) {
    _socketFactory = socketFactory ?? AtLookupSecureSocketFactory();
    _socketConfig = socketConfig ?? SecureSocketConfig();
  }

  final _logger = AtSignLogger('AtServerUrlFinder');

  /// Controls
  /// (a) how many retries are done, and
  /// (b) the delay before each retry
  static List<int> retryDelaysMillis = [50, 100, 150, 200];

  Future<String?> findSecondaryUrl(String atSign, {DateTime? deadline}) async {
    if (_rootDomain.startsWith("proxy:")) {
      // In order to make it easy for clients to connect to a reverse proxy
      // instead of doing a root lookup,  we adopt the convention that:
      // if the rootDomain starts with 'proxy:'
      // then the secondary domain name will be deemed to be the portion of rootDomain after 'proxy:'
      // and the secondary port will be deemed to be the rootPort
      return '${_rootDomain.substring("proxy:".length)}:$_rootPort';
    }
    deadline ??= DateTime.now().add(AtNetworkTimeouts.effectiveDefault);
    String? address;
    String lastExceptionMsg = '';
    for (int i = 0; i <= retryDelaysMillis.length; i++) {
      // Abandon the retry loop once the overall deadline has passed, instead of
      // always running all attempts (each of which can take seconds).
      if (!DateTime.now().isBefore(deadline)) {
        throw AtTimeoutException('AtLookup.findAtServer for $atSign timed out'
            '${lastExceptionMsg.isEmpty ? '' : ' : $lastExceptionMsg'}');
      }
      try {
        address = await _findSecondary(atSign, deadline);
        return address;
      } catch (e) {
        lastExceptionMsg = e.toString();
        if (i < retryDelaysMillis.length) {
          final delay = Duration(milliseconds: retryDelaysMillis[i]);
          // Only wait for the backoff if it still fits inside the deadline.
          if (DateTime.now().add(delay).isBefore(deadline)) {
            _logger.info('AtLookup.findAtServer for $atSign failed with $e'
                ' : will retry in ${retryDelaysMillis[i]} milliseconds');
            await Future.delayed(delay);
            continue;
          }
        }
        _logger.severe('findAtServer for $atSign : $e');
        if (e is RootServerConnectivityException) {
          rethrow;
        }
      }
    }
    throw AtConnectException('findAtServer for $atSign : $lastExceptionMsg');
  }

  Future<String?> _findSecondary(String atsign, DateTime deadline) async {
    String? response;
    SecureSocket? socket;
    try {
      _logger.finer('findAtServerUrl: received atsign: $atsign');
      if (atsign.startsWith('@')) atsign = atsign.replaceFirst('@', '');
      var answer = '';
      String? secondary;
      var ans = false;
      var prompt = false;
      var once = true;

      // Bound the connect by whatever budget remains before the deadline.
      final remaining =
          AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
      socket = await _socketFactory.createSocket(
        _rootDomain,
        '$_rootPort',
        _socketConfig,
        timeout: remaining,
      );
      _logger.finer('findAtServerUrl: connection to atDirectory established');
      // listen to the received data event stream
      socket.listen((List<int> event) async {
        _logger.finest('atDirectory socket listener received: $event');
        answer = utf8.decode(event);

        if (answer.endsWith('@') && prompt == false && once == true) {
          prompt = true;
          socket!.write('$atsign\n');
          await socket.flush();
          once = false;
        }

        if (answer.contains(':')) {
          answer = answer.replaceFirst('\r\n@', '');
          answer = answer.replaceFirst('@', '');
          answer = answer.replaceAll('@', '');
          secondary = answer.trim();
          ans = true;
        } else if (answer.startsWith('null')) {
          secondary = null;
          ans = true;
        }
      });
      // Wait for the atDirectory to answer, bounded by the overall deadline
      // (previously a fixed 30-second busy-wait, ignoring any caller budget).
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(Duration(milliseconds: 5));
        if (ans) {
          response = secondary;
          socket.write('@exit\n');
          await socket.flush();
          socket.destroy();
          _logger.finer(
              'findAtServerUrl got answer: $secondary and closing connection');
          return response;
        }
      }
      // .. and close the socket
      await socket.flush();
      socket.destroy();
      throw AtTimeoutException('AtLookup.findAtServer timed out');
    } on Exception catch (exception) {
      var msg = 'Connecting to $_rootDomain:$_rootPort : $exception';
      _logger.severe(msg);
      if (socket != null) {
        socket.destroy();
      }
      throw RootServerConnectivityException(msg);
    } catch (exception, stackTrace) {
      var msg = 'Connecting to $_rootDomain:$_rootPort : $exception';
      _logger.severe(msg);
      _logger.severe(stackTrace);
      if (socket != null) {
        socket.destroy();
      }
      throw RootServerConnectivityException(msg);
    }
  }
}
