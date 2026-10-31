window.MAP_FLOWS = window.MAP_FLOWS || {};
window.MAP_FLOWS["share-record"] = {
 "frames": [
  {
   "from": "alice-push",
   "kind": "loop",
   "label": "sync sends queued writes in batches until the queue is empty",
   "to": "alice-server-update"
  },
  {
   "from": "alice-server-queue",
   "kind": "opt",
   "label": "the atServer's autoNotify setting is on",
   "to": "bob-deliver"
  }
 ],
 "id": "share-record",
 "inputs": {
  "model": "ecadfb15df2c368ef87853ba067972cf0b5207d1888ff27d3eaf15e2a674f084",
  "production": "3c3bd74b659b8f81f21c340ada455f9cda536fab",
  "server": "d654f25bd4bdef2668c77556f563f9e43960b325"
 },
 "laneNote": "Server lane at at_server trunk d654f25bd; production p3.19.0 is 160 commits behind.",
 "lanes": [
  "alice.client",
  "alice.server",
  "bob.server",
  "bob.client"
 ],
 "lenses": [
  "notifications",
  "sync",
  "e2e"
 ],
 "retired": [],
 "steps": [
  {
   "anchor": {
    "contains": "await CryptoRuntime(this).prepareWrite(",
    "path": "packages/at_client/lib/src/client/at_client_impl.dart",
    "root": "sdk",
    "symbol": "AtClientImpl._putInternal",
    "url": "../../packages/at_client/lib/src/client/at_client_impl.dart"
   },
   "changed": false,
   "contracts": [
    {
     "backing": {
      "exit": {
       "guard": "!validationResult.isValid",
       "kind": "throw",
       "symbol": "AtClientImpl._putInternal",
       "type": "AtKeyException"
      }
     },
     "kind": "refuses",
     "label": "client-side, best effort",
     "text": "a key that fails AtKeyValidators, for example one @alice does not own"
    }
   ],
   "hash": "6f111480fad6379d",
   "id": "alice-put",
   "intent": "Validate @bob:note.ns@alice, set its sharedBy to @alice, let the crypto provider prepare the write, then build the update command.",
   "lane": "alice.client",
   "links": [],
   "reached": {
    "kind": "entry",
    "text": "entry"
   },
   "reviewed": "6f111480fad6379d",
   "skeleton": "_routingFor, _refuseNoCommitWithoutRemote\nAtClientValidation.validatePutRequest\nif atKey.sharedBy.isNull:\n  atKey.sharedBy = _atSign\nif atKey.metadata.namespaceAware:\n  atKey.namespace = preference?.namespace\nensureLowerCase\nvalidationResult = AtKeyValidators.get, atKey.toString, ValidationContext, AtKeyValidators.get().validate\nif !validationResult.isValid:\n  throw AtKeyException(validationResult.failure…\nif !atKey.metadata.isPublic \u0026\u0026 !atKey.isLocal \u0026\u0026 options.shouldEncrypt:\n  atKey.metadata = metadataForEncryptedSend\n  try:\n    await CryptoRuntime, _routingFor, CryptoRuntime(this).prepareWrite\n  on NamespaceKeyUnavailableException:\n    if !mayFallBackToLegacy(_preference):\n      rethrow\n    options = copyOptionsForLegacyFallback\nelse:\n  if !atKey.metadata.isPublic \u0026\u0026 !options.shouldEncrypt \u0026\u0026 !options.alreadyEncrypted:\n    atKey.metadata = metadataForEncryptedSend\ntuple = Tuple\nif atKey.metadata.isPublic == true:\n  try:\n    encryptionPrivateKey = await localSecondary.getEncryptionPrivateKey\n  on KeyNotFoundException:\nputBuilder = await putRequestTransformer.transform\nif putBuilder.value.length \u003e _preference!.maxDataSize:\n  throw BufferOverFlowException('The length of …\nputResponse = await _routingFor, executeUpdateOrDelete\nif putResponse == null || putResponse.isEmpty:\n  return AtResponse()..isError = true\nreturn await PutResponseTransformer().transform(putResponse)\n",
   "snippet": {
    "cut": false,
    "text": "  Future\u003cAtResponse\u003e _putInternal(\n    AtKey atKey,\n    dynamic value,\n    PutRequestOptions? putRequestOptions,\n  ) async {\n    _refuseNoCommitWithoutRemote(putRequestOptions?.noCommit ?? false,\n        _routingFor(atKey, putRequestOptions?.useRemoteAtServer));\n    // Performs the put request validations.\n    AtClientValidation.validatePutRequest(atKey, value, preference!);\n    // Set sharedBy to currentAtSign if not set.\n    if (atKey.sharedBy.isNull) {\n      atKey.sharedBy = _atSign;\n    }\n    if (atKey.metadata.namespaceAware) {\n      atKey.namespace ??= preference?.namespace;\n    }\n\n    ensureLowerCase(atKey);\n\n    var validationResult = AtKeyValidators.get().validate(\n      atKey.toString(),\n      ValidationContext()\n        ..atSign = _atSign\n        ..validateOwnership = true\n        ..enforceNamespace = !atKey.isLocal,\n    );\n    // If the validationResult.isValid is false, validation of AtKey failed.\n    // throw AtClientException with failure reason.\n    if (!validationResult.isValid) {\n      throw AtKeyException(validationResult.failureReason);\n    }\n    // NOTE: the provider that will encrypt this write acts before the pipeline\n    // starts — minting a content key means writing a conveyance record, and\n    // that cannot happen once the transformer is mid-way through building a\n    // verb builder. A `local:` record is excluded: it is never synced to the\n    // atServer, and every post-quantum provider declines a local key.\n    var options = putRequestOptions ?? PutRequestTransformer.defaultOptions;\n    if (!atKey.metadata.isPublic \u0026\u0026 !atKey.isLocal \u0026\u0026 options.shouldEncrypt) {\n      atKey.metadata = metadataForEncryptedSend(atKey.metadata);\n      try {\n        await CryptoRuntime(this).prepareWrite(\n          atKey,\n          requestedProviderId: options.cryptoProviderId,\n          // Any record the provider writes here is one this write will cite, so\n          // it has to travel the same route this write does.\n          useRemoteAtServer:\n              _routingFor(atKey, putRequestOptions?.useRemoteAtServer) ==\n                  RemoteLocalPref.remoteOnly,\n          // Not stamped here: the catch below may re-route this write to\n          // legacy, and a key stamped with the provider that then declined\n          // would claim a scheme its value was never sealed under.\n          stampProviderId: false,\n        );\n      } on NamespaceKeyUnavailableException catch (e) {\n        if (!mayFallBackToLegacy(_preference)) rethrow;\n        _logger.warning(\n            'falling back to legacy encryption for ${atKey.key}: ${e.message}');\n        options = copyOptionsForLegacyFallback(options);\n      }\n    } else if (!atKey.metadata.isPublic \u0026\u0026\n        !options.shouldEncrypt \u0026\u0026\n        !options.alreadyEncrypted) {\n      atKey.metadata = metadataForEncryptedSend(atKey.metadata);\n    }\n\n    var tuple = Tuple\u003cAtKey, dynamic\u003e()\n      ..one = atKey\n      ..two = value;\n\n    //Get encryptionPrivateKey for public key to signData\n    String? encryptionPrivateKey;\n    if (atKey.metadata.isPublic == true) {\n      try {\n        encryptionPrivateKey = await localSecondary?.getEncryptionPrivateKey();\n      } on KeyNotFoundException {\n        // Left null: the transformer refuses to sign with the message a\n        // caller acts on, rather than the keystore's record name.\n      }\n    }\n    // Transform put request\n    // Optionally passing encryption private key to sign the public data.\n    UpdateVerbBuilder putBuilder = await putRequestTransformer.transform(\n      tuple,\n      encryptionPrivateKey: encryptionPrivateKey,\n      // NOTE: `options`, not `putRequestOptions` — a legacy fallback is\n      // expressed by rewriting the options, and the transformer is where the\n      // provider is finally selected.\n      requestOptions: options,\n    );\n    // Validate the size of the value after encryption/encoding\n    // Since AtClientPreference is mandatory argument in create method, _preference\n    // will not be null.\n    if (putBuilder.value.length \u003e _preference!.maxDataSize) {\n      throw BufferOverFlowException(\n        'The length of value exceeds the maximum allowed length. Maximum buffer size is ${_preference!.maxDataSize} bytes. Found ${value.toString().length} bytes',\n      );\n    }\n\n    var putResponse = await executeUpdateOrDelete(\n        putBuilder, _routingFor(atKey, putRequestOptions?.useRemoteAtServer));\n\n    // If putResponse is null or empty, return AtResponse with isError set to true\n    if (putResponse == null || putResponse.isEmpty) {\n      return AtResponse()..isError = true;\n    }\n    return await PutResponseTransformer().transform(putResponse);\n  }"
   },
   "sublane": "AtClient",
   "touches": []
  },
  {
   "anchor": {
    "contains": "AESEncryptionAlgo(AESKey(sharedKey))",
    "path": "packages/at_client/lib/src/crypto/legacy/legacy_encryption.dart",
    "root": "sdk",
    "symbol": "SharedKeyEncryption.encrypt",
    "url": "../../packages/at_client/lib/src/crypto/legacy/legacy_encryption.dart"
   },
   "changed": false,
   "contracts": [],
   "hash": "a6853990e3db8960",
   "id": "alice-encrypt",
   "intent": "With the legacy crypto provider, encrypt the value under the symmetric key @alice shares with @bob, with a fresh IV.",
   "lane": "alice.client",
   "links": [],
   "reached": {
    "from": "alice-put",
    "kind": "untraced",
    "text": "via (untraced): the put transformer reaches it through the crypto provider the key's write selected"
   },
   "reviewed": "a6853990e3db8960",
   "skeleton": "if value is! String:\n  throw AtEncryptionException('Invalid value ty…\nawait super.encrypt\ntry:\n  atKey.metadata.ivNonce = EncryptionUtil.generateIV\n  iV = InitialisationVector.fromBase64\n  encryptionAlgo = AESKey, AESEncryptionAlgo\n  encryptedValue = await encryptStringToBase64\non AtEncryptionException:\n  rethrow\nreturn encryptedValue\n",
   "snippet": {
    "cut": false,
    "text": "  Future\u003cdynamic\u003e encrypt(AtKey atKey, dynamic value) async {\n    if (value is! String) {\n      throw AtEncryptionException(\n          'Invalid value type found: ${value.runtimeType}. Valid value type is String');\n    }\n\n    // Call super.encrypt to take care of getting hold of the correct\n    // encryption key and setting it in super.sharedKey\n    await super.encrypt(atKey, value);\n    String encryptedValue;\n    try {\n      // NOTE: AES here is CTR, so a (key, IV) pair must never encrypt twice;\n      // the IV is new for every value, whatever the key already carries.\n      atKey.metadata.ivNonce = EncryptionUtil.generateIV();\n      final iV = InitialisationVector.fromBase64(atKey.metadata.ivNonce!);\n      var encryptionAlgo = AESEncryptionAlgo(AESKey(sharedKey));\n      encryptedValue =\n          await encryptStringToBase64(value, encryptionAlgo, iv: iV);\n    } on AtEncryptionException catch (e) {\n      _logger.severe(\n          'encryption exception during shared key encryption of key: ${atKey.key}. Reason: ${e.toString()}');\n      rethrow;\n    }\n    return encryptedValue;\n  }"
   },
   "sublane": "Crypto",
   "touches": []
  },
  {
   "anchor": {
    "contains": "return await localSecondary!.executeVerb(builder);",
    "path": "packages/at_client/lib/src/client/at_client_impl.dart",
    "root": "sdk",
    "symbol": "AtClientImpl.executeUpdateOrDelete",
    "url": "../../packages/at_client/lib/src/client/at_client_impl.dart"
   },
   "changed": false,
   "contracts": [],
   "hash": "06f7912c16904574",
   "id": "alice-route",
   "intent": "Send the update to local storage, the default, or straight to @alice's atServer when the write asks for remote.",
   "lane": "alice.client",
   "links": [],
   "reached": {
    "from": "alice-put",
    "kind": "call",
    "text": "call"
   },
   "reviewed": "06f7912c16904574",
   "skeleton": "switch prefForOp:\n  case RemoteLocalPref.localOnly:\n    return await localSecondary!.executeVerb(builder)\n  case RemoteLocalPref.remoteOnly:\n    return await _remoteSecondary!.executeVerb(builder)\n",
   "snippet": {
    "cut": false,
    "text": "  Future\u003cString?\u003e executeUpdateOrDelete(\n    VerbBuilder builder,\n    RemoteLocalPref prefForOp,\n  ) async {\n    switch (prefForOp) {\n      case RemoteLocalPref.localOnly:\n        return await localSecondary!.executeVerb(builder);\n      case RemoteLocalPref.remoteOnly:\n        return await _remoteSecondary!.executeVerb(builder);\n    }\n  }"
   },
   "sublane": "AtClient",
   "touches": []
  },
  {
   "anchor": {
    "contains": "await q.enqueue(atKey, op);",
    "path": "packages/at_client/lib/src/client/local_secondary.dart",
    "root": "sdk",
    "symbol": "LocalSecondary._enqueueForSync",
    "url": "../../packages/at_client/lib/src/client/local_secondary.dart"
   },
   "changed": false,
   "contracts": [],
   "hash": "6b761184a3641116",
   "id": "alice-enqueue",
   "intent": "Once the local write succeeds, queue the record's name for sync and ask the sync service to drain the queue.",
   "lane": "alice.client",
   "links": [],
   "reached": {
    "from": "alice-route",
    "kind": "via",
    "text": "via LocalSecondary.executeVerb, LocalSecondary._update",
    "via": [
     "LocalSecondary.executeVerb",
     "LocalSecondary._update"
    ]
   },
   "reviewed": "6b761184a3641116",
   "skeleton": "if cameFromServer:\n  return\nif !shouldEnqueueForSync(atKey, op):\n  return\ntry:\n  q = await _liveSyncQueue\n  await q.enqueue\non any:\n  if e is StoppedException:\n    rethrow\n  return\ntry:\n  _atClient.syncService.sync\non any:\n  if _atClient.isStopped:\n    return\n",
   "snippet": {
    "cut": false,
    "text": "  Future\u003cvoid\u003e _enqueueForSync(\n    String atKey,\n    SyncQueueOp op, {\n    required bool cameFromServer,\n  }) async {\n    if (cameFromServer) return;\n    if (!shouldEnqueueForSync(atKey, op)) return;\n    // NOTE: two operations, so two try blocks. Queueing the write is the\n    // durable half; asking the sync service to drain is a best-effort nudge on\n    // top of it. One catch across both reported every trigger failure as a\n    // failure to enqueue, which names the wrong half: the write was already\n    // safely queued.\n    try {\n      final q = await _liveSyncQueue();\n      await q.enqueue(atKey, op);\n    } catch (e, st) {\n      if (e is StoppedException) rethrow;\n      // The write is not queued, so nothing will push it until the box\n      // becomes accessible again and the periodic safety-net timer finds it.\n      _logger.shout('failed to enqueue $atKey for sync: $e\\n$st');\n      return;\n    }\n\n    try {\n      // Trigger SyncServiceImpl to drain. Today this enqueues a\n      // sync request via the existing request-coalescing layer\n      // (`_addSyncRequestToQueue` → microtask → `processSyncRequests`).\n      // The sync service then peeks our queue and pushes batches.\n      _atClient.syncService.sync();\n    } catch (e, st) {\n      if (_atClient.isStopped) return;\n      logSwallowed(\n          _logger,\n          e,\n          '$atKey is queued for sync, but the sync service could '\n          'not be asked to drain, so it waits for the next trigger or for the '\n          'periodic safety net: $e\\n$st');\n    }\n  }"
   },
   "sublane": "LocalSecondary",
   "touches": [
    "sync-queue"
   ]
  },
  {
   "anchor": {
    "contains": "batchResponse = await sendBatch(batchRequests);",
    "path": "packages/at_client/lib/src/service/sync_service_impl.dart",
    "root": "sdk",
    "symbol": "SyncServiceImpl._pushFromSyncQueue",
    "url": "../../packages/at_client/lib/src/service/sync_service_impl.dart"
   },
   "changed": false,
   "contracts": [],
   "hash": "45f6fb828b67912e",
   "id": "alice-push",
   "intent": "Read queued names a batch at a time, build each record's update from local storage, and send the batch to @alice's atServer.",
   "lane": "alice.client",
   "links": [],
   "reached": {
    "from": "alice-enqueue",
    "kind": "declared",
    "note": "the queue is durable, so the push may run in a later session than the write",
    "text": "declared hop through AtSyncQueue",
    "through": "AtSyncQueue"
   },
   "reviewed": "45f6fb828b67912e",
   "skeleton": "localSecondary = _atClient.getLocalSecondary\nbatchSize = _atClient.getPreferences\nloop while true:\n  _throwIfStopped\n  atKeys = await localSecondary.peekSyncQueue\n  _bailIfStopped\n  _bailIfStopped\n  loop final atKey in atKeys:\n    entry = await localSecondary.readSyncQueueEntry\n    _bailIfStopped\n    if entry == null:\n      await localSecondary.removeFromSyncQueue\n      _bailIfStopped\n    try:\n      command = await _buildCommandFromQueueEntry\n      _bailIfStopped\n    on KeyNotFoundException:\n      await localSecondary.removeFromSyncQueueIfUnchanged\n      _bailIfStopped\n    VerbUtil.replaceNewline, BatchRequest, batchRequests.add\n    _BatchSource, batchSources.add\n  try:\n    batchResponse = await sendBatch\n    _bailIfStopped\n  on _SyncAbandoned:\n    rethrow\n  on Exception:\n    if e is StoppedException || isStopped:\n      throw _SyncAbandoned\n    cause = e.getTraceMessage, e.toString\n    return keyInfoList\n  loop final entry in batchResponse:\n    try:\n      responseObject = Response.fromJson\n      source = batchSources.elementAt\n      if responseObject.data != null:\n        commitId = int.parse\n      _promoteServerCommitId\n      if _highestPushedCommitId == null || commitId \u003e _highestPushedCommitId!:\n        _highestPushedCommitId = commitId\n      removed = await localSecondary.removeFromSyncQueueIfUnchanged\n      _bailIfStopped\n      _syncQueueOpToCommitOp, KeyInfo, keyInfoList.add\n    on _SyncAbandoned:\n      rethrow\n    on Exception:\n      if e is StoppedException || isStopped:\n        throw _SyncAbandoned\n      cause = e.getTraceMessage, e.toString\n  SyncProgress, DateTime.now, DateTime.now().toUtc, new List, _informSyncProgress\n  _bailIfStopped\n  _bailIfStopped\n  pendingFront = await localSecondary.peekSyncQueue\n  _bailIfStopped\n  atKeysSet = atKeys.toSet\n  allBatchKeysStillPresent = atKeysSet.contains\nreturn keyInfoList\n",
   "snippet": {
    "cut": true,
    "text": "  Future\u003cList\u003cKeyInfo\u003e\u003e _pushFromSyncQueue() async {\n    final localSecondary = _atClient.getLocalSecondary()!;\n    final batchSize = _atClient.getPreferences()!.syncBatchSize;\n    final keyInfoList = \u003cKeyInfo\u003e[];\n    var batchesDone = 0;\n    while (true) {\n      _throwIfStopped();\n      final atKeys = await localSecondary.peekSyncQueue(limit: batchSize);\n      _bailIfStopped();\n      if (atKeys.isEmpty) break;\n      // Snapshot the queue size BEFORE this batch so the\n      // no-progress guard at the bottom can detect \"the entries\n      // we just tried didn't get removed\" without conflating it\n      // with \"the queue is large because more writes arrived\".\n      final queueSizeBefore = await localSecondary.syncQueueSize;\n      _bailIfStopped();\n      // Build the batch. Order in `batchRequests` mirrors the order\n      // we got from `peekSyncQueue` — and the response comes back\n      // 1-indexed by batch id, so index N-1 in our list is the entry\n      // for batch id N. Track the source atKey + op alongside so we\n      // can correlate the response without re-parsing the wire.\n      final batchRequests = \u003cBatchRequest\u003e[];\n      final batchSources = \u003c_BatchSource\u003e[];\n      for (final atKey in atKeys) {\n        final entry = await localSecondary.readSyncQueueEntry(atKey);\n        _bailIfStopped();\n        if (entry == null) {\n          // The queue says we should push this atKey but the\n          // persisted record is gone (rare race — concurrent remove,\n          // or replay-time corruption). Drop it.\n          _logger.warning(\n              'sync queue race: $atKey missing persisted record; removing');\n          await localSecondary.removeFromSyncQueue(atKey);\n          _bailIfStopped();\n          continue;\n        }\n        final String command;\n        try {\n          command = await _buildCommandFromQueueEntry(atKey, entry.op);\n          _bailIfStopped();\n        } on KeyNotFoundException {\n          // The keystore doesn't have a value for this atKey\n          // (UPDATE / UPDATE_ALL / UPDATE_META). The race-tolerated\n          // case: queue write committed but the backing keystore\n          // write never landed (a crash between them). Drop the\n          // queue entry — there's nothing we can push, and the\n          // user-level write is already lost. Version-checked: a delete\n          // needs no keystore value, so one that replaced this entry after\n          // the read above must survive this drop and push next round.\n          _logger\n              .info('keystore miss for $atKey on push; dropping queue entry');\n          await localSecondary.removeFromSyncQueueIfUnchanged(atKey, entry.seq);\n          _bailIfStopped();\n          continue;\n        }\n        _logger.info('Will push ${entry.op} for $atKey');\n        final batchId = batchRequests.length + 1;\n        batchRequests\n            .add(BatchRequest(batchId, VerbUtil.replaceNewline(command)));\n        batchSources.add(_BatchSource(\n          atKey: atKey,\n          op: entry.op,\n          seq: entry.seq,\n        ));\n      }\n      if (batchRequests.isEmpty) {\n        // Every queued atKey we pulled was a phantom; loop and try\n        // the next batch (the queue may still have more).\n        continue;\n      }\n      var rewrittenMidPush = 0;\n      List\u003cdynamic\u003e batchResponse;\n      try {\n        batchResponse = await sendBatch(batchRequests);\n        _bailIfStopped();\n      } on _SyncAbandoned {\n        rethrow;\n      } on Exception catch (e) {\n        if (e is StoppedException || isStopped) throw const _SyncAbandoned();\n        // Network or auth failure for the whole batch. Leave queue\n        // entries in place — next round retries.\n        final cause = (e is AtException) ? e.getTraceMessage() : e.toString();\n        _logger.severe('sendBatch failed: $cause');\n        return keyInfoList;\n      }\n      for (final entry in batchResponse) {\n        try {\n          final batchId = entry['id'] as int;\n          final serverResponse = entry['response'];\n          final responseObject = Response.fromJson(serverResponse);\n          final source = batchSources.elementAt(batchId - 1);\n          var commitId = -1;\n          if (responseObject.data != null) {\n            commitId = int.parse(responseObject.data!);\n          }\n          if (commitId == -1) {\n            _logger.severe(\n                '${source.op} for key ${source.atKey} failed. Error code '\n                '${responseObject.errorCode} error message '\n                '${responseObject.errorMessage}');\n            // Leave in queue for retry. Don't remove.\n            continue;\n          }\n          _promoteServerCommitId(commitId);\n          // Track the high-water mark of OUR successful pushes\n          // separately from the broader server cursor so\n          // [_getLocalCommitId] reflects \"our writes the server has\n          // acked\" alongside the pull-side cursor. Commit-log-free:\n          // there is no local commit-log entry to back-write the\n          // server-assigned commitId onto — the durable watermark is\n          // the persisted pull cursor (`_lastReceivedServerCommitIdAtKey`).\n          if (_highestPushedCommitId == null ||\n              commitId \u003e _highestPushedCommitId!) {\n            _highestPushedCommitId = commitId;\n          }\n          final removed = await localSecondary.removeFromSyncQueueIfUnchanged(\n              source.atKey, source.seq);\n          if (!removed) {\n            // NOTE: a newer local write to this atKey replaced the queue entry\n            // while this batch was in flight. The server has the version this\n            // batch carried and the newer op pushes next round, so removing\n            // the entry unconditionally here would lose it.\n            rewrittenMidPush++;\n            _logger.finer('${source.atKey} re-enqueued mid-push; '\n                'keeping the newer entry queued for the next round');\n          }\n          _bailIfStopped();\n          keyInfoList.add(KeyInfo(\n            source.atKey,\n            SyncDirection.localToRemote,\n            _syncQueueOpToCommitOp(source.op),\n          ));\n        } on _SyncAbandoned {\n          rethrow;\n        } on Exception catch (e) {\n          if (e is StoppedException || isStopped) throw const _SyncAbandoned();\n          final cause = (e is AtException) ? e.getTraceMessage() : e.toString();\n          _logger.severe(\n              'exception processing batch response entry $entry: $cause');\n        }\n      }\n      batchesDone++;\n      // Snapshot keyInfoList AT this point so per-batch listeners\n      // see every push as it lands, not only at the terminal\n      // `Sync complete` event in `processSyncRequests`. If anything\n      // between `syncInternal` returning and that terminal emission\n      // throws (network blip on `_getServerCommitId` / `_getLocalCommitId`,\n      // a stop() racing the completion), the push KeyInfos would\n      // otherwise be silently dropped — listeners would never see\n      // a `localToRemote` event for keys that DID land on the server.\n      _informSyncProgress(\n        SyncProgress()\n          ..syncStatus = SyncStatus.inProgress\n          ..startedAt = DateTime.now().toUtc()\n          ..message = 'Push batch $batchesDone applied; '\n              '${await localSecondary.syncQueueSize} pending'\n          ..keyInfoList = List\u003cKeyInfo\u003e.from(keyInfoList),\n        localCommitId: _latestKnownServerCommitId,\n        serverCommitId: _latestKnownServerCommitId,\n      );"
   },
   "sublane": "SyncService",
   "touches": [
    "sync-queue"
   ]
  },
  {
   "anchor": {
    "contains": "verbHandlerManager.getVerbHandler(command)",
    "lines": [
     45,
     91
    ],
    "match": 63,
    "path": "packages/at_secondary_server/lib/src/verb/handler/batch_verb_handler.dart",
    "root": "server",
    "symbol": "BatchVerbHandler.processVerb",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/batch_verb_handler.dart#L45-L91"
   },
   "changed": false,
   "contracts": [],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "guard": "batchJson is! List",
      "id": "BatchVerbHandler.processVerb batchJson is! List throw",
      "kind": "throw",
      "messages": [
       "'a batch is a list of entries'"
      ],
      "symbol": "BatchVerbHandler.processVerb",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/batch_verb_handler.dart#L52"
     }
    ]
   },
   "hash": "080ed912f887cb2c",
   "id": "alice-server-batch",
   "intent": "Parse the batch and hand each entry's command to the handler dispatch chooses, answering each entry on its own.",
   "lane": "alice.server",
   "links": [],
   "reached": {
    "from": "alice-push",
    "kind": "wire",
    "replay": [
     {
      "commons": "at_commons 5.24.0 (at_server's lock)",
      "handler": "BatchVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.batch"
     },
     {
      "commons": "at_commons 5.25.0 (this checkout)",
      "handler": "BatchVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.batch"
     }
    ],
    "sample": "batch:[{\"id\":1,\"command\":\"update:@bob:note.ns@alice bm90IGEgcmVhbCBjaXBoZXJ0ZXh0\"}]",
    "text": "wire batch:",
    "verb": "batch",
    "via": []
   },
   "reviewed": "080ed912f887cb2c",
   "skeleton": "batchJson = jsonDecode\nif batchJson is! List:\n  throw InvalidSyntaxException('a batch is a li…\nloop var value in batchJson:\n  try:\n    if (id != null \u0026\u0026 batchId == null) || command is! String:\n      throw InvalidSyntaxException('invalid batch e…\n    verbHandler = verbHandlerManager.getVerbHandler\n    if verbHandler is! AbstractVerbHandler:\n      throw InvalidSyntaxException('invalid command…\n    if verbHandler is CramVerbHandler || verbHandler is PkamVerbHandler:\n      throw UnAuthorizedException(authenticationRef…\n    response = await verbHandler.processInternal\n    batchResponse = BatchResponse\n    batchResponses.add\n  on Exception:\n    response = Response\n    response.errorCode = GlobalExceptionHandler.getInstance, GlobalExceptionHandler.getIns….getErrorCode\n    if response.errorCode != null:\n      response.errorMessage = GlobalExceptionHandler.getInstance, GlobalExceptionHandler.getIns….getErrorDescription\n      batchResponse = BatchResponse\n      batchResponses.add\nresponse.data = jsonEncode\n",
   "snippet": {
    "cut": false,
    "startLine": 45,
    "text": "  Future\u003cvoid\u003e processVerb(\n      Response response,\n      HashMap\u003cString, String?\u003e verbParams,\n      InboundConnection atConnection) async {\n    var batchCommand = verbParams['json']!;\n    var batchJson = jsonDecode(batchCommand);\n    if (batchJson is! List) {\n      throw InvalidSyntaxException('a batch is a list of entries');\n    }\n    var batchResponses = \u003cBatchResponse\u003e[];\n    for (var value in batchJson) {\n      final Object? id = value is Map ? value['id'] : null;\n      final int? batchId = id is int ? id : null;\n      try {\n        final Object? command = value is Map ? value['command'] : null;\n        if ((id != null \u0026\u0026 batchId == null) || command is! String) {\n          throw InvalidSyntaxException('invalid batch entry');\n        }\n        var verbHandler = verbHandlerManager.getVerbHandler(command);\n        if (verbHandler is! AbstractVerbHandler) {\n          throw InvalidSyntaxException('invalid command');\n        }\n        if (verbHandler is CramVerbHandler || verbHandler is PkamVerbHandler) {\n          logger.warning('Refusing entry $batchId of a batch on session '\n              '${atConnection.metaData.sessionID}: $authenticationRefusal');\n          throw UnAuthorizedException(authenticationRefusal);\n        }\n        var response = await verbHandler.processInternal(command, atConnection);\n        var batchResponse = BatchResponse(batchId, response);\n        batchResponses.add(batchResponse);\n      } on Exception catch (e) {\n        var response = Response();\n        response.errorCode =\n            GlobalExceptionHandler.getInstance().getErrorCode(e);\n        if (response.errorCode != null) {\n          response.errorMessage = GlobalExceptionHandler.getInstance()\n              .getErrorDescription(response.errorCode);\n          var batchResponse = BatchResponse(batchId, response);\n          batchResponses.add(batchResponse);\n        } else {\n          logger.severe(\n              'No error code found. Exception executing command in a batch. ${e.toString()}');\n        }\n      }\n    }\n    response.data = jsonEncode(batchResponses);\n  }"
   },
   "touches": []
  },
  {
   "anchor": {
    "contains": "await super.notifyAfterStore(",
    "lines": [
     34,
     104
    ],
    "match": 86,
    "path": "packages/at_secondary_server/lib/src/verb/handler/update_verb_handler.dart",
    "root": "server",
    "symbol": "UpdateVerbHandler.processVerb",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/update_verb_handler.dart#L34-L104"
   },
   "changed": false,
   "contracts": [
    {
     "backing": {
      "exit": {
       "guard": "!isAuthorized",
       "kind": "throw",
       "symbol": "AbstractUpdateVerbHandler.preProcess",
       "type": "UnAuthorizedException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L95"
      }
     },
     "kind": "refuses",
     "label": "enforced by alice.server",
     "text": "a write the connection's enrollment is not authorized to make"
    },
    {
     "backing": {
      "exit": {
       "guard": "reserved != null",
       "kind": "throw",
       "symbol": "AbstractUpdateVerbHandler.preProcess",
       "type": "UnAuthorizedException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L103"
      }
     },
     "kind": "refuses",
     "label": "enforced by alice.server",
     "text": "a write into a reserved namespace"
    }
   ],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [
       "verbParams['json'] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams"
      ],
      "guard": "on AtException",
      "id": "AbstractUpdateVerbHandler.getUpdateParams on AtException rethrow",
      "kind": "rethrow",
      "messages": [],
      "symbol": "AbstractUpdateVerbHandler.getUpdateParams",
      "type": "AtException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L336"
     },
     {
      "branch": [
       "verbParams['json'] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams"
      ],
      "guard": "catch",
      "id": "AbstractUpdateVerbHandler.getUpdateParams catch throw",
      "kind": "throw",
      "messages": [
       "'invalid update:json document: $e'"
      ],
      "symbol": "AbstractUpdateVerbHandler.getUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L340"
     },
     {
      "branch": [
       "verbParams['json'] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateJsonUpdateParams"
      ],
      "guard": "value is! String || !_grammarValue.hasMatch(value)",
      "id": "AbstractUpdateVerbHandler._validateJsonUpdateParams value is! String || !_grammarValue.hasMatch(value) throw",
      "kind": "throw",
      "messages": [
       "'invalid value: update:json requires a non-empty, single-line' ' string, as the update grammar does'"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateJsonUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L456"
     },
     {
      "branch": [
       "verbParams['json'] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateJsonUpdateParams"
      ],
      "guard": "owner \u003e 0 \u0026\u0026 atKey.substring(owner) != canonicalAtKey(atSign)",
      "id": "AbstractUpdateVerbHandler._validateJsonUpdateParams owner \u003e 0 \u0026\u0026 atKey.substring(owner) != canonicalAtKey(atSign) throw",
      "kind": "throw",
      "messages": [
       "message"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateJsonUpdateParams",
      "type": "InvalidAtKeyException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L477"
     },
     {
      "branch": [
       "verbParams['json'] != null",
       "!(metadata == null)",
       "metadata.ttr != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateJsonUpdateParams",
       "validateTTR"
      ],
      "guard": "ttrMs \u003c= -2",
      "id": "validateTTR ttrMs \u003c= -2 throw",
      "kind": "throw",
      "messages": [
       "'Valid values for TTR are -1 and greater than or equal to 0'"
      ],
      "symbol": "validateTTR",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/utils/handler_util.dart#L19"
     },
     {
      "branch": [
       "verbParams['json'] != null",
       "!(metadata == null)"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateJsonUpdateParams"
      ],
      "guard": "metadata.isPublic == true \u0026\u0026 updateParams.sharedWith.isNotNullOrEmpty",
      "id": "AbstractUpdateVerbHandler._validateJsonUpdateParams metadata.isPublic == true \u0026\u0026 updateParams.sharedWith.isNotNullOrEmpty throw",
      "kind": "throw",
      "messages": [
       "'invalid update:json document: a key cannot be public and shared' ' with ${updateParams.sharedWith} at once'"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateJsonUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L495"
     },
     {
      "branch": [
       "verbParams['json'] != null",
       "!(metadata == null)",
       "each asserted in {'createdAt' : metadata.createdAt, 'updatedAt' : metadata.updatedAt, 'expiresAt' : metadata.expiresAt, 'availableAt' : metadata.availableAt}.entries"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateJsonUpdateParams"
      ],
      "guard": "asserted.value != null \u0026\u0026 !asserted.value!.isUtc",
      "id": "AbstractUpdateVerbHandler._validateJsonUpdateParams asserted.value != null \u0026\u0026 !asserted.value!.isUtc throw",
      "kind": "throw",
      "messages": [
       "'invalid update:json document: ${asserted.key} must be UTC, as' ' the update grammar requires'"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateJsonUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L509"
     },
     {
      "branch": [
       "verbParams['json'] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateUpdateParams"
      ],
      "guard": "updateParams.atKey == null || updateParams.atKey!.isEmpty",
      "id": "AbstractUpdateVerbHandler._validateUpdateParams updateParams.atKey == null || updateParams.atKey!.isEmpty throw",
      "kind": "throw",
      "messages": [
       "'atKey.key not supplied'"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L435"
     },
     {
      "branch": [
       "verbParams['json'] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateUpdateParams"
      ],
      "guard": "updateParams.sharedBy != null \u0026\u0026 updateParams.sharedBy!.isNotEmpty \u0026\u0026 updateParams.sharedBy != atSign",
      "id": "AbstractUpdateVerbHandler._validateUpdateParams updateParams.sharedBy != null \u0026\u0026 updateParams.sharedBy!.isNotEmpty \u0026\u0026 updateParams.sharedBy != atSign throw",
      "kind": "throw",
      "messages": [
       "message"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateUpdateParams",
      "type": "InvalidAtKeyException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L446"
     },
     {
      "branch": [
       "!(verbParams['json'] != null)",
       "verbParams[AtConstants.ttr] != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "validateTTR"
      ],
      "guard": "ttrMs \u003c= -2",
      "id": "validateTTR ttrMs \u003c= -2 throw #2",
      "kind": "throw",
      "messages": [
       "'Valid values for TTR are -1 and greater than or equal to 0'"
      ],
      "symbol": "validateTTR",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/utils/handler_util.dart#L19"
     },
     {
      "branch": [
       "!(verbParams['json'] != null)"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams"
      ],
      "guard": "on FormatException",
      "id": "AbstractUpdateVerbHandler.getUpdateParams on FormatException throw",
      "kind": "throw",
      "messages": [
       "'invalid ${AtConstants.appMetadata}: ${e.message}'"
      ],
      "symbol": "AbstractUpdateVerbHandler.getUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L419"
     },
     {
      "branch": [
       "!(verbParams['json'] != null)"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateUpdateParams"
      ],
      "guard": "updateParams.atKey == null || updateParams.atKey!.isEmpty",
      "id": "AbstractUpdateVerbHandler._validateUpdateParams updateParams.atKey == null || updateParams.atKey!.isEmpty throw #2",
      "kind": "throw",
      "messages": [
       "'atKey.key not supplied'"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateUpdateParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L435"
     },
     {
      "branch": [
       "!(verbParams['json'] != null)"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.getUpdateParams",
       "AbstractUpdateVerbHandler._validateUpdateParams"
      ],
      "guard": "updateParams.sharedBy != null \u0026\u0026 updateParams.sharedBy!.isNotEmpty \u0026\u0026 updateParams.sharedBy != atSign",
      "id": "AbstractUpdateVerbHandler._validateUpdateParams updateParams.sharedBy != null \u0026\u0026 updateParams.sharedBy!.isNotEmpty \u0026\u0026 updateParams.sharedBy != atSign throw #2",
      "kind": "throw",
      "messages": [
       "message"
      ],
      "symbol": "AbstractUpdateVerbHandler._validateUpdateParams",
      "type": "InvalidAtKeyException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L446"
     },
     {
      "branch": [
       "!(atKey == null || !isWritingVerb())",
       "!(canonicalAtKey(atKey) != AtConstants.atPkamPublicKey)"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "AbstractVerbHandler.isAuthorized",
       "AbstractVerbHandler.refuseFlatCredentialWrite"
      ],
      "guard": "!(isCramConnection(md) \u0026\u0026 getVerb() is Update)",
      "id": "AbstractVerbHandler.refuseFlatCredentialWrite !(isCramConnection(md) \u0026\u0026 getVerb() is Update) throw",
      "kind": "throw",
      "messages": [
       "flatCredentialWriteRefusal"
      ],
      "symbol": "AbstractVerbHandler.refuseFlatCredentialWrite",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_verb_handler.dart#L242"
     },
     {
      "branch": [
       "!(atKey == null || !isMutatingVerb())"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "AbstractVerbHandler.isAuthorized",
       "AbstractVerbHandler.refuseTelemetryKeyMutation"
      ],
      "guard": "AtServerTelemetryKeyGuard.isTelemetryKey(atKey)",
      "id": "AbstractVerbHandler.refuseTelemetryKeyMutation AtServerTelemetryKeyGuard.isTelemetryKey(atKey) throw",
      "kind": "throw",
      "messages": [
       "AtServerTelemetryKeyGuard.refusal"
      ],
      "symbol": "AbstractVerbHandler.refuseTelemetryKeyMutation",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_verb_handler.dart#L251"
     },
     {
      "branch": [
       "!isCramConnection(inboundConnectionMetadata)",
       "!(enrollmentId == null)",
       "!cram",
       "!(enrollmentId == null || enrollDataStoreValue == null)",
       "!(enrollDataStoreValue.approval?.state != EnrollmentStatus.approved.name)"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "AbstractVerbHandler.isAuthorized",
       "AbstractVerbHandler.isAuthorizedSync",
       "AbstractVerbHandler._applyEnrollmentValidations"
      ],
      "guard": "operation.isNotEmpty \u0026\u0026 enrollDataStoreValue.namespaces.containsKey(EnrollmentConstants.enrollManageNamespace) == false",
      "id": "AbstractVerbHandler._applyEnrollmentValidations operation.isNotEmpty \u0026\u0026 enrollDataStoreValue.namespaces.containsKey(EnrollmentConstants.enrollManageNamespace) == false throw",
      "kind": "throw",
      "messages": [
       "'The approving enrollment does not have access' ' to \"__manage\" namespace'"
      ],
      "symbol": "AbstractVerbHandler._applyEnrollmentValidations",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_verb_handler.dart#L419"
     },
     {
      "branch": [
       "!isCramConnection(inboundConnectionMetadata)",
       "!(enrollmentId == null)",
       "!cram",
       "!(enrollmentId == null || enrollDataStoreValue == null)",
       "!(enrollDataStoreValue.approval?.state != EnrollmentStatus.approved.name)",
       "atKey != null \u0026\u0026 namespace != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "AbstractVerbHandler.isAuthorized",
       "AbstractVerbHandler.isAuthorizedSync",
       "AbstractVerbHandler._applyEnrollmentValidations"
      ],
      "guard": "catch",
      "id": "AbstractVerbHandler._applyEnrollmentValidations catch throw",
      "kind": "throw",
      "messages": [
       "'AtKey.fromString($atKey) failed: $e'"
      ],
      "symbol": "AbstractVerbHandler._applyEnrollmentValidations",
      "type": "IllegalArgumentException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_verb_handler.dart#L429"
     },
     {
      "branch": [
       "!isCramConnection(inboundConnectionMetadata)",
       "!(enrollmentId == null)",
       "!cram",
       "!(enrollmentId == null || enrollDataStoreValue == null)",
       "!(enrollDataStoreValue.approval?.state != EnrollmentStatus.approved.name)",
       "atKey != null \u0026\u0026 namespace != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "AbstractVerbHandler.isAuthorized",
       "AbstractVerbHandler.isAuthorizedSync",
       "AbstractVerbHandler._applyEnrollmentValidations"
      ],
      "guard": "atKeyObj.namespace != namespace",
      "id": "AbstractVerbHandler._applyEnrollmentValidations atKeyObj.namespace != namespace throw",
      "kind": "throw",
      "messages": [
       "'AtKey namespace and passed namespace do not match'"
      ],
      "symbol": "AbstractVerbHandler._applyEnrollmentValidations",
      "type": "IllegalArgumentException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_verb_handler.dart#L432"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess"
      ],
      "guard": "!isAuthorized",
      "id": "AbstractUpdateVerbHandler.preProcess !isAuthorized throw",
      "kind": "throw",
      "messages": [
       "apkamUnauthorizedMsg(md.enrollmentId ?? 'primary', atKey)"
      ],
      "symbol": "AbstractUpdateVerbHandler.preProcess",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L95"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess"
      ],
      "guard": "reserved != null",
      "id": "AbstractUpdateVerbHandler.preProcess reserved != null throw",
      "kind": "throw",
      "messages": [
       "'Record in reserved namespace' ' ${sanitiseForLogging(reserved)} may not be updated'"
      ],
      "symbol": "AbstractUpdateVerbHandler.preProcess",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L103"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess"
      ],
      "guard": "isPerEnrollmentRecordForAnotherAtSign(atKey, atSign: atSign.toAtsign())",
      "id": "AbstractUpdateVerbHandler.preProcess isPerEnrollmentRecordForAnotherAtSign(atKey, atSign: atSign.toAtsign()) throw",
      "kind": "throw",
      "messages": [
       "'A per-enrollment record may not be for another atSign'"
      ],
      "symbol": "AbstractUpdateVerbHandler.preProcess",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L108"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess"
      ],
      "guard": "keyType case KeyType.privateKey || KeyType.cachedPublicKey || KeyType.cachedSharedKey || KeyType.localKey || KeyType.invalidKey",
      "id": "AbstractUpdateVerbHandler.preProcess keyType case KeyType.privateKey || KeyType.cachedPublicKey || KeyType.cachedSharedKey || KeyType.localKey || KeyType.invalidKey throw",
      "kind": "throw",
      "messages": [
       "'You may not update keys of type $keyType'"
      ],
      "symbol": "AbstractUpdateVerbHandler.preProcess",
      "type": "InvalidAtKeyException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L124"
     },
     {
      "branch": [
       "metadata != null",
       "ccd == null \u0026\u0026 ttrMillis != null"
      ],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "validateCacheMetadata",
       "validateTTR"
      ],
      "guard": "ttrMs \u003c= -2",
      "id": "validateTTR ttrMs \u003c= -2 throw #3",
      "kind": "throw",
      "messages": [
       "'Valid values for TTR are -1 and greater than or equal to 0'"
      ],
      "symbol": "validateTTR",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/utils/handler_util.dart#L19"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess"
      ],
      "guard": "updateParams.metadata!.ttr != null \u0026\u0026 updateParams.metadata!.ttr! \u003e 0 \u0026\u0026 sharedBy != null \u0026\u0026 sharedBy != atSign",
      "id": "AbstractUpdateVerbHandler.preProcess updateParams.metadata!.ttr != null \u0026\u0026 updateParams.metadata!.ttr! \u003e 0 \u0026\u0026 sharedBy != null \u0026\u0026 sharedBy != atSign throw",
      "kind": "throw",
      "messages": [
       "'update verb but sharedBy ($sharedBy) is not current atSign ($atSign)'"
      ],
      "symbol": "AbstractUpdateVerbHandler.preProcess",
      "type": "IllegalArgumentException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L145"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess",
       "AbstractUpdateVerbHandler._checkMaxLength"
      ],
      "guard": "key.length \u003e maxLength",
      "id": "AbstractUpdateVerbHandler._checkMaxLength key.length \u003e maxLength throw",
      "kind": "throw",
      "messages": [
       "'key length ${key.length} is greater than max allowed $maxLength chars'"
      ],
      "symbol": "AbstractUpdateVerbHandler._checkMaxLength",
      "type": "InvalidAtKeyException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L631"
     },
     {
      "branch": [],
      "chain": [
       "UpdateVerbHandler.processVerb",
       "AbstractUpdateVerbHandler.preProcess"
      ],
      "guard": "existingAtMetaData?.immutable == true",
      "id": "AbstractUpdateVerbHandler.preProcess existingAtMetaData?.immutable == true throw",
      "kind": "throw",
      "messages": [
       "'Immutable records may not be updated'"
      ],
      "symbol": "AbstractUpdateVerbHandler.preProcess",
      "type": "IllegalStateException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L155"
     },
     {
      "branch": [],
      "guard": "canonicalAtKey(updatePreProcessResult.atKey) == AtConstants.atPkamPublicKey",
      "id": "UpdateVerbHandler.processVerb canonicalAtKey(updatePreProcessResult.atKey) == AtConstants.atPkamPublicKey success",
      "kind": "success",
      "messages": [],
      "symbol": "UpdateVerbHandler.processVerb",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/update_verb_handler.dart#L69"
     }
    ]
   },
   "hash": "85f2b16946cd8860",
   "id": "alice-server-update",
   "intent": "Check the connection may write the key, store the record with its commit, then queue the auto-notification.",
   "lane": "alice.server",
   "links": [],
   "reached": {
    "from": "alice-server-batch",
    "kind": "wire",
    "nested": true,
    "replay": [
     {
      "commons": "at_commons 5.24.0 (at_server's lock)",
      "handler": "UpdateVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.update"
     },
     {
      "commons": "at_commons 5.25.0 (this checkout)",
      "handler": "UpdateVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.update"
     }
    ],
    "sample": "update:@bob:note.ns@alice bm90IGEgcmVhbCBjaXBoZXJ0ZXh0",
    "text": "wire update: (nested)",
    "verb": "update",
    "via": []
   },
   "reviewed": "85f2b16946cd8860",
   "skeleton": "updateParams = getUpdateParams\ndataStoreKey = getDataStoreKey, getDataStoreKey(updateParams).toLowerCase\nmutexRef = updateMutexes.putIfAbsent\ntry:\n  await mutexRef.mutex.acquire\n  updatePreProcessResult = await super.preProcess\n  if canonicalAtKey(updatePreProcessResult.atKey) == AtConstants.atPkamPublicKey:\n    await AtSecondaryServerImpl.getInstance, AtSecondaryServerImpl.getInst….installLegacyKeyIntoPrimary\n    response.data = '-1'\n    return\n  result = await markingKeyHolder\n  response.data = result.toString\n  await super.notifyAfterStore\nfinally:\n  mutexRef.mutex.release\n  if mutexRef.waiters == 0:\n    updateMutexes.remove\n",
   "snippet": {
    "cut": false,
    "startLine": 34,
    "text": "  Future\u003cvoid\u003e processVerb(\n      Response response,\n      HashMap\u003cString, String?\u003e verbParams,\n      InboundConnection atConnection) async {\n    UpdateParams updateParams = getUpdateParams(verbParams);\n\n    // NOTE lowercased, so two case-variants of one command contend for the\n    // same mutex.\n    String dataStoreKey = getDataStoreKey(updateParams).toLowerCase();\n\n    final mutexRef = updateMutexes.putIfAbsent(dataStoreKey, MutexRef.new);\n\n    try {\n      mutexRef.waiters++;\n      if (logger.isLoggable('finest')) {\n        logger.finest(\n            'Acquiring mutex for $dataStoreKey - ${mutexRef.waiters} waiting (including me)');\n      }\n      await mutexRef.mutex.acquire();\n\n      var updatePreProcessResult = await super.preProcess(\n        response,\n        verbParams,\n        updateParams,\n        atConnection,\n      );\n\n      // NOTE the flat legacy credential is never written; the value is\n      // redirected into the `primary` enrollment.\n      if (canonicalAtKey(updatePreProcessResult.atKey) ==\n          AtConstants.atPkamPublicKey) {\n        await AtSecondaryServerImpl.getInstance()\n            .enrollmentManager\n            .installLegacyKeyIntoPrimary(updatePreProcessResult.atData.data!);\n        response.data = '-1';\n        return;\n      }\n\n      var result = await markingKeyHolder(\n          updatePreProcessResult,\n          atConnection.metaData as InboundConnectionMetadata,\n          () =\u003e keepingApskLinks(\n              updatePreProcessResult,\n              () =\u003e keyStore.put(\n                    updatePreProcessResult.atKey,\n                    updatePreProcessResult.atData,\n                    skipCommit: verbParams[WireParams.noCommit] != null,\n                    assertedTimestamps:\n                        updatePreProcessResult.assertedTimestamps,\n                  )));\n      response.data = result?.toString();\n\n      await super.notifyAfterStore(verbParams, updateParams,\n          updatePreProcessResult);\n    } finally {\n      mutexRef.mutex.release();\n      mutexRef.waiters--;\n      if (mutexRef.waiters == 0) {\n        if (logger.isLoggable('finest')) {\n          logger.finest(\n              'Releasing mutex on $dataStoreKey : 0 now waiting for mutex on $dataStoreKey - removing mutex');\n        }\n        updateMutexes.remove(dataStoreKey);\n      } else {\n        if (logger.isLoggable('finest')) {\n          logger.finest(\n              'Releasing mutex on $dataStoreKey : ${mutexRef.waiters} still waiting for mutex on $dataStoreKey');\n        }\n      }\n    }\n  }"
   },
   "touches": [
    "keystore",
    "commit-log"
   ]
  },
  {
   "anchor": {
    "contains": "case NotificationType.sent:",
    "lines": [
     146,
     197
    ],
    "match": 155,
    "path": "packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart",
    "root": "server",
    "symbol": "NotificationManager.enqueue",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L146-L197"
   },
   "changed": false,
   "contracts": [],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "guard": "stored == null \u0026\u0026 !readBackFailed",
      "id": "AbstractUpdateVerbHandler.notifyAfterStore stored == null \u0026\u0026 !readBackFailed return",
      "kind": "return",
      "messages": [],
      "symbol": "AbstractUpdateVerbHandler.notifyAfterStore",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L254"
     },
     {
      "branch": [],
      "guard": "!_autoNotify",
      "id": "AbstractUpdateVerbHandler.notify !_autoNotify return",
      "kind": "return",
      "messages": [],
      "symbol": "AbstractUpdateVerbHandler.notify",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L524"
     },
     {
      "branch": [],
      "guard": "forAtSign == null || forAtSign.isEmpty",
      "id": "AbstractUpdateVerbHandler.notify forAtSign == null || forAtSign.isEmpty return",
      "kind": "return",
      "messages": [],
      "symbol": "AbstractUpdateVerbHandler.notify",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L527"
     },
     {
      "branch": [],
      "guard": "forAtSign.toAtsign() == atSign",
      "id": "AbstractUpdateVerbHandler.notify forAtSign.toAtsign() == atSign return",
      "kind": "return",
      "messages": [],
      "symbol": "AbstractUpdateVerbHandler.notify",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/abstract_update_verb_handler.dart#L530"
     },
     {
      "branch": [],
      "guard": "reserved != null",
      "id": "NotificationManager.notify reserved != null return",
      "kind": "return",
      "messages": [],
      "symbol": "NotificationManager.notify",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L214"
     }
    ]
   },
   "hash": "9fb5caac3bdeb250",
   "id": "alice-server-queue",
   "intent": "Build a notification for @bob from the stored record, persist it, and add it to the sender for @bob.",
   "lane": "alice.server",
   "links": [],
   "reached": {
    "from": "alice-server-update",
    "kind": "via",
    "text": "via AbstractUpdateVerbHandler.notifyAfterStore, AbstractUpdateVerbHandler.notify, NotificationManager.notify",
    "via": [
     "AbstractUpdateVerbHandler.notifyAfterStore",
     "AbstractUpdateVerbHandler.notify",
     "NotificationManager.notify"
    ]
   },
   "reviewed": "9fb5caac3bdeb250",
   "skeleton": "if closed:\n  throw StateError('Closed')\nswitch n.type:\n  case NotificationType.sent:\n    if n.toAtSign?.toAtsign() == atSign:\n      throw StateError(s)\n    if n.fromAtSign != atSign:\n      throw StateError(s)\n    reserved = _reservedNamespaceOfSent\n    if reserved != null:\n      s = sanitiseForLogging\n      throw StateError(s)\n    sent.add\n    n.toAtSign!.toAtsign, getPerAtSignNotifSender, getPerAtSignNotifSender(n.toA….add\n  case NotificationType.received:\n    _startReport, _pushToMonitors\n  case NotificationType.self:\n    if (n.toAtSign ?? atSign) != atSign:\n      throw StateError(s)\n    _pushToMonitors\n  case null:\n    throw InvalidSyntaxException('Notification ty…\n",
   "snippet": {
    "cut": false,
    "startLine": 146,
    "text": "  void enqueue(AtNotification n, {bool report = false}) {\n    if (closed) {\n      throw StateError('Closed');\n    }\n\n    if (logger.isLoggable('info')) {\n      logger.info('enqueue ${n.id} (${n.notification})');\n    }\n    switch (n.type) {\n      case NotificationType.sent:\n        if (n.toAtSign?.toAtsign() == atSign) {\n          String s = 'notificationType \"sent\" but toAtsign ${n.toAtSign}'\n              ' is the same as our atSign $atSign';\n          logger.severe(s);\n          throw StateError(s);\n        }\n        if (n.fromAtSign != atSign) {\n          String s = 'notificationType \"sent\" but fromAtsign ${n.fromAtSign}'\n              ' is not the same as our atSign $atSign';\n          logger.severe(s);\n          throw StateError(s);\n        }\n        final String? reserved = _reservedNamespaceOfSent(n);\n        if (reserved != null) {\n          String s = 'notificationType \"sent\" but notification ${n.id} uses'\n              ' reserved namespace ${sanitiseForLogging(reserved)}';\n          logger.severe(s);\n          throw StateError(s);\n        }\n        sent.add(n); // Useful for testing only\n        // We are sending this notification to another atSign\n        getPerAtSignNotifSender(n.toAtSign!.toAtsign()).notifs.add(n);\n        break;\n\n      case NotificationType.received:\n        // We have received from another atSign\n        _pushToMonitors(n, report: report ? _startReport(n) : null);\n        break;\n      case NotificationType.self:\n        if ((n.toAtSign ?? atSign) != atSign) {\n          String s = 'notificationType \"self\" but toAtsign ${n.toAtSign}'\n              ' is not our atSign $atSign';\n          logger.severe(s);\n          throw StateError(s);\n        }\n        // We are sending this notification to ourselves (other clients)\n        _pushToMonitors(n);\n        break;\n      case null:\n        throw InvalidSyntaxException('Notification type is required');\n    }\n  }"
   },
   "touches": [
    "notification-store"
   ]
  },
  {
   "anchor": {
    "contains": "await outBoundClient.notify(notifyCommandBody)",
    "lines": [
     629,
     741
    ],
    "match": 702,
    "path": "packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart",
    "root": "server",
    "symbol": "PerAtSignNotifSender.send",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L629-L741"
   },
   "changed": false,
   "contracts": [],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "guard": "n.toAtSign?.toAtsign() != atSign",
      "id": "PerAtSignNotifSender.send n.toAtSign?.toAtsign() != atSign return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L636"
     },
     {
      "branch": [],
      "guard": "n.notificationStatus != NotificationStatus.queued",
      "id": "PerAtSignNotifSender.send n.notificationStatus != NotificationStatus.queued return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L641"
     },
     {
      "branch": [],
      "guard": "keyLength \u003e maxNotificationKeyLength",
      "id": "PerAtSignNotifSender.send keyLength \u003e maxNotificationKeyLength return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L657"
     },
     {
      "branch": [],
      "guard": "notifMgr.closed",
      "id": "PerAtSignNotifSender.send notifMgr.closed return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L672"
     },
     {
      "branch": [],
      "guard": "n.isExpired()",
      "id": "PerAtSignNotifSender.send n.isExpired() return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L686"
     },
     {
      "branch": [],
      "guard": "notifyResponse == 'data:success'",
      "id": "PerAtSignNotifSender.send notifyResponse == 'data:success' return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L716"
     },
     {
      "branch": [
       "catch"
      ],
      "guard": "on SecondaryNotFoundException",
      "id": "PerAtSignNotifSender.send on SecondaryNotFoundException return",
      "kind": "return",
      "messages": [],
      "symbol": "PerAtSignNotifSender.send",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L729"
     }
    ]
   },
   "hash": "a593cc0ada4e95e7",
   "id": "alice-server-send",
   "intent": "Take notifications for @bob one at a time and send each over an outbound connection, retrying until it is delivered or expires.",
   "lane": "alice.server",
   "links": [],
   "reached": {
    "from": "alice-server-queue",
    "kind": "stream",
    "text": "stream hop through PerAtSignNotifSender.notifs, bound in PerAtSignNotifSender.new, via PerAtSignNotifSender.onNotif",
    "through": "PerAtSignNotifSender.notifs",
    "via": [
     "PerAtSignNotifSender.onNotif"
    ]
   },
   "reviewed": "a593cc0ada4e95e7",
   "skeleton": "if n.toAtSign?.toAtsign() != atSign:\n  return\nif n.notificationStatus != NotificationStatus.queued:\n  return\nkeyLength = notificationCachedByRecipient, notificationKeyLength\nif keyLength \u003e maxNotificationKeyLength:\n  n.notificationStatus = NotificationStatus.errored\n  notifMgr.telemetry.settled\n  try:\n    await notifMgr.put\n  on any:\n  return\nloop while true:\n  if notifMgr.closed:\n    return\n  try:\n    if n.isExpired():\n      n.notificationStatus = NotificationStatus.expired\n      notifMgr.telemetry.settled\n      try:\n        await notifMgr.put\n      on any:\n      return\n    outBoundClient = await notifMgr.notifyConnectionsPool.getOutboundClient\n    peerFeatures = notifMgr.isEphemeral, outBoundClient.usePeerFeature, notifMgr.hasExplicitExpiry, outBoundClient.usePeerFeature\n    notifyCommandBody = notifMgr.prepareNotifyCommandBody\n    notifyResponse = await outBoundClient.notify\n    if notifyResponse == 'data:success':\n      n.notificationStatus = NotificationStatus.delivered\n      notifMgr.telemetry.settled\n      try:\n        await notifMgr.put\n      on any:\n      return\n    else:\n      throw Exception('Unexpected response $notifyR…\n  on any:\n    try:\n      await notifMgr.notifyConnectionsPoo….findSecondary\n    on SecondaryNotFoundException:\n      n.notificationStatus = NotificationStatus.errored\n      notifMgr.telemetry.settled\n      await notifMgr.put\n      return\n    await Future.delayed\n    if delay \u003c maxDelay:\n      delay = (delay.inMilliseconds * phi).floor, min, Duration\n",
   "snippet": {
    "cut": false,
    "startLine": 629,
    "text": "  Future\u003cvoid\u003e send(AtNotification n) async {\n    if (logger.isLoggable('info')) {\n      logger.info('send: ${n.id} (${n.notification})');\n    }\n\n    if (n.toAtSign?.toAtsign() != atSign) {\n      logger.severe('toAtsign is ${n.toAtSign} but we are for $atSign');\n      return;\n    }\n\n    if (n.notificationStatus != NotificationStatus.queued) {\n      logger.severe('need status queued but got ${n.notificationStatus}');\n      return;\n    }\n\n    final int keyLength = notificationKeyLength(n.notification ?? '',\n        cached: notificationCachedByRecipient(n));\n    if (keyLength \u003e maxNotificationKeyLength) {\n      logger.severe('Not sending notification ${n.id}: its key would be'\n          ' $keyLength characters long where $atSign holds it, over the'\n          ' limit of $maxNotificationKeyLength');\n      n.notificationStatus = NotificationStatus.errored;\n      notifMgr.telemetry.settled(n);\n      try {\n        await notifMgr.put(n.id, n);\n      } catch (e) {\n        logger.warning('Exception $e while setting status errored on ${n.id}');\n      }\n      return;\n    }\n\n    // We keep trying until either\n    // (1) successful delivery, or\n    // (2) atSign no longer in directory\n    Duration delay = initialDelay;\n    while (true) {\n      // Delivery is retried until it succeeds or the atSign leaves the\n      // directory, so a closed manager must break the loop explicitly:\n      // otherwise every undelivered notification keeps retrying past\n      // server shutdown, against a keystore that `stop()` closes right\n      // after us.\n      if (notifMgr.closed) {\n        logger.info('NotificationManager is closed - abandoning ${n.id}');\n        return;\n      }\n      try {\n        // not much point in sending expired notifications, is there\n        if (n.isExpired()) {\n          logger.info('notification ${n.id} has expired - will not deliver');\n          n.notificationStatus = NotificationStatus.expired;\n          notifMgr.telemetry.settled(n);\n          try {\n            await notifMgr.put(n.id, n);\n          } catch (e) {\n            logger.warning(\n                'Exception $e while setting status expired on ${n.id}');\n          }\n          return;\n        }\n\n        //   get outbound client and send notify command\n        var outBoundClient =\n            await notifMgr.notifyConnectionsPool.getOutboundClient(atSign);\n        final peerFeatures = {\n          if (notifMgr.isEphemeral(n) \u0026\u0026\n              await outBoundClient.usePeerFeature(InfoFeature.notifyEph))\n            InfoFeature.notifyEph,\n          if (notifMgr.hasExplicitExpiry(n) \u0026\u0026\n              await outBoundClient.usePeerFeature(InfoFeature.notifyEAtn))\n            InfoFeature.notifyEAtn,\n        };\n        var notifyCommandBody =\n            notifMgr.prepareNotifyCommandBody(n, peerFeatures: peerFeatures);\n        var notifyResponse = await outBoundClient.notify(notifyCommandBody);\n        // if response was data:success - great, we're done!\n        if (notifyResponse == 'data:success') {\n          n.notificationStatus = NotificationStatus.delivered;\n          notifMgr.telemetry.settled(n);\n          if (logger.isLoggable('info')) {\n            logger.info('Delivered ${n.id} (${n.notification})');\n          }\n          try {\n            await notifMgr.put(n.id, n);\n          } catch (e) {\n            logger.warning(\n                'Exception $e while setting status delivered on ${n.id}');\n          }\n          return;\n        } else {\n          throw Exception('Unexpected response $notifyResponse');\n        }\n      } catch (e) {\n        try {\n          await notifMgr.notifyConnectionsPool.secondaryAddressFinder\n              .findSecondary(atSign);\n        } on SecondaryNotFoundException catch (_) {\n          logger.warning('no such atSign $atSign - giving up on ${n.id}');\n          n.notificationStatus = NotificationStatus.errored;\n          notifMgr.telemetry.settled(n);\n          await notifMgr.put(n.id, n);\n          return;\n        }\n        logger.info('Error while sending ${n.id}: ${e.runtimeType} : $e\\n');\n        logger.info('Will retry in $delay');\n        await Future.delayed(delay);\n        if (delay \u003c maxDelay) {\n          delay = Duration(\n              milliseconds: min((delay.inMilliseconds * phi).floor(),\n                  maxDelay.inMilliseconds));\n        }\n      }\n    }\n  }"
   },
   "touches": []
  },
  {
   "anchor": {
    "contains": "SecondaryUtil.buildBoundPolChallenge(currentAtSign)",
    "lines": [
     121,
     200
    ],
    "match": 180,
    "path": "packages/at_secondary_server/lib/src/verb/handler/from_verb_handler.dart",
    "root": "server",
    "symbol": "FromVerbHandler.processVerb",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/from_verb_handler.dart#L121-L200"
   },
   "changed": false,
   "contracts": [
    {
     "backing": {
      "exit": {
       "guard": "inBlockList",
       "kind": "throw",
       "symbol": "FromVerbHandler.processVerb",
       "type": "BlockedConnectionException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/from_verb_handler.dart#L159"
      }
     },
     "kind": "refuses",
     "label": "enforced by bob.server",
     "text": "a from: naming an atSign on this atSign's blocklist"
    }
   ],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "guard": "_namesAnotherAtSign(atConnection, fromAtSign)",
      "id": "FromVerbHandler.processVerb _namesAnotherAtSign(atConnection, fromAtSign) throw",
      "kind": "throw",
      "messages": [
       "anotherAtSignRefusal"
      ],
      "symbol": "FromVerbHandler.processVerb",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/from_verb_handler.dart#L129"
     },
     {
      "branch": [],
      "guard": "inBlockList",
      "id": "FromVerbHandler.processVerb inBlockList throw",
      "kind": "throw",
      "messages": [
       "'Unable to connect'"
      ],
      "symbol": "FromVerbHandler.processVerb",
      "type": "BlockedConnectionException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/from_verb_handler.dart#L159"
     },
     {
      "branch": [
       "fromAtSign != AtSecondaryServerImpl.getInstance().currentAtSign \u0026\u0026 AtSecondaryConfig.clientCertificateRequired"
      ],
      "guard": "!result",
      "id": "FromVerbHandler.processVerb !result throw",
      "kind": "throw",
      "messages": [
       "'Certificate Verification Failed'"
      ],
      "symbol": "FromVerbHandler.processVerb",
      "type": "UnAuthenticatedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/from_verb_handler.dart#L167"
     }
    ]
   },
   "hash": "84d7c4500f1ab546",
   "id": "bob-server-from",
   "intent": "Answer from:@alice with a challenge bound to @bob's atServer, stored for one minute, unless @alice is on @bob's blocklist.",
   "lane": "bob.server",
   "links": [],
   "reached": {
    "from": "alice-server-send",
    "kind": "wire",
    "replay": [
     {
      "commons": "at_commons 5.24.0 (at_server's lock)",
      "handler": "FromVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.from"
     },
     {
      "commons": "at_commons 5.25.0 (this checkout)",
      "handler": "FromVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.from"
     }
    ],
    "sample": "from:@alice",
    "text": "wire from:",
    "verb": "from",
    "via": []
   },
   "reviewed": "84d7c4500f1ab546",
   "skeleton": "fromAtSign = verbParams[AtConstants.atSign….toAtsign\nif _namesAnotherAtSign(atConnection, fromAtSign):\n  throw UnAuthorizedException(anotherAtSignRefu…\ncurrentAtSign = AtSecondaryServerImpl.getInstance\natConfigInstance = AtConfig\natConnection.initiatedBy = currentAtSign\nif verbParams[AtConstants.clientConfig] != null \u0026\u0026 verbParams[AtConstants.clientConfig]!.isN…:\n  decodedClientConfig = jsonDecode\n  if clientVersion is String \u0026\u0026 _isVersion(clientVersion):\n    atConnectionMetadata.clientVersion = clientVersion\n  _loggable, _loggable, _loggable, _loggable\ninBlockList = await atConfigInstance.checkInBlockList\nif inBlockList:\n  throw BlockedConnectionException('Unable to c…\nif fromAtSign != AtSecondaryServerImpl.getInstance().currentAtSign \u0026\u0026 AtSecondaryConfig.clie…:\n  result = await _verifyFromAtSign\n  if !result:\n    throw UnAuthenticatedException('Certificate V…\natData = AtData\nproof = Uuid, Uuid().v4, SecondaryUtil.buildBoundPolChallenge\natData.data = proof\natData.metaData = AtMetaData\nawait keyStore.put\nresponse.data = '$responsePrefix${atConnectionMetadata.sessionID}…\nif fromAtSign == currentAtSign:\n  atConnectionMetadata.self = true\nelse:\n  atConnectionMetadata.from = true\n  atConnectionMetadata.fromAtSign = fromAtSign\ntry:\n  await from.name, accessLog.insert\non DataStoreException:\n",
   "snippet": {
    "cut": false,
    "startLine": 121,
    "text": "  Future\u003cvoid\u003e processVerb(\n      Response response,\n      HashMap\u003cString, String?\u003e verbParams,\n      InboundConnection atConnection) async {\n    Atsign fromAtSign = verbParams[AtConstants.atSign]!.toAtsign();\n    // NOTE a connection stays bound to the atSign it authenticated as, so this\n    // refusal comes before anything is written to the connection.\n    if (_namesAnotherAtSign(atConnection, fromAtSign)) {\n      throw UnAuthorizedException(anotherAtSignRefusal);\n    }\n    var currentAtSign = AtSecondaryServerImpl.getInstance().currentAtSign;\n    atConfigInstance = AtConfig(keyStore, currentAtSign);\n    atConnection.initiatedBy = currentAtSign;\n    var atConnectionMetadata =\n        atConnection.metaData as InboundConnectionMetadata;\n\n    if (verbParams[AtConstants.clientConfig] != null \u0026\u0026\n        verbParams[AtConstants.clientConfig]!.isNotEmpty) {\n      var decodedClientConfig =\n          jsonDecode(verbParams[AtConstants.clientConfig]!);\n      final clientVersion = decodedClientConfig[AtConstants.version];\n      if (clientVersion is String \u0026\u0026 _isVersion(clientVersion)) {\n        atConnectionMetadata.clientVersion = clientVersion;\n      }\n      atConnectionMetadata\n        ..clientId = _loggable(decodedClientConfig[AtConstants.clientId])\n        ..appName = _loggable(decodedClientConfig[AtConstants.appName])\n        ..appVersion = _loggable(decodedClientConfig[AtConstants.appVersion])\n        ..platform = _loggable(decodedClientConfig[AtConstants.platform]);\n    }\n\n    var keyPrefix = (fromAtSign == currentAtSign) ? 'private:' : 'public:';\n    var responsePrefix = (fromAtSign == currentAtSign) ? 'data:' : 'proof:';\n\n    var inBlockList = await atConfigInstance.checkInBlockList(fromAtSign);\n\n    if (inBlockList) {\n      logger.severe('$fromAtSign is in blocklist of $currentAtSign');\n      throw BlockedConnectionException('Unable to connect');\n    }\n\n    if (fromAtSign != AtSecondaryServerImpl.getInstance().currentAtSign \u0026\u0026\n        AtSecondaryConfig.clientCertificateRequired) {\n      var result = await _verifyFromAtSign(fromAtSign, atConnection);\n      logger.finer('_verifyFromAtSign result : $result');\n      if (!result) {\n        throw UnAuthenticatedException('Certificate Verification Failed');\n      }\n    }\n\n    //store key with private/public prefix, sessionId and fromAtSign\n    String storedSecretId =\n        '$keyPrefix${atConnectionMetadata.sessionID}$fromAtSign';\n    final AtData atData = AtData();\n    // The challenge the peer/client signs. Peer pol auth (fromAtSign !=\n    // currentAtSign) gets a verifier-bound challenge naming this server;\n    // the self path (client PKAM/CRAM) keeps the bare UUID.\n    final String proof = (fromAtSign == currentAtSign)\n        ? Uuid().v4()\n        : SecondaryUtil.buildBoundPolChallenge(currentAtSign);\n    atData.data = proof;\n    atData.metaData = AtMetaData()..ttl = 60 * 1000; //expire in 1 min\n    logger.finer('Storing secret to $storedSecretId');\n    await keyStore.put(storedSecretId, atData);\n    response.data =\n        '$responsePrefix${atConnectionMetadata.sessionID}$fromAtSign:$proof';\n\n    logger.finer('fromAtSign : $fromAtSign currentAtSign : $currentAtSign');\n    if (fromAtSign == currentAtSign) {\n      atConnectionMetadata.self = true;\n    } else {\n      atConnectionMetadata.from = true;\n      atConnectionMetadata.fromAtSign = fromAtSign;\n    }\n    try {\n      await accessLog.insert(fromAtSign, from.name());\n    } on DataStoreException catch (e) {\n      logger.severe('Hive error adding to access log:${e.toString()}');\n    }\n  }"
   },
   "touches": []
  },
  {
   "anchor": {
    "contains": "message = await consumeChallenge(storedSecretId);",
    "lines": [
     46,
     120
    ],
    "match": 93,
    "path": "packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart",
    "root": "server",
    "symbol": "PolVerbHandler.processVerb",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L46-L120"
   },
   "changed": false,
   "contracts": [
    {
     "backing": {
      "exit": {
       "guard": "atConnectionMetadata.from != true",
       "kind": "throw",
       "symbol": "PolVerbHandler.processVerb",
       "type": "InvalidRequestException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L56"
      }
     },
     "kind": "refuses",
     "label": "enforced by bob.server",
     "text": "pol on a connection with no earlier from:"
    },
    {
     "backing": {
      "exit": {
       "guard": "!isValidChallenge",
       "kind": "throw",
       "symbol": "PolVerbHandler.processVerb",
       "type": "UnAuthenticatedException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L111"
      }
     },
     "kind": "refuses",
     "label": "enforced by bob.server",
     "text": "a signature over the challenge that does not verify against signing_publickey@alice"
    }
   ],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "guard": "atConnectionMetadata.from != true",
      "id": "PolVerbHandler.processVerb atConnectionMetadata.from != true throw",
      "kind": "throw",
      "messages": [
       "'You must execute a ' '\\'from:\\' command before you may run the pol command'"
      ],
      "symbol": "PolVerbHandler.processVerb",
      "type": "InvalidRequestException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L56"
     },
     {
      "branch": [
       "!oc.isConnectionCreated"
      ],
      "guard": "on Exception",
      "id": "PolVerbHandler.processVerb on Exception rethrow",
      "kind": "rethrow",
      "messages": [],
      "symbol": "PolVerbHandler.processVerb",
      "type": "Exception",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L70"
     },
     {
      "branch": [],
      "guard": "on Exception",
      "id": "PolVerbHandler.processVerb on Exception rethrow #2",
      "kind": "rethrow",
      "messages": [],
      "symbol": "PolVerbHandler.processVerb",
      "type": "Exception",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L96"
     },
     {
      "branch": [],
      "guard": "fromPublicKey == null || signedChallenge == null || message == null",
      "id": "PolVerbHandler.processVerb fromPublicKey == null || signedChallenge == null || message == null throw",
      "kind": "throw",
      "messages": [
       "'Unable to verify signature'"
      ],
      "symbol": "PolVerbHandler.processVerb",
      "type": "AtException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L104"
     },
     {
      "branch": [],
      "guard": "!isValidChallenge",
      "id": "PolVerbHandler.processVerb !isValidChallenge throw",
      "kind": "throw",
      "messages": [
       "'Pol Authentication Failed'"
      ],
      "symbol": "PolVerbHandler.processVerb",
      "type": "UnAuthenticatedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/pol_verb_handler.dart#L111"
     }
    ]
   },
   "hash": "13bd576ff341e88f",
   "id": "bob-server-pol",
   "intent": "Fetch @alice's signed challenge and signing_publickey@alice, spend the stored challenge, and mark the connection pol-authenticated only if the signature verifies.",
   "lane": "bob.server",
   "links": [],
   "reached": {
    "from": "bob-server-from",
    "kind": "wire",
    "replay": [
     {
      "commons": "at_commons 5.24.0 (at_server's lock)",
      "handler": "PolVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.pol"
     },
     {
      "commons": "at_commons 5.25.0 (this checkout)",
      "handler": "PolVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.pol"
     }
    ],
    "sample": "pol",
    "text": "wire pol",
    "verb": "pol",
    "via": []
   },
   "reviewed": "13bd576ff341e88f",
   "skeleton": "if atConnectionMetadata.from != true:\n  throw InvalidRequestException('You must execu…\noc = await outboundClientManager.getClient\nif !oc.isConnectionCreated:\n  try:\n    await oc.connect\n  on Exception:\n    rethrow\ntry:\n  doing = 'fetching signed challenge from $fromAtSign'\n  signedChallenge = oc.lookUp, (await (oc.lookUp('$sessionID….replaceFirst\n  doing = 'fetching signing_publickey$fromAtSign'\n  fromPublicKey = oc.plookUp, (await (oc.plookUp('signing_p….replaceFirst\n  doing = 'fetching stored secret $storedSecretId'\n  message = await consumeChallenge\non Exception:\n  rethrow\nif fromPublicKey == null || signedChallenge == null || message == null:\n  throw AtException('Unable to verify signature…\nisValidChallenge = RSAPublicKey.fromString, utf8.encode, base64Decode, RSAPublicKey.fromString(fromP….verifySHA256Signature\nif !isValidChallenge:\n  throw UnAuthenticatedException('Pol Authentic…\natConnectionMetadata.isPolAuthenticated = true\nresponse.data = 'pol:$fromAtSign@'\nawait pol.name, _insertIntoAccessLog\nreturn\n",
   "snippet": {
    "cut": false,
    "startLine": 46,
    "text": "  Future\u003cvoid\u003e processVerb(\n      Response response,\n      HashMap\u003cString, String?\u003e verbParams,\n      InboundConnection atConnection) async {\n    InboundConnectionMetadata atConnectionMetadata =\n        atConnection.metaData as InboundConnectionMetadata;\n    var fromAtSign = atConnectionMetadata.fromAtSign;\n    var sessionID = atConnectionMetadata.sessionID;\n\n    if (atConnectionMetadata.from != true) {\n      throw InvalidRequestException('You must execute a '\n          '\\'from:\\' command before you may run the pol command');\n    }\n    logger.info('pol from $fromAtSign');\n\n    final OutboundClient oc = await outboundClientManager.getClient(\n        fromAtSign!, _dummyInboundConnection,\n        handshakeRequired: false);\n    if (!oc.isConnectionCreated) {\n      try {\n        await oc.connect();\n      } on Exception catch (e) {\n        logger.severe(\n            'Exception connecting to $fromAtSign\\'s outbound client | $e');\n        rethrow;\n      }\n    }\n\n    final String storedSecretId = 'public:$sessionID$fromAtSign';\n\n    String? signedChallenge, fromPublicKey, message;\n\n    String doing = '';\n    try {\n      doing = 'fetching signed challenge from $fromAtSign';\n      signedChallenge = (await (oc.lookUp(\n        '$sessionID$fromAtSign',\n        handshake: false,\n      )))\n          ?.replaceFirst(_dataPrefix, '');\n\n      doing = 'fetching signing_publickey$fromAtSign';\n      fromPublicKey = (await (oc.plookUp('signing_publickey$fromAtSign')))\n          ?.replaceFirst(_dataPrefix, '');\n\n      // NOTE spent on read, whatever the verification below decides.\n      doing = 'fetching stored secret $storedSecretId';\n      message = await consumeChallenge(storedSecretId);\n    } on Exception catch (e) {\n      logger.severe('Exception while $doing : $e');\n      rethrow;\n    }\n\n    if (fromPublicKey == null || signedChallenge == null || message == null) {\n      logger.severe('Unable to verify signature.'\n          ' fromPublicKey is $fromPublicKey'\n          ' | signedChallenge is $signedChallenge'\n          ' | message is $message');\n      throw AtException('Unable to verify signature');\n    }\n\n    bool isValidChallenge = RSAPublicKey.fromString(fromPublicKey)\n        .verifySHA256Signature(\n            utf8.encode(message), base64Decode(signedChallenge));\n    if (!isValidChallenge) {\n      throw UnAuthenticatedException('Pol Authentication Failed');\n    }\n\n    atConnectionMetadata.isPolAuthenticated = true;\n    response.data = 'pol:$fromAtSign@';\n    await _insertIntoAccessLog(fromAtSign, pol.name());\n    logger.info('response : $fromAtSign@');\n\n    return;\n  }"
   },
   "touches": []
  },
  {
   "anchor": {
    "contains": "_refuseForeignAtSigns(verbParams,",
    "lines": [
     109,
     244
    ],
    "match": 124,
    "path": "packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart",
    "root": "server",
    "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L109-L244"
   },
   "changed": false,
   "contracts": [
    {
     "backing": {
      "exit": {
       "guard": "sharedBy != fromAtSign",
       "kind": "throw",
       "symbol": "NotifyVerbHandler._refuseForeignAtSigns",
       "type": "UnAuthorizedException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L259"
      }
     },
     "kind": "refuses",
     "label": "enforced by bob.server",
     "text": "a notification whose sharedBy is not the atSign pol proved"
    },
    {
     "backing": {
      "exit": {
       "guard": "sharedWith != currentAtSign",
       "kind": "throw",
       "symbol": "NotifyVerbHandler._refuseForeignAtSigns",
       "type": "UnAuthorizedException",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L253"
      }
     },
     "kind": "refuses",
     "label": "enforced by bob.server",
     "text": "a notification for an atSign other than @bob"
    },
    {
     "backing": {
      "gherkin": {
       "clause": "Then it gets data:success",
       "feature": "features/notify/peer_reserved_namespace.feature",
       "root": "server",
       "scenario": "Another atServer's notification into a reserved namespace is dropped",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/features/notify/peer_reserved_namespace.feature#L36"
      }
     },
     "kind": "post",
     "label": "backed",
     "text": "a notification into a reserved namespace is dropped and answered data:success"
    },
    {
     "backing": {
      "exit": {
       "guard": "await notifMgr.isKeyExists(n.id!)",
       "kind": "success",
       "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
       "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L164"
      }
     },
     "kind": "post",
     "label": "backed",
     "text": "a notification whose id this atServer already holds is not stored again, and is answered data:success"
    }
   ],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "chain": [
       "NotifyVerbHandler.processVerb",
       "NotifyVerbHandler._validateNotifyVerbParams"
      ],
      "guard": "verbParams[AtConstants.strategy] == 'latest' \u0026\u0026 verbParams[AtConstants.notifier] == null",
      "id": "NotifyVerbHandler._validateNotifyVerbParams verbParams[AtConstants.strategy] == 'latest' \u0026\u0026 verbParams[AtConstants.notifier] == null throw",
      "kind": "throw",
      "messages": [
       "'For Strategy latest, notifier cannot be null'"
      ],
      "symbol": "NotifyVerbHandler._validateNotifyVerbParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L433"
     },
     {
      "branch": [],
      "chain": [
       "NotifyVerbHandler.processVerb",
       "NotifyVerbHandler.refuseConflictingLifetime"
      ],
      "guard": "verbParams[AtConstants.notificationExpiresAt] != null \u0026\u0026 verbParams[AtConstants.ttlNotification] != null",
      "id": "NotifyVerbHandler.refuseConflictingLifetime verbParams[AtConstants.notificationExpiresAt] != null \u0026\u0026 verbParams[AtConstants.ttlNotification] != null throw",
      "kind": "throw",
      "messages": [
       "'eAtn and ttln cannot both be given'"
      ],
      "symbol": "NotifyVerbHandler.refuseConflictingLifetime",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L633"
     },
     {
      "branch": [
       "isEphemeral(verbParams)"
      ],
      "chain": [
       "NotifyVerbHandler.processVerb",
       "NotifyVerbHandler.refuseConflictingLifetime"
      ],
      "guard": "SecondaryUtil.getOperationType(verbParams[AtConstants.operation]) == OperationType.delete",
      "id": "NotifyVerbHandler.refuseConflictingLifetime SecondaryUtil.getOperationType(verbParams[AtConstants.operation]) == OperationType.delete throw",
      "kind": "throw",
      "messages": [
       "'eph does not take delete'"
      ],
      "symbol": "NotifyVerbHandler.refuseConflictingLifetime",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L638"
     },
     {
      "branch": [
       "isEphemeral(verbParams)",
       "each field in [AtConstants.ttr, AtConstants.ccd]"
      ],
      "chain": [
       "NotifyVerbHandler.processVerb",
       "NotifyVerbHandler.refuseConflictingLifetime"
      ],
      "guard": "verbParams[field] != null",
      "id": "NotifyVerbHandler.refuseConflictingLifetime verbParams[field] != null throw",
      "kind": "throw",
      "messages": [
       "'eph does not take $field'"
      ],
      "symbol": "NotifyVerbHandler.refuseConflictingLifetime",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L642"
     },
     {
      "branch": [],
      "guard": "!atConnectionMetadata.isAuthenticated \u0026\u0026 !atConnectionMetadata.isPolAuthenticated",
      "id": "NotifyVerbHandler.processVerb !atConnectionMetadata.isAuthenticated \u0026\u0026 !atConnectionMetadata.isPolAuthenticated throw",
      "kind": "throw",
      "messages": [
       "'Notify command cannot be executed without authentication'"
      ],
      "symbol": "NotifyVerbHandler.processVerb",
      "type": "UnAuthenticatedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L86"
     },
     {
      "branch": [],
      "chain": [
       "NotifyVerbHandler.processVerb",
       "NotifyVerbHandler._refuseOverlongId"
      ],
      "guard": "(verbParams[AtConstants.id]?.length ?? 0) \u003e maxIdLength",
      "id": "NotifyVerbHandler._refuseOverlongId (verbParams[AtConstants.id]?.length ?? 0) \u003e maxIdLength throw",
      "kind": "throw",
      "messages": [
       "idTooLong"
      ],
      "symbol": "NotifyVerbHandler._refuseOverlongId",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L421"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "_isText(verbParams)",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection _isText(verbParams) success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L122"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "chain": [
       "NotifyVerbHandler._handlePolAuthenticatedConnection",
       "NotifyVerbHandler._refuseForeignAtSigns"
      ],
      "guard": "sharedWith != currentAtSign",
      "id": "NotifyVerbHandler._refuseForeignAtSigns sharedWith != currentAtSign throw",
      "kind": "throw",
      "messages": [
       "'Notification from $fromAtSign is for ${sharedWith ?? 'no atSign'},' ' not $currentAtSign'"
      ],
      "symbol": "NotifyVerbHandler._refuseForeignAtSigns",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L253"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "chain": [
       "NotifyVerbHandler._handlePolAuthenticatedConnection",
       "NotifyVerbHandler._refuseForeignAtSigns"
      ],
      "guard": "sharedBy != fromAtSign",
      "id": "NotifyVerbHandler._refuseForeignAtSigns sharedBy != fromAtSign throw",
      "kind": "throw",
      "messages": [
       "'Notification from $fromAtSign is of a key with no sharedBy'",
       "'$sharedBy is not authorized to send notification as $fromAtSign'"
      ],
      "symbol": "NotifyVerbHandler._refuseForeignAtSigns",
      "type": "UnAuthorizedException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L259"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "!isWellFormedAtKey(atKey)",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection !isWellFormedAtKey(atKey) success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L133"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "reserved != null",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection reserved != null success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L142"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "chain": [
       "NotifyVerbHandler._handlePolAuthenticatedConnection",
       "NotifyVerbHandler._populateNotificationBuilder",
       "NotifyVerbHandler._metadataFromParams"
      ],
      "guard": "on FormatException",
      "id": "NotifyVerbHandler._metadataFromParams on FormatException throw",
      "kind": "throw",
      "messages": [
       "'invalid ${AtConstants.appMetadata}: ${e.message}'"
      ],
      "symbol": "NotifyVerbHandler._metadataFromParams",
      "type": "InvalidSyntaxException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L561"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "n.isExpired()",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection n.isExpired() success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L156"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "await notifMgr.isKeyExists(n.id!)",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection await notifMgr.isKeyExists(n.id!) success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L164"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated",
       "caches"
      ],
      "chain": [
       "NotifyVerbHandler._handlePolAuthenticatedConnection",
       "refuseOverlongNotificationKey"
      ],
      "guard": "length \u003e maxNotificationKeyLength",
      "id": "refuseOverlongNotificationKey length \u003e maxNotificationKeyLength throw",
      "kind": "throw",
      "messages": [
       "'notification key length $length is greater' ' than $maxNotificationKeyLength chars'"
      ],
      "symbol": "refuseOverlongNotificationKey",
      "type": "InvalidAtKeyException",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_key_length.dart#L28"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "!caches",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection !caches success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L188"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "operationType == OperationType.delete",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection operationType == OperationType.delete success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L206"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated"
      ],
      "guard": "atNotificationBuilder.atValue != null",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection atNotificationBuilder.atValue != null success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L228"
     },
     {
      "branch": [
       "!atConnectionMetadata.isAuthenticated",
       "!(atNotificationBuilder.atValue != null)"
      ],
      "guard": "isKeyPresent",
      "id": "NotifyVerbHandler._handlePolAuthenticatedConnection isKeyPresent success",
      "kind": "success",
      "messages": [],
      "symbol": "NotifyVerbHandler._handlePolAuthenticatedConnection",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/verb/handler/notify_verb_handler.dart#L240"
     }
    ]
   },
   "hash": "4c59ba21162ee7be",
   "id": "bob-server-accept",
   "intent": "Accept @alice's notification only if it is for @bob and its sharedBy is the atSign pol proved.",
   "lane": "bob.server",
   "links": [],
   "reached": {
    "from": "bob-server-pol",
    "kind": "wire",
    "replay": [
     {
      "commons": "at_commons 5.24.0 (at_server's lock)",
      "handler": "NotifyVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.notify"
     },
     {
      "commons": "at_commons 5.25.0 (this checkout)",
      "handler": "NotifyVerbHandler",
      "parses": true,
      "syntax": "VerbSyntax.notify"
     }
    ],
    "sample": "notify:id:0a1b2c3d-1111-2222-3333-444455556666:update:messageType:key:@bob:note.ns@alice:bm90IGEgcmVhbCBjaXBoZXJ0ZXh0",
    "text": "wire notify:, via NotifyVerbHandler.processVerb",
    "verb": "notify",
    "via": [
     "NotifyVerbHandler.processVerb"
    ]
   },
   "reviewed": "4c59ba21162ee7be",
   "skeleton": "if _isText(verbParams):\n  response.data = 'data:success'\n  return\n_refuseForeignAtSigns\nif !isWellFormedAtKey(atKey):\n  response.data = 'data:success'\n  return\nreserved = reservedNamespaceOf\nif reserved != null:\n  response.data = 'data:success'\n  return\natNotificationBuilder = polConnectionMetadata.fromAtS….toAtsign, _populateNotificationBuilder\nn = atNotificationBuilder.build\nif n.isExpired():\n  response.data = 'data:success'\n  return\nif await notifMgr.isKeyExists(n.id!):\n  response.data = 'data:success'\n  return\noperationType = getOperationType\ncaches = _cachedByRecipient\nif caches:\n  refuseOverlongNotificationKey\nawait isEphemeral, notifMgr.notify\nif !caches:\n  response.data = 'data:success'\n  return\nasserted = _assertedTimestampsFromParams\nif operationType == OperationType.delete:\n  cachedKeyCommitId = await _removeCachedKey\n  _writeStats\n  response.data = 'data:success'\n  return\nisKeyPresent = await keyStore.exists\nif atNotificationBuilder.atValue != null:\n  if isKeyPresent:\n    atMetadata = await keyStore.getMeta\n  metadata = AtMetadataBuilder, AtMetadataBuilder(atSign: pol….build\n  cachedKeyCommitId = await _storeCachedKey\n  _writeStats\n  response.data = 'data:success'\n  return\nelse:\n  if isKeyPresent:\n    cachedKeyCommitId = await _updateMetadata\n    _writeStats\n    response.data = 'data:success'\n    return\nresponse.data = 'data:success'\nreturn\n",
   "snippet": {
    "cut": false,
    "startLine": 109,
    "text": "  Future\u003cvoid\u003e _handlePolAuthenticatedConnection(\n      Atsign currentAtSign,\n      HashMap\u003cString, String?\u003e verbParams,\n      InboundConnectionMetadata polConnectionMetadata,\n      Response response) async {\n    if (logger.isLoggable('info')) {\n      logger.info('Processing notification id ${verbParams[AtConstants.id]}');\n    }\n    if (_isText(verbParams)) {\n      logger.warning('Dropped text notification ${verbParams[AtConstants.id]}'\n          ' from ${polConnectionMetadata.fromAtSign}'\n          ' for ${verbParams[AtConstants.forAtSign]}: $textNotSupported');\n      response.data = 'data:success';\n      return;\n    }\n    _refuseForeignAtSigns(verbParams,\n        currentAtSign: currentAtSign,\n        fromAtSign: polConnectionMetadata.fromAtSign!);\n    final String atKey = verbParams[AtConstants.atKey]!;\n    if (!isWellFormedAtKey(atKey)) {\n      logger.warning('Dropping notification ${verbParams[AtConstants.id]}'\n          ' from ${polConnectionMetadata.fromAtSign!.toAtsign()}: its key is'\n          ' not a well-formed atKey');\n      response.data = 'data:success';\n      return;\n    }\n    // NOTE another atSign's notification never lands in a reserved namespace.\n    final String? reserved = reservedNamespaceOf(atKey);\n    if (reserved != null) {\n      logger.warning('Dropping notification ${verbParams[AtConstants.id]}'\n          ' from ${polConnectionMetadata.fromAtSign!.toAtsign()}: it uses'\n          ' reserved namespace ${sanitiseForLogging(reserved)}');\n      response.data = 'data:success';\n      return;\n    }\n\n    var atNotificationBuilder = _populateNotificationBuilder(verbParams,\n        fromAtSign: polConnectionMetadata.fromAtSign!.toAtsign());\n\n    AtNotification n = atNotificationBuilder.build();\n\n    // If the the notification has expired, do not store it\n    // Instead, log a warning, but return data:success as it is not\n    // definitely an error condition\n    if (n.isExpired()) {\n      logger.warning('Notification ${n.id} from ${n.fromAtSign} has expired');\n      response.data = 'data:success';\n      return;\n    }\n\n    // If we already have a notification with this ID, do not store it\n    // Instead, log a warning, but return data:success for idempotency reasons\n    if (await notifMgr.isKeyExists(n.id!)) {\n      logger.warning('We have already received notification ${n.id}');\n      response.data = 'data:success';\n      return;\n    }\n\n    // When Operation is update, cache key only when TTR is set.\n    // Also, If operation is delete removed the cached key - irrespective of TTR value.\n    final OperationType operationType =\n        getOperationType(verbParams[AtConstants.operation]);\n    final bool caches = _cachedByRecipient(verbParams);\n    final String cachedNotificationKey =\n        '${AtConstants.cached}:${atNotificationBuilder.notification}';\n    // NOTE checked before the notification is stored, so one whose key\n    // cannot be cached is refused with nothing stored or pushed.\n    if (caches) {\n      refuseOverlongNotificationKey(atNotificationBuilder.notification!,\n          cached: true);\n    }\n\n    // Store and send the notification\n    await notifMgr.notify(n,\n        ephemeral: isEphemeral(verbParams), reportReceived: true);\n\n    // Everything after here is to do with auto-caching based on notifications\n    if (!caches) {\n      response.data = 'data:success';\n      return;\n    }\n    // Sender-asserted timestamps travel to the keystore explicitly, so the\n    // cached key is stored with the origin's values. Passed on EVERY write\n    // that transmits them — a refresh of an existing cached key included —\n    // because direct keystore writes have no retain-merge to carry a\n    // previously-asserted expiry forward.\n    final asserted = _assertedTimestampsFromParams(verbParams);\n\n    // If operationType is delete, remove the cached key only\n    // when cascade delete is set to true\n    int? cachedKeyCommitId;\n    if (operationType == OperationType.delete) {\n      cachedKeyCommitId = await _removeCachedKey(cachedNotificationKey,\n          deletedAt: atNotificationBuilder.atMetaData?.updatedAt);\n      //write the latest commit id to the StatsNotificationService\n      _writeStats(cachedKeyCommitId, operationType.name);\n      response.data = 'data:success';\n      return;\n    }\n\n    var isKeyPresent = await keyStore.exists(cachedNotificationKey);\n    AtMetaData? atMetadata;\n    // If atValue is not null, store a cached key\n    if (atNotificationBuilder.atValue != null) {\n      // If the cached key is already present, get the existing metadata\n      // and update the new metadata.\n      if (isKeyPresent) {\n        atMetadata = await keyStore.getMeta(cachedNotificationKey);\n      }\n      var metadata = AtMetadataBuilder(\n              atSign: polConnectionMetadata.fromAtSign!,\n              newAtMetaData: atNotificationBuilder.atMetaData!,\n              existingMetaData: atMetadata)\n          .build();\n      cachedKeyCommitId = await _storeCachedKey(cachedNotificationKey, metadata,\n          atValue: atNotificationBuilder.atValue, assertedTimestamps: asserted);\n      //write the latest commit id to the StatsNotificationService\n      _writeStats(cachedKeyCommitId, operationType.name);\n      response.data = 'data:success';\n      return;\n    }\n    // The updateMetadata gets invoked via the update_meta verb to update the\n    // cached key metadata.\n    else if (isKeyPresent) {\n      var atMetaData = atNotificationBuilder.atMetaData;\n      cachedKeyCommitId = await _updateMetadata(\n          cachedNotificationKey, atMetaData,\n          assertedTimestamps: asserted);\n      //write the latest commit id to the StatsNotificationService\n      _writeStats(cachedKeyCommitId, operationType.name);\n      response.data = 'data:success';\n      return;\n    }\n    response.data = 'data:success';\n    return;\n  }"
   },
   "touches": []
  },
  {
   "anchor": {
    "contains": "sink.push(n, report: report);",
    "lines": [
     236,
     255
    ],
    "match": 240,
    "path": "packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart",
    "root": "server",
    "symbol": "NotificationManager._pushToMonitors",
    "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L236-L255"
   },
   "changed": false,
   "contracts": [],
   "exits": {
    "complete": true,
    "incomplete": [],
    "list": [
     {
      "branch": [],
      "guard": "closed",
      "id": "NotificationManager.notify closed throw",
      "kind": "throw",
      "messages": [
       "'Closed'"
      ],
      "symbol": "NotificationManager.notify",
      "type": "StateError",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L207"
     },
     {
      "branch": [],
      "guard": "reserved != null",
      "id": "NotificationManager.notify reserved != null return",
      "kind": "return",
      "messages": [],
      "symbol": "NotificationManager.notify",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L214"
     },
     {
      "branch": [],
      "guard": "closed",
      "id": "NotificationManager.enqueue closed throw",
      "kind": "throw",
      "messages": [
       "'Closed'"
      ],
      "symbol": "NotificationManager.enqueue",
      "type": "StateError",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L148"
     },
     {
      "branch": [
       "n.type case NotificationType.self"
      ],
      "guard": "(n.toAtSign ?? atSign) != atSign",
      "id": "NotificationManager.enqueue (n.toAtSign ?? atSign) != atSign throw",
      "kind": "throw",
      "messages": [
       "s"
      ],
      "symbol": "NotificationManager.enqueue",
      "type": "StateError",
      "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_secondary_server/lib/src/notification/notification_manager_impl.dart#L189"
     }
    ]
   },
   "hash": "6e8a48292ec822e7",
   "id": "bob-server-push",
   "intent": "Hand the stored notification to the feed of every monitor connection @bob's clients hold, each exactly once.",
   "lane": "bob.server",
   "links": [],
   "reached": {
    "from": "bob-server-accept",
    "kind": "via",
    "text": "via NotificationManager.notify, NotificationManager.enqueue",
    "via": [
     "NotificationManager.notify",
     "NotificationManager.enqueue"
    ]
   },
   "reviewed": "6e8a48292ec822e7",
   "skeleton": "loop final MonitorSink sink in _monitors.values.toList():\n  try:\n    sink.push\n  on any:\n    who = describeInboundConnection\n    report.abandon\nreport.seal\n",
   "snippet": {
    "cut": false,
    "startLine": 236,
    "text": "  void _pushToMonitors(AtNotification n, {LivePushReport? report}) {\n    for (final MonitorSink sink in _monitors.values.toList()) {\n      final int counted = report?.counted ?? 0;\n      try {\n        sink.push(n, report: report);\n      } catch (e, st) {\n        // NOTE one feed's failure neither stops the rest nor reaches the\n        // sender, since the notification is already held.\n        final AtConnectionMetaData metaData = sink.connection.metaData;\n        final String who = metaData is InboundConnectionMetadata\n            ? describeInboundConnection(metaData)\n            : 'session ${metaData.sessionID}';\n        logger.severe('$e while handing notification ${n.id}'\n            ' (${sanitiseForLogging(n.notification ?? '')}) to the monitor'\n            ' feed of $who\\n$st');\n        report?.abandon(counted);\n      }\n    }\n    report?.seal();\n  }"
   },
   "touches": [
    "notification-store"
   ]
  },
  {
   "anchor": {
    "contains": "await handleNotification(notification);",
    "path": "packages/at_client/lib/src/manager/monitor.dart",
    "root": "sdk",
    "symbol": "Monitor._onNotification",
    "url": "../../packages/at_client/lib/src/manager/monitor.dart"
   },
   "changed": false,
   "contracts": [],
   "hash": "c19f50b1766931e5",
   "id": "bob-receive",
   "intent": "Pause the monitor stream while a notification is handled, so notifications are handled one at a time and in order.",
   "lane": "bob.client",
   "links": [],
   "reached": {
    "from": "bob-server-push",
    "kind": "push",
    "text": "push: the atServer writes the notification to the monitor connection, which at_lookup delivers as a stream"
   },
   "reviewed": "c19f50b1766931e5",
   "skeleton": "lastReceipt = DateTime.now, DateTime.now().toUtc\nsubscription.pause\ntry:\n  await handleNotification\non any:\nfinally:\n  subscription.resume\n",
   "snippet": {
    "cut": false,
    "text": "  Future\u003cvoid\u003e _onNotification(String notification) async {\n    lastReceipt = DateTime.now().toUtc();\n    // Paused for the duration of the handler, as the socket-owning Monitor\n    // was. `listen` discards the future an async callback returns, so without\n    // this two notifications are handled at once: the watermark is written out\n    // of arrival order, and a reconnect's retained backlog arrives as fast as\n    // the atServer can send rather than as fast as this client can absorb.\n    // at_lookup carries the pause down to the socket.\n    //\n    // NOTE Safe only while [lookUp] is this monitor's own: on one shared with\n    // RemoteSecondary the handler's own put would wait for a response on the\n    // socket it has just paused.\n    final subscription = _notificationSubscription;\n    subscription?.pause();\n    try {\n      await handleNotification(notification);\n    } catch (e, st) {\n      logger.shout('Caught $e while handling $notification\\n$st');\n    } finally {\n      subscription?.resume();\n    }\n  }"
   },
   "sublane": "Monitor",
   "touches": []
  },
  {
   "anchor": {
    "contains": "_lastReceivedMillis = n.epochMillis;",
    "path": "packages/at_client/lib/src/service/notification_service_impl.dart",
    "root": "sdk",
    "symbol": "NotificationServiceImpl.handleNotificationReceipt",
    "url": "../../packages/at_client/lib/src/service/notification_service_impl.dart"
   },
   "changed": false,
   "contracts": [],
   "hash": "fe2417dbf132ca3b",
   "id": "bob-deliver",
   "intent": "Parse the notification, deliver it to each matching subscriber in order, then save its time as the watermark a reconnect replays from.",
   "lane": "bob.client",
   "links": [],
   "reached": {
    "from": "bob-receive",
    "kind": "field",
    "text": "function-field hop through Monitor.handleNotification, bound in NotificationServiceImpl._"
   },
   "reviewed": "fe2417dbf132ca3b",
   "skeleton": "try:\n  if isStopped:\n    return\n  notifs = notificationParser.parse, notificationParser.getAtNotifications\n  _lastReceipt = DateTime.now, DateTime.now().toUtc\n  loop var n in notifs:\n    loop final entry in _streamListeners.entries.toList():\n      try:\n        await _deliver\n      on NskeyPrivateUnavailableException:\n        _park\n      on any:\n        if isStopped:\n          return\n        _drop\n    if n.id != '-1':\n      if n.epochMillis \u003e (_lastReceivedMillis ?? 0):\n        _lastReceivedMillis = n.epochMillis\n      if isStopped:\n        return\n      try:\n        await _watermarkValue, atClient.put\n      on any:\non any:\n  reason = e.toString\n  if !_droppedController.isClosed:\n    _droppedController.add\n",
   "snippet": {
    "cut": false,
    "text": "  Future\u003cvoid\u003e handleNotificationReceipt(String notificationJSON) async {\n    try {\n      logger.finest('DEBUG: $notificationJSON');\n      if (isStopped) return;\n\n      final notifs = notificationParser\n          .getAtNotifications(notificationParser.parse(notificationJSON));\n      _lastReceipt = DateTime.now().toUtc();\n      for (var n in notifs) {\n        if (n.key == myStatsNotifKey) {\n          logger.finer('Received ${n.key} (serverCommitId) ${n.value}');\n        } else {\n          logger.finer('Received ${n.key}');\n        }\n        // NOTE: a `for` loop, not `_streamListeners.forEach` — `Map.forEach`\n        // takes a void callback and discards the Future an `async` one\n        // returns, so every await below would run detached and delivery would\n        // not stay ordered. Order is what the values depend on: a content\n        // key is conveyed before the value citing it, and a subscriber that\n        // processes them out of order sees a value it cannot open. `.toList()`\n        // because a subscriber registering or cancelling mid-notification\n        // would otherwise throw ConcurrentModificationError.\n        final transforms = \u003cbool, Future\u003cAtNotification\u003e\u003e{};\n        for (final entry in _streamListeners.entries.toList()) {\n          final notificationConfig = entry.key;\n          final streamController = entry.value;\n          try {\n            await _deliver(n, notificationConfig, streamController, transforms);\n          } on NskeyPrivateUnavailableException catch (e) {\n            _park(e, n, notificationConfig, streamController);\n          } catch (e) {\n            if (isStopped) return;\n            // NOTE: `warning`, not `finer` — this notification is dropped here\n            // and never retried, and a silent drop is indistinguishable to the\n            // subscriber from one that was never sent.\n            _drop(\n                n.key,\n                'Dropping notification ${n.key} for subscriber '\n                '(regex \"${notificationConfig.regex}\"): $e');\n          }\n        }\n        // NOTE: after delivery, never before. A stop between the two then\n        // leaves the watermark behind a notification no subscriber saw, and\n        // the next connection replays it: at least once rather than lost.\n        if (n.id != '-1') {\n          if (n.epochMillis \u003e (_lastReceivedMillis ?? 0)) {\n            _lastReceivedMillis = n.epochMillis;\n          }\n          if (isStopped) return;\n          try {\n            await atClient.put(\n                lastReceivedNotificationAtKey, _watermarkValue(n),\n                putRequestOptions: _watermarkPutOptions);\n          } catch (e) {\n            if (isStopped) {\n              logger.finer('Not saving the last received notification ID: '\n                  'the service was stopped during the write ($e)');\n            } else {\n              logSwallowed(logger, e,\n                  'Failed to save last received notification ID: $e');\n            }\n          }\n        }\n      }\n    } catch (e) {\n      final reason = 'unexpected error:${e.toString()}'\n          ' while processing notificationJson: $notificationJSON';\n      logger.severe(reason);\n      if (!_droppedController.isClosed) {\n        _droppedController.add((key: '', reason: reason));\n      }\n    }\n  }"
   },
   "sublane": "NotificationService",
   "touches": []
  }
 ],
 "summary": "@alice's client puts @bob:note.ns@alice. The write lands in local storage and the sync queue, and sync pushes it to @alice's atServer in a batch: command. @alice's atServer stores it and, with autoNotify on, queues a notification for @bob. It proves itself to @bob's atServer with from: and pol, then sends notify:. @bob's atServer accepts the notification and pushes it to @bob's monitor connection, and @bob's client hands it to its subscribers.",
 "title": "@alice shares a record with @bob, and @bob's client hears of it",
 "unverified": 0
};
