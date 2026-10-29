Feature: at_client_flutter gives an app its platform defaults

  at_client's verbs take the store, the transport and the atDirectory finder
  explicitly. A Flutter app with its own UI calls them through AtsignFlows,
  which supplies them: Hive in the app's support directory (storageOrDefault),
  TLS on TCP, and the atDirectory the preference names. A pending
  enrollment's client takes its store from storageOrDefault. The dialogs run
  their verbs through an AtsignFlows too, given as their flows, so an app's
  widget test can stand in for them.

  Races: none arise; the defaults are chosen once per call, as the dialogs
  chose them.
  Replay: none arise; the verbs are at_client's, unchanged.
  DoS: none arise; nothing is opened until a verb runs.
  Forgery and impersonation: none arise; authentication is unchanged, and the
  default store is the atSign's own, as before.

  Scenario: A widget test stands in for the verbs a dialog runs
    Given an AtsignFlows of the app's own whose open fails
    When a PkamDialog given it as its flows is shown
    Then the dialog runs the stand-in's open for its atSign, and pops with no client

  Scenario: With no store named, the default is Hive in the app's support directory
    Given a preference that names no hiveStoragePath
    When the app asks storageOrDefault for an atSign's store
    Then it is a Hive store in the app's support directory, which the client closes
