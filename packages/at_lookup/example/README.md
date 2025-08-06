<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

### Now for a little internet optimism

# at_lookup_example library

The atlookup package is an interface between the Client SDK and the cloud secondary.

## Give it a try

This package includes a sample code in
the [example](https://github.com/atsign-foundation/at_libraries/blob/doc_at_lookup/at_lookup/example/bin/example.dart)
directory for usage of the at_lookup library.

### Usage

#### Initializing the atLookup Instance

```dart

var atLookupImpl = AtLookupImpl(
  '@alice',
  'root.atsign.com',
  64,
  privateKey: 'privateKey',
  cramSecret: 'cramSecret',
);
```

#### Update the key

```dart
//Build update verb builder
var updateVerbBuilder = UpdateVerbBuilder()
  ..atKey = 'phone'
  ..sharedBy = '@alice'
  ..sharedWith = '@bob'
  ..value = '+1 889 886 7879';

// Sends update command to secondary server
// Set sync attribute to true sync the value to secondary server.
var updateResult = atLookupImpl.executeVerb(updateVerbBuilder, sync: true);
```

#### Get the value of the key

```dart
// Builds lookup key builder
var lookupVerbBuilder = LookupVerbBuilder()
  ..atKey = 'phone'
  ..sharedBy = '@bob'
  ..auth = true;
// Sends lookup command to secondary server
var lookupResult = atLookupImpl.executeVerb(lookupVerbBuilder);
```

#### Retrieve the keys from the secondary server

```dart
// Builds scan verb builder
var scanVerbBuilder = ScanVerbBuilder();
var scanResult = atLookupImpl.executeVerb(scanVerbBuilder);
```

#### Delete the key from secondary server

```dart
//Builds delete verb builder
var deleteVerbBuilder = DeleteVerbBuilder()
    ..sharedWith = '@bob'
    ..atKey = 'phone'
    ..sharedBy = '@alice';
// Sends delete key to secondary server  
var deleteResult = atLookupImpl.executeVerb(deleteVerbBuilder, sync: true);
```