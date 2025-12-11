part of '../isolated_atclient.dart';

class _AtClientWorker {
  static void main(SendPort send) async {
    final recv = ReceivePort();
    send.send(recv.sendPort);

    final (taken, recvStream, closeRecvStream) = await takeFromStream(3, recv);

    final atAuth = AtAuth.create();
    try {
      final req = AtAuthRequest(
        taken[0],
        FileAtKeysIo(),
        rootDomain: AtRootDomain.parse(taken[1]),
        atAuthKeys: AtKeys.fromJson(jsonDecode(taken[2])),
      );

      final res = await atAuth.authenticate(req);
      if (!res.isSuccessful) throw "Failed to authenticate ${taken[0]}";
    } catch (e) {
      send.send(e.toString());
      return;
    }

    final AtClient atClient;
    try {
      atClient = await AtClientImpl.create(
        taken[0],
        "noports",
        AtClientPreference()..isLocalStoreRequired = false,
      );
      send.send(true);
    } catch (e) {
      send.send(e.toString());
      return;
    }

    handle(
        send: send,
        atClient: atClient,
        recv: recvStream,
        closeRecv: () {
          closeRecvStream();
          recv.close();
        });
  }

  // Helper function to convert _AtKeyRecord to AtKey
  static AtKey _atKeyFromRecord(_AtKeyRecord record) {
    var atKey = AtKey();
    atKey.key = record.key;
    atKey.sharedWith = record.sharedWith;
    atKey.sharedBy = record.sharedBy;
    atKey.namespace = record.namespace;
    atKey.isLocal = record.isLocal;
    atKey.isRef = record.isRef;
    atKey.metadata = _metadataFromRecord(record.metadata);
    return atKey;
  }

  // Helper function to convert _MetadataRecord to Metadata
  static Metadata _metadataFromRecord(_MetadataRecord record) {
    return Metadata()
      ..ttl = record.ttl
      ..ttb = record.ttb
      ..ttr = record.ttr
      ..ccd = record.ccd
      ..availableAt = record.availableAt
      ..expiresAt = record.expiresAt
      ..refreshAt = record.refreshAt
      ..createdAt = record.createdAt
      ..updatedAt = record.updatedAt
      ..dataSignature = record.dataSignature
      ..sharedKeyStatus = record.sharedKeyStatus
      ..isPublic = record.isPublic
      ..isHidden = record.isHidden;
  }

  // Helper function to convert Metadata to MetadataRecord
  static _MetadataRecord _metadataToRecord(Metadata metadata) {
    return (
      ttl: metadata.ttl,
      ttb: metadata.ttb,
      ttr: metadata.ttr,
      ccd: metadata.ccd,
      availableAt: metadata.availableAt,
      expiresAt: metadata.expiresAt,
      refreshAt: metadata.refreshAt,
      createdAt: metadata.createdAt,
      updatedAt: metadata.updatedAt,
      dataSignature: metadata.dataSignature,
      sharedKeyStatus: metadata.sharedKeyStatus,
      isPublic: metadata.isPublic,
      isHidden: metadata.isHidden,
    );
  }

