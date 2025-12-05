---
date: 2025-12-09T15:04:21-05:00
researcher: xavierchanth
git_commit: fda3b0911bd98c07f21e6f3554cbbcdc1d52f1c6
branch:
repository: at_sdk
topic: "Singleton to Dependency Injection Migration Analysis"
tags: [research, codebase, singleton, dependency-injection, refactoring-analysis]
status: complete
last_updated: 2025-12-09
last_updated_by: xavierchanth
---

# Research: Singleton to Dependency Injection Migration Analysis

**Date**: 2025-12-09T15:04:21-05:00
**Researcher**: xavierchanth
**Git Commit**: fda3b0911bd98c07f21e6f3554cbbcdc1d52f1c6
**Branch**: (detached HEAD or untracked)
**Repository**: at_sdk

## Research Question

What would it take to drop singletons (.getInstance()) from the codebase and replace all usage with dependency injection?

## Summary

The at_sdk codebase contains **50+ singleton implementations** using the `.getInstance()` pattern across 15+ packages. These singletons form a **3-level deep dependency hierarchy** with AtClientManager at the root, used 366 times across 133 files. The codebase already has **mature dependency injection patterns** including constructor injection, factory methods, and an abstract service factory (AtServiceFactory). Migration would require systematic refactoring from the bottom-up, starting with infrastructure singletons and propagating through service layers to UI components.

## Detailed Findings

### 1. Singleton Distribution by Package

#### Core SDK Layer (packages/at_client)
- **AtClientManager** - 366 occurrences across 133 files ([at_client_manager.dart:40](packages/at_client/lib/src/manager/at_client_manager.dart))
- **AtClientConfig** - 4 occurrences across 3 files ([at_client_config.dart:3](packages/at_client/lib/src/preference/at_client_config.dart))
- **SyncManagerImpl** - Deprecated ([sync_manager_impl.dart:7](packages/at_client/lib/src/manager/sync_manager_impl.dart))
- **SyncIsolateManager** - Deprecated ([sync_isolate_manager.dart:13](packages/at_client/lib/src/manager/sync_isolate_manager.dart))
- **AtCollectionModelFactoryManager** - 28 occurrences across 6 files ([at_collection_model_factory.dart:19](packages/at_client/lib/src/at_collection/at_collection_model_factory.dart))

#### Mobile Layer (packages/at_client_mobile)
- **KeyChainManager** - 46 occurrences across 19 files ([keychain_manager.dart:29](packages/at_client_mobile/lib/src/keychain_manager.dart))

#### Onboarding Layer (packages/at_onboarding_flutter)
- **OnboardingService** - 20 occurrences across 14 files ([onboarding_service.dart:14](packages/at_onboarding_flutter/lib/services/onboarding_service.dart))
- **BackendService** - Minimal usage ([backend_service.dart:2](packages/at_onboarding_flutter/lib/services/backend_service.dart))
- **AtOnboardingBackupService** - Minimal usage ([at_onboarding_backup_service.dart:9](packages/at_onboarding_flutter/lib/services/at_onboarding_backup_service.dart))

#### Feature Services Layer
- **ContactService** (at_contacts_flutter) - 72 occurrences across 19 files ([contact_service.dart:20](packages/at_contacts_flutter/lib/services/contact_service.dart))
- **GroupService** (at_contacts_group_flutter) - ([group_service.dart:23](packages/at_contacts_group_flutter/lib/services/group_service.dart))
- **ChatService** (at_chat_flutter) - ([chat_service.dart:14](packages/at_chat_flutter/lib/services/chat_service.dart))
- **InvitationService** (at_invitation_flutter) - ([invitation_service.dart:17](packages/at_invitation_flutter/lib/services/invitation_service.dart))
- **NotifyService** (at_notify_flutter) - ([notify_service.dart:16](packages/at_notify_flutter/lib/services/notify_service.dart))
- **ThemeService** (at_theme_flutter) - ([theme_service.dart:10](packages/at_theme_flutter/lib/services/theme_service.dart))
- **AtSyncUI** (at_sync_ui_flutter) - ([at_sync_ui.dart:64](packages/at_sync_ui_flutter/lib/at_sync_ui.dart))
- **AtFollowServices** (at_follows_flutter) - ([at_follow_services.dart](packages/at_follows_flutter/lib/utils/at_follow_services.dart))

