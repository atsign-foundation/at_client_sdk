<img width=250px src="https://atsign.dev/assets/img/atPlatform_logo_gray.svg?sanitize=true">

## Now for some internet optimism.

[![pub package](https://img.shields.io/pub/v/at_client)](https://pub.dev/packages/at_client) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client

### Introduction

The at_client library is the non-platform specific Client SDK which provides the essential methods for building an app using the atProtocol.

SDK that provides the essential methods for building an app using [The atProtocol](https://atsign.com). You may also want to look at [at_client_mobile](https://pub.dev/packages/at_client_mobile).

**at_client** package is written in Dart, supports Flutter and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data "*flipping the internet*".

## Get Started

Initially to get a basic overview of the SDK, you must read the [atsign docs](https://atsign.dev/docs/overview/).

> To use this package you must be having a basic setup, Follow here to [get started](https://atsign.dev/docs/get-started/setup-your-env/).

Check how to use this package in the [at_client installation tab](https://pub.dev/packages/at_client/install).

## Usage

- Set `AtClientPreferences` to your preferred settings.

```dart
Directory appSupportDir = await getApplicationSupportDirectory();
AtClientPreference preferences = AtClientPreference()
        ..rootDomain = 'root.atsign.org'
        ..namespace = '.my_namespace'
        ..hiveStoragePath = appSupportDir.path
        ..commitLogPath = appSupportDirdir.path
        ..isLocalStoreRequired = true;
```

- These `preferences` are used for your application.

```dart
AtClientManager atClientManagerInstance = await AtClientManager.getInstance().setCurrentAtSign(atSign, AtEnv.appNamespace, preferences);
```

- Update the user data using the `put()` method.

```dart
AtKey atKey = AtKey()
        ..key = 'phone'
        ..namespace = '.myApp';
await atClientInstance.put(atKey, '+00 123-456-7890');
```

- Get the data using the `get()` method.

```dart
AtKey atKey = AtKey()
        ..key='phone'
        ..namespace = '.myApp';
AtValue value = await atClientInstance.get(atKey);
print(value.value); // +00 123-456-7890
```

- Delete the data using the `delete()` method.

```dart
bool isDeleted = await atClientInstance.delete(atKey);
print(isDeleted); // true if deleted
```

- Sync the data to the server using the `sync()` method if needed.

```dart
late SyncService _syncService;
_syncService = atClientManagerInstance.syncService;
_syncService.sync(onDone: _onSuccessCallback); // prints 'Sync done' on done.

void _onSuccessCallback() {
  print('Sync done');
}
```

- Notify the server that the data has changed using the `notify()` method.

```dart
AtClientManager atClientManagerInstance = AtClientManager.getInstance();
MetaData metaData = Metadata()..ttl='60000'
               ..ttb='30000'
AtKey key = AtKey()..key='phone'
          ..sharedWith='@bob'
          ..metadata=metaData
        ..namespace = '.myApp';
String value = (await atClientInstance.get(atKey)).value;
OperationEnum operation = OperationEnum.update;
bool isNotified = await atClientManagerInstance.notify(atKey, value, operation);
print(isNotified); // true if notified
```

- Notify an update operation to an atsign.

```dart
String toAtsign = '@bob';
var key = AtKey()
        ..key = 'phone'
        ..sharedWith = toAtSign;
var notification = NotificationServiceImpl(atClient!);
await notification.notify(NotificationParams.forUpdate(key));
```

- Want to check connection status? Why another package in you app? Use `ConnectivityListener`.

```dart
ConnectivityListener().subscribe().listen((isConnected) {
  if (isConnected) {
    print('connection available');
   } else {
    print('connection lost');
  }
});
```

AtClient has many more methods that are exposed. Please refer to the [atsign docs](https://atsign.dev/docs/overview/) for more details.


## Example

We have a good example with explanation in the [at_client_mobile](https://pub.dev/packages/at_client_mobile/example) package.