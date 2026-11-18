Feature: Every authenticating from: names the program and the SDK that sent it

  Every from: a client sends to authenticate carries, in its clientConfig,
  the program's name and version and the SDK's name and version, and an
  at_client connection carries at_client's version as `version` too, so an
  atServer can tell which program and which build each connection came from.

  Races: the config is fixed when the client is built, and every connection
  sends the same one.
  Replay: the config carries no secret and no freshness; a resent from: is
  answered with a new challenge, as today.
  DoS: the config is a few short strings, each cut to 64 characters, built
  once per client.
  Forgery: the config is the client's own claim to its own atServer; a client
  that misstates it mislabels only its own connections, and no key added here
  changes how the atServer answers.
  Impersonation: the config names a program, never an atSign, and lets no one
  act as one.

  Scenario Outline: an at_client connection names its program and SDK
    Given an app whose atClientParticulars name it "acme_chat" version "2.3.1"
    When the client authenticates its <connection> connection
    Then the from: command's clientConfig has appName "acme_chat", appVersion "2.3.1", sdkName "atsign.dart.at_client" and sdkVersion at_client's version

    Examples:
      | connection         |
      | verb               |
      | sync               |
      | notification       |
      | start-up key check |

  Scenario: an app that names nothing is named after its program file
    Given an app run from "acme_chat.dart" that sets no appName or appVersion
    When the client authenticates a connection
    Then the from: command's clientConfig has appName "acme_chat" and appVersion "unknown"
    And the client logs one warning, naming atClientParticulars, when it starts

  Scenario: an app with no program file to name is "unknown"
    Given an app on a platform with no program file that sets no appName
    When the client authenticates a connection
    Then the from: command's clientConfig has appName "unknown"

  Scenario: a name or version longer than 64 characters is cut
    Given an app whose appName is 80 characters long
    When the client authenticates a connection
    Then the from: command's clientConfig has appName cut to its first 64 characters

  Scenario: every from: at_client sends carries version, at_client's version
    Given an app listening for notifications
    When the client authenticates its notification connection
    Then the from: command's clientConfig has version at_client's version
    And the verb connection's from: carries the same version

  Scenario: at_activate names itself and at_client
    Given at_activate onboarding an atSign
    When it authenticates with CRAM, then PKAM, and when it enrolls
    Then each from: command's clientConfig has appName "at_activate", appVersion at_client_cli's version, sdkName "atsign.dart.at_client" and sdkVersion at_client's version

  Scenario: a program using at_auth alone is named after at_auth
    Given a program that onboards through at_auth and passes no client config
    When at_auth authenticates
    Then the from: command's clientConfig has the program's derived appName, appVersion "unknown", sdkName "atsign.dart.at_auth" and sdkVersion at_auth's version, and no version

  Scenario: a version the caller gives that is null, empty or only whitespace is not sent
    Given a program that passes at_auth a client config whose version is null, "" or "  "
    When at_auth builds the from: command's clientConfig
    Then the clientConfig has no version, and a version with text in it is kept

  Scenario: a proxy root's preamble stays bare
    Given a client whose root is a proxy
    When it opens and authenticates a connection
    Then the first from: is "from:@alice" alone, and the authenticating from: after it carries the clientConfig