#### Location Services Layer (packages/at_location_flutter) - 11 singletons
- **LocationService** ([location_service.dart:22](packages/at_location_flutter/lib/service/location_service.dart))
- **MasterLocationService** ([master_location_service.dart:18](packages/at_location_flutter/lib/service/master_location_service.dart))
- **KeyStreamService** ([key_stream_service.dart:19](packages/at_location_flutter/lib/service/key_stream_service.dart))
- **SendLocationNotification** ([send_location_notification.dart:32](packages/at_location_flutter/lib/service/send_location_notification.dart))
- **HomeScreenService** ([home_screen_service.dart](packages/at_location_flutter/lib/service/home_screen_service.dart))
- **SearchLocationService** ([search_location_service.dart](packages/at_location_flutter/lib/service/search_location_service.dart))
- **AtLocationNotificationListener** ([at_location_notification_listener.dart:27](packages/at_location_flutter/lib/service/at_location_notification_listener.dart))
- **NotifyAndPut** ([notify_and_put.dart:9](packages/at_location_flutter/lib/service/notify_and_put.dart))
- **DistanceCalculate** ([distance_calculate.dart](packages/at_location_flutter/lib/service/distance_calculate.dart))
- **ConnectivityService** ([api_service.dart](packages/at_location_flutter/lib/service/api_service.dart))

#### Events Services Layer (packages/at_events_flutter) - 6 singletons
- **EventService** ([event_services.dart](packages/at_events_flutter/lib/services/event_services.dart))
- **HomeEventService** ([home_event_service.dart](packages/at_events_flutter/lib/services/home_event_service.dart))
- **EventKeyStreamService** ([event_key_stream_service.dart](packages/at_events_flutter/lib/services/event_key_stream_service.dart))
- **AtEventNotificationListener** ([at_event_notification_listener.dart](packages/at_events_flutter/lib/services/at_event_notification_listener.dart))
- **VenuesServices** ([venues_services.dart](packages/at_events_flutter/lib/services/venues_services.dart))
- **EventsMapScreenData** ([events_map_screen.dart](packages/at_events_flutter/lib/screens/map_screen/events_map_screen.dart))

#### UI Utility Singletons (multiple packages)
- **SizeConfig** - Found in at_common_flutter, at_login_flutter, at_follows_flutter, at_backupkey_flutter
- **CustomToast** - Found in at_theme_flutter, at_location_flutter, at_events_flutter, at_contacts_group_flutter
- **LoadingDialog** - Found in at_location_flutter, at_events_flutter, at_contacts_group_flutter
- **CustomTextStyles** - Found in at_common_flutter, at_contacts_flutter, at_contacts_group_flutter, at_location_flutter, at_events_flutter, at_invitation_flutter
- **Color/Text Constants** - AllColors, AllText, AllImages, TextConstants across multiple packages

### 2. Singleton Dependency Chains

#### Chain 1: Core Client Operations (Depth: 3)
```
RemoteSecondary/LocalSecondary/AtClientImpl
    ├─> AtClientManager.getInstance()
    │   └─> [root singleton]
    ├─> AtClientConfig.getInstance()
    │   └─> [root singleton]
    └─> SecondaryPersistenceStoreFactory.getInstance()
        └─> [root singleton]
```