  static void handle(
      {required Stream<Object?> recv,
      required void Function() closeRecv,
      required SendPort send,
      required AtClient atClient}) async {
    recv.listen((msg) async {
      if (msg is! _WorkerRequest) {
        send.send("Unknown message type sent to AtClientWorker");
        return;
      }

      try {
        switch (msg.request) {
          case "close":
            closeRecv();
            return;
          case "delete":
            var p = msg.params as _DeleteRequest;
            var opts = DeleteRequestOptions();
            opts.useRemoteAtServer =
                p.useRemoteAtServer ?? opts.useRemoteAtServer;
            var deleteRes = await atClient.delete(
              _atKeyFromRecord(p.atKey),
              isDedicated: p.isDedicated,
              deleteRequestOptions: opts,
            );
            _DeleteResponse resp = (success: deleteRes);
            send.send(resp);
            return;

          case "get":
            var p = msg.params as _GetRequest;
            var opts = GetRequestOptions();
            opts.bypassCache = p.bypassCache ?? opts.bypassCache;
            opts.useRemoteAtServer =
                p.useRemoteAtServer ?? opts.useRemoteAtServer;
            var getRes = await atClient.get(
              _atKeyFromRecord(p.atKey),
              isDedicated: p.isDedicated,
              getRequestOptions: opts,
            );
            _GetResponse resp = (
              value: getRes.value,
              metadata: getRes.metadata != null
                  ? _metadataToRecord(getRes.metadata!)
                  : null
            );
            send.send(resp);
            return;

          case "getAtKeys":
            var p = msg.params as _GetAtKeysRequest;
            var getAtKeysRes = await atClient.getAtKeys(
              regex: p.regex,
              sharedBy: p.sharedBy,
              sharedWith: p.sharedWith,
              showHiddenKeys: p.showHiddenKeys,
              useRemoteAtServer: p.useRemoteAtServer,
            );
            _GetAtKeysResponse resp =
                (atKeys: getAtKeysRes.map((key) => key.toString()).toList());
            send.send(resp);
            return;

          case "getKeys":
            var p = msg.params as _GetKeysRequest;
            var getKeysRes = await atClient.getKeys(
              regex: p.regex,
              sharedBy: p.sharedBy,
              sharedWith: p.sharedWith,
              showHiddenKeys: p.showHiddenKeys,
              useRemoteAtServer: p.useRemoteAtServer,
            );
            _GetKeysResponse resp = (keys: getKeysRes);
            send.send(resp);
            return;

          case "getMeta":
            var p = msg.params as _GetMetaRequest;
            var getMetaRes = await atClient.getMeta(_atKeyFromRecord(p.atKey));
            _GetMetaResponse resp = (
              metadata:
                  getMetaRes != null ? _metadataToRecord(getMetaRes) : null
            );
            send.send(resp);
            return;

          case "getOTP":
            var getOTPRes = await atClient.getOTP();
            _GetOTPResponse resp = (atResponse: getOTPRes.toJson());
            send.send(resp);
            return;

          case "notifyList":
            var p = msg.params as _NotifyListRequest;
            var notifyListRes = await atClient.notifyList(
              fromDate: p.fromDate,
              toDate: p.toDate,
              regex: p.regex,
            );
            _NotifyListResponse resp = (result: notifyListRes);
            send.send(resp);
            return;

          case "notifyStatus":
            var p = msg.params as _NotifyStatusRequest;
            var notifyStatusRes = await atClient.notifyStatus(p.notificationId);
            _NotifyStatusResponse resp = (status: notifyStatusRes);
            send.send(resp);
            return;

          case "put":
            var p = msg.params as _PutRequest;
            var opts = PutRequestOptions();
            opts.storeSharedKeyEncryptedMetadata =
                p.storeSharedKeyEncryptedMetadata ??
                    opts.storeSharedKeyEncryptedMetadata;
            opts.useRemoteAtServer =
                p.useRemoteAtServer ?? opts.useRemoteAtServer;
            opts.shouldEncrypt = p.shouldEncrypt ?? opts.shouldEncrypt;
            var putRes = await atClient.put(
              _atKeyFromRecord(p.atKey),
              p.value,
              isDedicated: p.isDedicated,
              putRequestOptions: opts,
            );
            _PutResponse resp = (success: putRes);
            send.send(resp);
            return;

          case "putBinary":
            var p = msg.params as _PutBinaryRequest;
            var opts = PutRequestOptions();
            opts.storeSharedKeyEncryptedMetadata =
                p.storeSharedKeyEncryptedMetadata ??
                    opts.storeSharedKeyEncryptedMetadata;
            opts.useRemoteAtServer =
                p.useRemoteAtServer ?? opts.useRemoteAtServer;
            opts.shouldEncrypt = p.shouldEncrypt ?? opts.shouldEncrypt;
            var putBinaryRes = await atClient.putBinary(
              _atKeyFromRecord(p.atKey),
              p.value,
              putRequestOptions: opts,
            );
            _PutBinaryResponse resp = (atResponse: putBinaryRes.toJson());
            send.send(resp);
            return;

          case "putMeta":
            var p = msg.params as _PutMetaRequest;
            var putMetaRes = await atClient.putMeta(_atKeyFromRecord(p.atKey));
            _PutMetaResponse resp = (success: putMetaRes);
            send.send(resp);
            return;

          case "putText":
            var p = msg.params as _PutTextRequest;
            var opts = PutRequestOptions();
            opts.storeSharedKeyEncryptedMetadata =
                p.storeSharedKeyEncryptedMetadata ??
                    opts.storeSharedKeyEncryptedMetadata;
            opts.useRemoteAtServer =
                p.useRemoteAtServer ?? opts.useRemoteAtServer;
            opts.shouldEncrypt = p.shouldEncrypt ?? opts.shouldEncrypt;
            var putTextRes = await atClient.putText(
              _atKeyFromRecord(p.atKey),
              p.value,
              putRequestOptions: opts,
            );
            _PutTextResponse resp = (atResponse: putTextRes.toJson());
            send.send(resp);
            return;

          case "setSPP":
            var p = msg.params as _SetSPPRequest;
            var setSPPRes = await atClient.setSPP(p.otp);
            _SetSPPResponse resp = (atResponse: setSPPRes.toJson());
            send.send(resp);
            return;
        }
      } catch (e, s) {
        print("Error in AtClient Worker: $e");
        print("Stacktrace: $s");
        send.send(e.toString());
        return;
      }
    });
  }
}
