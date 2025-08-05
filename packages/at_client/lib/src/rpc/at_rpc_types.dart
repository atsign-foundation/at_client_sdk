/// Simple data structure whose JSON is transmitted as the payload of the
/// notification which is sent from the requester to the responder
class AtRpcReq {
  /// A unique id which is used to correlate responses to requests
  final int reqId;

  /// The app-specific payload of the request
  final Map<String, dynamic> payload;

  AtRpcReq({required this.reqId, required this.payload});

  /// factory which generates a request ID
  static AtRpcReq create(Map<String, dynamic> payload) {
    return AtRpcReq(
        reqId: DateTime.now().microsecondsSinceEpoch, payload: payload);
  }

  Map<String, dynamic> toJson() => {'reqId': reqId, 'payload': payload};

  static AtRpcReq fromJson(Map<String, dynamic> json) {
    return AtRpcReq(reqId: json['reqId'], payload: json['payload']);
  }

  @override
  String toString() => toJson().toString();
}

/// The types of responses which the responder can send back to the requester
enum AtRpcRespType {
  /// Message received, looks valid, will process
  ack,

  /// Message received, will not process (e.g. due to invalid structure)
  nack,

  /// Have processed the request successfully, here's the response
  success,

  /// Tried to process the request but it failed in some way, here's some info
  error
}

/// Simple data structure whose JSON is transmitted as the payload of the
/// notification which is sent by the responder back to the requester
class AtRpcResp {
  /// The unique ID of the request. See also [AtRpcReq.reqId]
  final int reqId;

  /// The response type (ack / nack / success / error) - see [AtRpcRespType]
  final AtRpcRespType respType;

  /// The app-specific payload of the response
  final Map<String, dynamic> payload;

  /// An optional additional message
  final String? message;

  AtRpcResp(
      {required this.reqId,
      required this.respType,
      required this.payload,
      this.message});

  /// factory which makes an [AtRpcResp] with [AtRpcRespType.ack]
  /// and no payload
  static AtRpcResp ack({required AtRpcReq request}) {
    return AtRpcResp(
        reqId: request.reqId, respType: AtRpcRespType.ack, payload: {});
  }

  /// factory which makes an [AtRpcResp] with [AtRpcRespType.nack]
  /// and no payload
  static AtRpcResp nack(
      {required AtRpcReq request,
      String? message,
      Map<String, dynamic>? payload}) {
    return AtRpcResp(
        reqId: request.reqId,
        respType: AtRpcRespType.nack,
        payload: payload ?? {},
        message: message);
  }

  static AtRpcResp fromJson(Map<String, dynamic> json) {
    return AtRpcResp(
        reqId: json['reqId'],
        respType: AtRpcRespType.values.byName(json['respType']),
        payload: json['payload'],
        message: json['message']);
  }

  Map<String, dynamic> toJson() => {
        'reqId': reqId,
        'respType': respType.name,
        'payload': payload,
        'message': message
      };

  @override
  String toString() => toJson().toString();
}