**Evidence**:
- [at_client_impl.dart:144](packages/at_client/lib/src/client/at_client_impl.dart) - AtClientManager usage
- [at_client_impl.dart:239](packages/at_client/lib/src/client/at_client_impl.dart) - AtClientConfig usage
- [at_client_impl.dart:242](packages/at_client/lib/src/client/at_client_impl.dart) - SecondaryPersistenceStoreFactory usage
- [remote_secondary.dart:47](packages/at_client/lib/src/client/remote_secondary.dart) - AtClientManager.secondaryAddressFinder
- [local_secondary.dart:25](packages/at_client/lib/src/client/local_secondary.dart) - SecondaryPersistenceStoreFactory usage

#### Chain 2: Onboarding Flow (Depth: 3)
```
OnboardingService
    └─> KeyChainManager.getInstance()
        └─> [root singleton]
    └─> AtClientManager (via deprecated AtClientService)
        └─> [root singleton]
```

**Evidence**:
- [onboarding_service.dart:22](packages/at_onboarding_flutter/lib/services/onboarding_service.dart) - KeyChainManager dependency

#### Chain 3: Location Services (Depth: 3)
```
SendLocationNotification
    └─> AtLocationNotificationListener()
        ├─> AtClientManager.getInstance() (lines 50, 51, 62, 82)
        └─> KeyChainManager.getInstance() (line 75)
```

**Evidence**:
- [send_location_notification.dart:69](packages/at_location_flutter/lib/service/send_location_notification.dart) - AtLocationNotificationListener dependency
- [at_location_notification_listener.dart:50-82](packages/at_location_flutter/lib/service/at_location_notification_listener.dart) - Multiple AtClientManager calls

#### Chain 4: Flutter Services (Depth: 2)
```
ContactService/InvitationService/GroupService/NotifyService
    └─> AtClientManager.getInstance()
        └─> [root singleton]
```

**Evidence**:
- [invitation_service.dart:49, 92, 100, 120, 131, 148](packages/at_invitation_flutter/lib/services/invitation_service.dart) - AtClientManager usage
- [group_service.dart:121](packages/at_contacts_group_flutter/lib/services/group_service.dart) - AtClientManager usage

**No circular dependencies detected** - all dependency graphs are acyclic with clear hierarchical structure.

### 3. Existing Dependency Injection Patterns

#### Pattern 3.1: Constructor Injection (Primary Pattern)

**Example 1: EnrollmentServiceImpl** ([enrollment_service_impl.dart](packages/at_client/lib/src/service/enrollment_service_impl.dart))
```dart
class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollment _atEnrollmentImpl;

  EnrollmentServiceImpl(this._atClient, this._atEnrollmentImpl);

  // Uses injected dependencies throughout
}
```

**Example 2: SharedKeyEncryption** ([shared_key_encryption.dart](packages/at_client/lib/src/encryption_service/shared_key_encryption.dart))
```dart
class SharedKeyEncryption extends AbstractAtKeyEncryption {
  final AtClient _atClient;

  SharedKeyEncryption(this._atClient) : super(_atClient) {
    // Initialization
  }
}
```

**Example 3: CacheableSecondaryAddressFinder** ([cacheable_secondary_address_finder.dart](packages/at_lookup/lib/src/cache/cacheable_secondary_address_finder.dart))
```dart
class CacheableSecondaryAddressFinder implements SecondaryAddressFinder {
  final String _rootDomain;
  final int _rootPort;
  late SecondaryUrlFinder _secondaryFinder;

  CacheableSecondaryAddressFinder(this._rootDomain, this._rootPort,
      {SecondaryUrlFinder? secondaryFinder, SecureSocketConfig? socketConfig}) {
    _secondaryFinder = secondaryFinder ??
        SecondaryUrlFinder(_rootDomain, _rootPort, socketConfig: socketConfig);
  }
}
```

#### Pattern 3.2: Abstract Service Factory

**AtServiceFactory** ([at_client_manager.dart:157-205](packages/at_client/lib/src/manager/at_client_manager.dart))
```dart
abstract class AtServiceFactory {
  Future<AtClient> atClient(...);
  Future<NotificationService> notificationService(...);
  Future<SyncService> syncService(...);
  EnrollmentService enrollmentService(...);
}

class DefaultAtServiceFactory implements AtServiceFactory {
  @override
  Future<AtClient> atClient(String atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {AtChops? atChops, AtLookUp? atLookUp, String? enrollmentId}) async {
    return await AtClientImpl.create(atSign, namespace, preference,
        atClientManager: atClientManager,
        atChops: atChops,
        atLookUp: atLookUp,
        enrollmentId: enrollmentId);
  }
  // ... other factory methods
}
```

