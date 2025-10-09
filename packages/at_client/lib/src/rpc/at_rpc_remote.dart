import 'package:at_client/at_client.dart';

abstract class AtRpcRemote {
  Future<dynamic> $invoke(String methodName, List<dynamic> positional, Map<String, dynamic> named);
}

/// represents a remote procedure call (RPC) endpoint
class AtRpcStubGetter {
  late AtRpcClient _atRpcClient;

  AtRpcStubGetter(
    {required AtClient atClient,
    required String serverAtsign,
    required String baseNameSpace,
    required String domainNameSpace}) {
    _atRpcClient = AtRpcClient(atClient: atClient, serverAtsign: serverAtsign, baseNameSpace: baseNameSpace, domainNameSpace: domainNameSpace);
  }

  Future<List<String>> getAvailableStubs() async {
    final Map<String, dynamic> response = await _atRpcClient.call({'operation': 'list_stubs'});
    if(response['stubs'] != null && response['stubs'] is List) {
      return List<String>.from(response['stubs']);
    }
    throw Exception('Invalid response from server: "${response.toString()}"');
  }

  T getStub<T>(String stubName) {
    return _RemoteStubProxy<T>(stubName, _atRpcClient) as T;
  }
}

class _RemoteStubProxy<T> {
  final String _stubName;
  final AtRpcClient _client;

  _RemoteStubProxy(this._stubName, this._client);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = _symbolToString(invocation.memberName);
    final positional = invocation.positionalArguments;
    final named = invocation.namedArguments.map((k, v) => MapEntry(_symbolToString(k), v));

    final payload = {
      'operation': 'invoke',
      'stub': _stubName,
      'method': method,
      'params': {
        'positional': positional,
        'named': named,
      },
    };

    Future<dynamic> fut = _client.call(payload).then((resp) {
      if (resp['error'] != null) throw Exception(resp['error']);
      return resp['result'];
    });

    return fut;
  }

  String _symbolToString(Symbol s) {
    final m = RegExp(r'Symbol\("(.+)"\)').firstMatch(s.toString());
    return m?.group(1) ?? s.toString();
  }
}

/// server that manages AtRpcRemote instances
class AtRpcRemoteRegistry implements AtRpcCallbacks {
  late AtRpc _atRpcServer;

  late AtClient _atClient;
  late String _baseNameSpace;
  late String _domainNameSpace;
  late Set<String> _allowList;
  late Map<String, Object> _remoteObjects;

  AtRpcRemoteRegistry(
      {required final AtClient atClient,
      required final String baseNameSpace,
      required final String domainNameSpace,
      required final Set<String> allowList,
      required final Map<String, Object> remoteObjects}) {
    _atClient = atClient;
    _baseNameSpace = baseNameSpace;
    _domainNameSpace = domainNameSpace;
    _allowList = allowList;
    _remoteObjects = remoteObjects;

    _atRpcServer = AtRpc(
        atClient: _atClient,
        baseNameSpace: _baseNameSpace,
        domainNameSpace: _domainNameSpace,
        callbacks: this,
        allowList: _allowList);

    _remoteObjects = remoteObjects;
  }

  Future<void> start() async {
    _atRpcServer.start();
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    final Map<String, dynamic> payload = request.payload;
    final String operation = payload['operation'];

    if(operation == 'list_stubs') {
      final dynamic respPayload = {'stubs': _remoteObjects.keys.toList()};
      final AtRpcResp response = AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.success, payload: respPayload);
      return response;
    } else if(operation == 'invoke') {
      // {'operation': 'invoke', 'stub': 'MyStub', 'method': 'myMethod', 'params': {...}}
      final String stubName = payload['stub'];
      final String methodName = payload['method'];
      final Map<String, dynamic> params = payload['params'] ?? {};

      if(!_remoteObjects.containsKey(stubName)) {
        return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.error, payload: {'error': 'Stub "$stubName" not found'});
      }

      final Object stub = _remoteObjects[stubName]!;
      final dynamic method = stub.runtimeType
          .toString()
          .contains(methodName) ? stub as dynamic : null;
      if(method == null) {
        return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.error, payload: {'error': 'Method "$methodName" not found on stub "$stubName"'});
      }

      try {
        final dynamic result = await Function.apply(method, [params]);
        
        return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.success, payload: {'result': result});
      } catch(e) {
        return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.error, payload: {'error': e.toString()});
      }
    }
    return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.error, payload: {});
  }

  @override
  Future<void> handleResponse(AtRpcResp response) {
    // TODO: implement handleResponse
    throw UnimplementedError();
  }
}
