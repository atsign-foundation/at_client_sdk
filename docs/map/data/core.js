window.MAP = {
 "flows": [
  {
   "id": "share-record",
   "lenses": [
    "notifications",
    "sync",
    "e2e"
   ],
   "title": "@alice shares a record with @bob, and @bob's client hears of it"
  }
 ],
 "inputs": {
  "model": "ecadfb15df2c368ef87853ba067972cf0b5207d1888ff27d3eaf15e2a674f084",
  "production": "3c3bd74b659b8f81f21c340ada455f9cda536fab",
  "server": "d654f25bd4bdef2668c77556f563f9e43960b325"
 },
 "laneNote": "Server lane at at_server trunk d654f25bd; production p3.19.0 is 160 commits behind.",
 "lanes": [
  {
   "id": "alice.client",
   "role": "client",
   "sublanes": [
    "AtClient",
    "Crypto",
    "LocalSecondary",
    "SyncService"
   ],
   "title": "@alice's client"
  },
  {
   "id": "alice.server",
   "role": "server",
   "sublanes": [],
   "title": "@alice's atServer"
  },
  {
   "id": "bob.server",
   "role": "server",
   "sublanes": [],
   "title": "@bob's atServer"
  },
  {
   "id": "bob.client",
   "role": "client",
   "sublanes": [
    "Monitor",
    "NotificationService"
   ],
   "title": "@bob's client"
  }
 ],
 "lenses": [
  {
   "flows": [
    "share-record"
   ],
   "id": "notifications",
   "links": [
    {
     "href": "packages/at_client/example/bin/notifications.dart",
     "title": "The notifications example"
    }
   ],
   "summary": "How a write on one atSign's client reaches another atSign's client as a notification, across both atServers.",
   "title": "Notifications and subscriptions"
  },
  {
   "flows": [
    "share-record"
   ],
   "id": "sync",
   "links": [
    {
     "href": "packages/at_client/README.md",
     "title": "at_client README"
    }
   ],
   "summary": "How a write lands in local storage first and reaches the atServer through the sync queue.",
   "title": "Online / offline, remote / local and sync"
  },
  {
   "flows": [
    "share-record"
   ],
   "id": "e2e",
   "links": [
    {
     "href": "packages/at_client/README.md",
     "title": "at_client README"
    }
   ],
   "summary": "Where a shared value is encrypted for its recipient before it leaves the client.",
   "title": "End-to-end encryption"
  }
 ],
 "roots": {
  "productionTag": "p3.19.0",
  "sdk": "atsign-foundation/at_client_sdk",
  "server": "atsign-foundation/at_server",
  "serverBranch": "trunk",
  "serverSha": "d654f25bd4bdef2668c77556f563f9e43960b325"
 },
 "stores": [
  {
   "id": "sync-queue",
   "root": "sdk",
   "symbol": "AtSyncQueue",
   "title": "the client's sync queue",
   "url": "../../packages/at_client/lib/src/sync/at_sync_queue.dart"
  },
  {
   "id": "keystore",
   "root": "server",
   "symbol": "AtKeyValueStore",
   "title": "the atServer's keystore",
   "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_persistence_secondary_server/lib/src/spec/keystore/at_keyvalue_store.dart"
  },
  {
   "id": "commit-log",
   "root": "server",
   "symbol": "AtCommitLog",
   "title": "the atServer's commit log",
   "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_persistence_secondary_server/lib/src/spec/commitlog/at_commit_log.dart"
  },
  {
   "id": "notification-store",
   "root": "server",
   "symbol": "AtNotificationKeystore",
   "title": "the atServer's notification store",
   "url": "https://github.com/atsign-foundation/at_server/blob/d654f25bd4bdef2668c77556f563f9e43960b325/packages/at_persistence_secondary_server/lib/src/spec/notifications/at_notification_keystore.dart"
  }
 ]
};