**Usage**: AtClientManager.setCurrentAtSign() accepts a custom AtServiceFactory parameter, allowing complete control over service instantiation.

**Custom Implementation Example**: [service_factories.dart](packages/at_onboarding_cli/lib/src/factory/service_factories.dart)
```dart
class ServiceFactoryWithNoOpSyncService extends DefaultAtServiceFactory {
  @override
  Future<SyncService> syncService(
      AtClient atClient,
      AtClientManager atClientManager,
      NotificationService notificationService) async {
    return NoOpSyncService();
  }
}
```

#### Pattern 3.3: Static Factory Methods with DI

**SyncServiceImpl** ([sync_service_impl.dart:86-102](packages/at_client/lib/src/service/sync_service_impl.dart))
```dart
class SyncServiceImpl implements SyncService {
  late final AtClient _atClient;
  late final RemoteSecondary _remoteSecondary;
  late final NotificationServiceImpl _statsNotificationListener;

  SyncServiceImpl._(
      AtClientManager atClientManager,
      AtClient atClient,
      NotificationService notificationService,
      RemoteSecondary remoteSecondary) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _remoteSecondary = remoteSecondary;
    // ... initialization
  }

  static Future<SyncService> create(AtClient atClient,
      {required AtClientManager atClientManager,
      required NotificationService notificationService,
      RemoteSecondary? remoteSecondary}) async {
    remoteSecondary ??= RemoteSecondary(...);
    final syncService = SyncServiceImpl._(
        atClientManager, atClient, notificationService, remoteSecondary);
    await syncService.statsServiceListener();
    return syncService;
  }
}
```

**NotificationServiceImpl** ([notification_service_impl.dart:87-111](packages/at_client/lib/src/service/notification_service_impl.dart))
```dart
class NotificationServiceImpl implements NotificationService {
  static Future<NotificationService> create(AtClient atClient,
      {required AtClientManager atClientManager, Monitor? monitor}) async {
    final notificationService =
        NotificationServiceImpl._(atClientManager, atClient, monitor: monitor);
    return notificationService;
  }

  NotificationServiceImpl._(AtClientManager atClientManager, AtClient atClient,
      {Monitor? monitor}) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _monitor = monitor ?? Monitor(...);
  }
}
```

#### Pattern 3.4: Provider Pattern (Flutter State Management)

**ConnectionProvider** ([connection_model.dart](packages/at_follows_flutter/lib/domain/connection_model.dart))
```dart
class ConnectionProvider extends ChangeNotifier {
  static final _singleton = ConnectionProvider._internal();
  ConnectionProvider._internal();

  factory ConnectionProvider() {
    return _singleton;
  }

  late ConnectionsService _connectionsService;

  init(String atsign) {
    if (atsign != initialised) {
      _connectionsService = ConnectionsService();
      // ... initialization
    }
  }
}
```

**Usage in widgets**:
```dart
body: ChangeNotifierProvider<ConnectionProvider>.value(
  value: _connectionProvider,
  child: // ... widget tree
)
```

#### Pattern 3.5: Setter Injection

**AtClient services** ([at_client_impl.dart:90-118](packages/at_client/lib/src/client/at_client_impl.dart))
```dart
late SyncService _syncService;

@override
set syncService(SyncService syncService) {
  _syncService = syncService;
}

late NotificationService _notificationService;

@override
set notificationService(NotificationService notificationService) {
  _notificationService = notificationService;
}
```

