Feature: at_client_flutter gives an app its platform defaults

  at_client's verbs take the store, the transport and the atDirectory finder
  explicitly. A Flutter app with its own UI calls them through AtsignFlows,
  which supplies them: Hive in the app's support directory (storageOrDefault),
  TLS on TCP, and the atDirectory the preference names. A pending
  enrollment's client takes its store from storageOrDefault. The dialogs run
  their verbs through an AtsignFlows too, given as their flows, so an app's
  widget test can stand in for them.

  Each AtsignFlows verb also takes the other options its Atsign verb takes
  (activate's provisioningBudget among them, open's serviceFactory, enroll's
  apkamKeysExpiry) and passes each on unchanged, with the Atsign verb's own
  defaults. It does not take the connection (atLookUp) an Atsign verb can be
  handed instead of building one, since supplying that is what it is for.

  Races: none arise; the defaults are chosen once per call, as the dialogs
  chose them.
  Replay: none arise; the verbs are at_client's, unchanged.
  DoS: none arise; nothing is opened until a verb runs, and a provisioning
  budget or poll interval reaches the Atsign verb as given.
  Forgery and impersonation: none arise; authentication is unchanged, and the
  default store is the atSign's own, as before. A posture or scope option
  (signingAlgo, mintLegacyMaterial, namespace) reaches the Atsign verb as
  given, and one not given reaches it as null, so the Atsign verb applies
  its own default and its own refusals.

  Scenario: A widget test stands in for the verbs a dialog runs
    Given an AtsignFlows of the app's own whose open fails
    When a PkamDialog given it as its flows is shown
    Then the dialog runs the stand-in's open for its atSign, and pops with no client

  Scenario: With no store named, the default is Hive in the app's support directory
    Given a preference that names no hiveStoragePath
    When the app asks storageOrDefault for an atSign's store
    Then it is a Hive store in the app's support directory, which the client closes

  Scenario: An activation through AtsignFlows names the device the app gave
    Given a device name the app chose
    When the app activates through AtsignFlows
    Then the enrollment request Atsign.activate sends names that device

  Scenario: An activation given no device names Atsign.activate's own
    Given no device name
    When the app activates through AtsignFlows
    Then the enrollment request names Atsign.activate's default device

  Scenario: A client opened through AtsignFlows takes the namespace the app gave
    Given a namespace the app chose, and a preference that names none
    When the app opens through AtsignFlows
    Then the client's namespace is the one the app gave

  Scenario: A client opened given no namespace takes the preference's own
    Given no namespace, and a preference that names none
    When the app opens through AtsignFlows
    Then the client names no namespace

  Scenario: An enrollment through AtsignFlows asks for the key expiry the app gave
    Given a key expiry the app chose
    When the app enrolls through AtsignFlows
    Then the enrollment request asks for that expiry

  Scenario: An enrollment given no key expiry asks for none
    Given no key expiry
    When the app enrolls through AtsignFlows
    Then the enrollment request asks for no expiry
