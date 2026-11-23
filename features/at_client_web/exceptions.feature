Feature: Every exception the package declares is an AtException in one file

  lib/src/exceptions.dart declares each exception the session, the adapter and the
  opening layer throw; the bridge alone maps them to codes.

  Scenario: every exception the package declares is declared in lib/src/exceptions.dart
    Given every Dart file under packages/at_client_web/lib
    When each class that implements Exception or extends an exception type is located
    Then all of them are declared in lib/src/exceptions.dart and none anywhere else
    And SessionClosedException is among them

  Scenario: every exception the package declares is an AtException
    Given one instance of each exception lib/src/exceptions.dart declares
    When a Dart caller catches AtException
    Then every one of them is caught

  Scenario: the exceptions file reaches no web-only API
    Given lib/src/exceptions.dart and everything it imports inside the package
    Then none of them imports dart:js_interop, dart:js_interop_unsafe, dart:html or package:web
    And it imports no file under lib/src/js, lib/src/session, lib/src/collections or lib/src/keys

  Scenario: the barrels export every exception they exported before
    Given a Dart file that imports only package:at_client_web/at_client_web.dart, and one that imports only package:at_client_web/at_client_web_web.dart
    When the first names PortalSessionOfflineException and UnsupportedKeyMaterialException, and the second also names SetupLockTimeoutException, IndexedDbException and the at_client and at_auth passkey exceptions the barrel lists today
    Then both files analyze without error

  Scenario: a type renamed by the layering still resolves under its trunk name
    Given a Dart file that imports only package:at_client_web/at_client_web.dart
    When it names PortalSessionOfflineException, which the layering renamed to SessionOfflineException
    Then the file analyzes, with a deprecation notice that names SessionOfflineException
    And the old name is the new type, so a catch on either catches both

  Scenario: only the bridge and its code mapping name an error code
    Given every Dart file under packages/at_client_web/lib except lib/src/js/bridge.dart and the bridge's code-mapping file
    Then none holds a string literal that is one of the bridge's error codes or starts with COLLECTION_
    And no file under lib/src/collections or lib/src/session imports the bridge or its code mapping

  Scenario: the session and the adapter report caller mistakes with a typed exception
    Given a session built directly on a client, without the bridge
    When it is constructed with an invalid namespace, subscribe is called with an invalid regular expression, or collection is called with an invalid name
    Then each throws an exception declared in lib/src/exceptions.dart and never an ArgumentError
    And the bridge maps the first two to invalid_argument and the third to COLLECTION_INVALID_ARGUMENT