**Usage** ([at_client_manager.dart:85-102](packages/at_client/lib/src/manager/at_client_manager.dart)):
```dart
_currentAtClient = await serviceFactory.atClient(...);

var notificationService = await serviceFactory.notificationService(_currentAtClient!, this);
_currentAtClient!.notificationService = notificationService;

var syncService = await serviceFactory.syncService(_currentAtClient!, this, notificationService);
_currentAtClient!.syncService = syncService;
```

### 4. Singleton Pattern Variations

#### Variation 1: Classic getInstance()
```dart
class AtClientManager {
  static final AtClientManager _singleton = AtClientManager._internal();
  AtClientManager._internal();

  factory AtClientManager.getInstance() {
    return _singleton;
  }
}
```
Used by: AtClientManager, KeyChainManager, OnboardingService, BackendService

#### Variation 2: Dart Factory Constructor
```dart
class ContactService {
  static final ContactService _instance = ContactService._();
  ContactService._();

  factory ContactService() => _instance;
}
```
Used by: ContactService, GroupService, LocationService, ChatService, InvitationService, NotifyService

#### Variation 3: Instance Property
```dart
class AtSyncUI {
  static final AtSyncUI _instance = AtSyncUI._();
  AtSyncUI._();

  static AtSyncUI get instance => _instance;
}
```
Used by: AtSyncUI, AtOnboardingBackupService

### 5. Test Dependency Injection Examples

**enrollment_service_test.dart** ([enrollment_service_test.dart:24-39](packages/at_client/test/enrollment_service_test.dart))
```dart
void main() {
  String currentAtSign = '@alice';
  late AtClient atClient;
  MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();

  setUpAll(() async {
    AtChops atChops = await TestUtils.getAtChops();
    atClient = await AtClientImpl.create(
        currentAtSign,
        'wavi',
        AtClientPreference()
          ..isLocalStoreRequired = true
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/commit',
        enrollmentId: enrollmentId,
        atChops: atChops,
        remoteSecondary: mockRemoteSecondary);  // Mock injected
    atClient.syncService = MockSyncService();   // Mock injected via setter
  });
}
```

This demonstrates the codebase **already supports DI for testing** - mocks can be injected via constructor parameters and setters.

### 6. Migration Requirements

#### Phase 1: Infrastructure Layer (Bottom-Up)
**Target**: Root singletons with no dependencies
- AtClientConfig (4 occurrences, 3 files)
- SecondaryPersistenceStoreFactory (16 occurrences, 9 files)
- AtCommitLogManagerImpl (21 occurrences, 12 files)
- AtCollectionModelFactoryManager (28 occurrences, 6 files)

**Approach**:
- Convert to injectable instances
- Update factory methods to accept these as parameters
- Modify AtClientManager to hold and provide these instances

#### Phase 2: Core Manager Layer
**Target**: AtClientManager (366 occurrences, 133 files)
- This is the central singleton that most code depends on
- Already has constructor-based instantiation for testing
- Already provides AtServiceFactory for customization

**Approach**:
- Create application-level composition root
- Inject AtClientManager into top-level components
- Use existing AtServiceFactory mechanism for service creation
- Propagate through widget trees using Provider/InheritedWidget

#### Phase 3: Mobile Layer
**Target**: KeyChainManager (46 occurrences, 19 files)
- Used by OnboardingService and mobile authentication flows
- Platform-specific initialization in factory constructor

**Approach**:
- Extract platform-specific initialization
- Inject KeyChainManager into services that need it
- Update OnboardingService to receive via constructor

#### Phase 4: Service Layer
**Target**: Feature services (ContactService, InvitationService, etc.)
- Already many services use constructor injection internally
- Singletons mainly at service boundary

**Approach**:
- Convert service singletons to instances
- Use Provider pattern for Flutter state management
- Inject via widget initialization or routing

#### Phase 5: UI Layer
**Target**: UI utility singletons (SizeConfig, CustomToast, etc.)
- Mostly stateless utilities
- Could remain static or convert to dependency injection

**Approach**:
- Low priority - these are utilities with minimal coupling
- Could use InheritedWidget/Provider for theme/config
- Or keep as static utilities (acceptable for pure utilities)

