/// The browser platform library: the core API, in-memory storage, the passkey
/// entry points, and the session and exceptions they return and throw.
library;

export 'package:at_auth/passkey.dart' show PrfUnavailableException;
export 'package:at_client/at_client.dart';
export 'package:at_client/memory.dart';
export 'package:at_client/passkey.dart'
    show
        AtServerAtKeysLockedException,
        MissingAtKeysDocumentException,
        PasskeyLostException,
        PasskeyOnboardingIncompleteException,
        PasskeySession,
        PkamRefusedException,
        PublicKeyMismatchException;

export 'at_client_web.dart';
export 'src/keys/indexeddb_store.dart' show IndexedDbException;
export 'src/session/session_transport.dart';
export 'src/session/web_passkey_entry.dart'
    show clearPrfMiss, onboardNewAtSign, passkeyLogin, prfSupported;
export 'src/session/web_setup_lock.dart' show SetupLockTimeoutException;