### 7. Existing DI-Ready Infrastructure

The codebase already has strong DI support:

1. **AtServiceFactory abstraction** - Allows complete control over service instantiation
2. **Static factory methods** - Most services have `create()` methods accepting dependencies
3. **Constructor injection** - Core services use constructor-based DI
4. **Optional parameters** - Many constructors support optional dependencies for flexibility
5. **Setter injection** - Services can be replaced after construction for testing
6. **Provider pattern** - Flutter packages already use ChangeNotifierProvider
7. **Test infrastructure** - Tests demonstrate successful mock injection

### 8. Migration Complexity Analysis

#### Low Complexity (Can migrate independently)
- UI utility singletons (SizeConfig, CustomToast, etc.) - 15+ classes
- Deprecated singletons (SyncManagerImpl, SyncIsolateManager) - 2 classes
- BackendService (minimal usage) - 1 class

#### Medium Complexity (Requires coordinated updates)
- AtClientConfig - 4 occurrences
- AtCollectionModelFactoryManager - 28 occurrences
- KeyChainManager - 46 occurrences
- Feature services (ContactService, etc.) - 72+ occurrences

#### High Complexity (Core infrastructure)
- AtClientManager - 366 occurrences across 133 files
- External persistence factories (SecondaryPersistenceStoreFactory, AtCommitLogManagerImpl)

#### Dependency Propagation
Migration must follow dependency direction:
```
Infrastructure singletons (Phase 1)
    ↓
AtClientManager (Phase 2)
    ↓
KeyChainManager (Phase 3)
    ↓
Service layer singletons (Phase 4)
    ↓
UI utilities (Phase 5)
```

### 9. Example Migration Pattern

#### Before (Singleton):
```dart
// Service implementation
class ContactService {
  static final ContactService _instance = ContactService._();
  ContactService._();
  factory ContactService() => _instance;

  late AtClient _atClient;

  Future<void> init() async {
    _atClient = AtClientManager.getInstance().atClient;
  }
}

// Usage
ContactService().init();
var contacts = await ContactService().getContacts();
```

#### After (Dependency Injection):
```dart
// Service implementation
class ContactService {
  final AtClient _atClient;

  ContactService(this._atClient);

  Future<List<Contact>> getContacts() async {
    // Use _atClient
  }
}

// Composition root (app initialization)
class AppDependencies {
  late final AtClientManager atClientManager;
  late final ContactService contactService;

  Future<void> initialize() async {
    atClientManager = AtClientManager('@alice');
    await atClientManager.setCurrentAtSign('@alice', 'namespace', prefs);
    contactService = ContactService(atClientManager.atClient);
  }
}

// Widget usage with Provider
void main() {
  final deps = AppDependencies();
  await deps.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider<AtClientManager>.value(value: deps.atClientManager),
        Provider<ContactService>.value(value: deps.contactService),
      ],
      child: MyApp(),
    ),
  );
}

// Widget access
class ContactsWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final contactService = Provider.of<ContactService>(context, listen: false);
    // Use contactService
  }
}
```

## Code References

### Key Singleton Implementations
- `packages/at_client/lib/src/manager/at_client_manager.dart:40` - AtClientManager singleton
- `packages/at_client_mobile/lib/src/keychain_manager.dart:29` - KeyChainManager singleton
- `packages/at_onboarding_flutter/lib/services/onboarding_service.dart:14` - OnboardingService singleton
- `packages/at_contacts_flutter/lib/services/contact_service.dart:20` - ContactService singleton

### Key DI Implementations
- `packages/at_client/lib/src/manager/at_client_manager.dart:157` - AtServiceFactory abstraction
- `packages/at_client/lib/src/service/sync_service_impl.dart:86` - SyncServiceImpl with private constructor DI
- `packages/at_client/lib/src/service/notification_service_impl.dart:87` - NotificationServiceImpl with DI
- `packages/at_client/lib/src/service/enrollment_service_impl.dart` - EnrollmentServiceImpl pure DI example

### Dependency Chains
- `packages/at_client/lib/src/client/at_client_impl.dart:144,239,242` - Multiple singleton dependencies
- `packages/at_client/lib/src/client/remote_secondary.dart:47` - AtClientManager usage
- `packages/at_onboarding_flutter/lib/services/onboarding_service.dart:22` - KeyChainManager dependency
- `packages/at_invitation_flutter/lib/services/invitation_service.dart:49` - AtClientManager usage

## Architecture Documentation

### Current Singleton Architecture

```
Application Layer (UI/Widgets)
    ↓ (calls getInstance())
Feature Services Layer (ContactService, LocationService, etc.)
    ↓ (calls getInstance())
Platform Layer (KeyChainManager, OnboardingService)
    ↓ (calls getInstance())
Core Manager Layer (AtClientManager)
    ↓ (calls getInstance())
Infrastructure Layer (Config, Persistence, Factories)
```

### Proposed DI Architecture

```
Application Layer (UI/Widgets)
    ↓ (receives via Provider/Constructor)
Feature Services Layer (ContactService, LocationService, etc.)
    ↓ (receives via Constructor)
Platform Layer (KeyChainManager, OnboardingService)
    ↓ (receives via Constructor)
Core Manager Layer (AtClientManager)
    ↓ (receives via Constructor)
Infrastructure Layer (Config, Persistence, Factories)
    ↑ (created at Composition Root)
Composition Root (App initialization)
```

### Existing DI Patterns by Layer

| Layer | Current Pattern | DI Support |
|-------|----------------|------------|
| Infrastructure | Singleton factories | Can be instantiated directly |
| Core Services | Static factory + DI | Already supports constructor injection |
| Platform Services | Singleton getInstance() | Limited DI support |
| Feature Services | Singleton getInstance() | No DI support currently |
| UI Layer | Direct singleton access | Provider pattern available |

## Historical Context (from thoughts/)

No existing research documents found specifically on singleton-to-DI migration.

## Related Research

No related research documents found in thoughts/shared/research/ directory.

## Open Questions

1. **AtClientManager scope**: Should AtClientManager be application-scoped (one per app) or session-scoped (one per @sign)?
   - Current implementation: One global instance managing current @sign
   - Alternative: Multiple instances for multi-tenant scenarios

2. **External persistence factories**: SecondaryPersistenceStoreFactory and AtCommitLogManagerImpl come from at_persistence_secondary_server package
   - Need to verify if these can be instantiated or require upstream changes
   - May need to maintain wrapper singletons if external package doesn't support DI

3. **Flutter widget tree integration**: How to propagate dependencies through deep widget trees?
   - Option A: Provider/Riverpod at app root
   - Option B: InheritedWidget for specific subtrees
   - Option C: Service locator pattern (GetIt, get_it package) as intermediate step

4. **UI utility singletons**: Should stateless utilities (SizeConfig, CustomToast) remain static?
   - Pure utilities with no state could remain static helpers
   - Theme-dependent utilities should use InheritedWidget/Provider
   - Recommendation: Defer UI utility migration to Phase 5

5. **Testing strategy**: How to maintain existing test suite during migration?
   - Tests already use DI via constructor injection
   - Can migrate incrementally by supporting both patterns temporarily
   - Use feature flags or factory methods during transition

6. **Performance implications**: Are there performance concerns with DI?
   - Singleton lazy initialization vs eager initialization at composition root
   - Memory: Multiple instances vs single instance (likely negligible)
   - Lookup time: Direct singleton access vs Provider lookup (microseconds difference)

7. **Breaking changes**: How to maintain backward compatibility?
   - Phase migration with deprecation warnings
   - Support both patterns during transition period
   - Major version bump for complete migration

8. **Composition root location**: Where should the composition root live?
   - Application main() for Flutter apps
   - AtClientManager.initialize() for library usage
   - Both patterns for flexibility?
