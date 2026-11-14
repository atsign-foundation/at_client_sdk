Feature: A request option left unset follows the client's routing preference

  An app routes a whole client with AtClientPreference.remoteLocalPref and one
  operation with useRemoteAtServer on its request options. An option the app
  never set follows the preference; one it set, true or false, is enforced.
  Reading an option that was never set still gives false, so code that reads
  it is unchanged.

  Races: none arise; routing is decided once per call from values the caller
  holds.
  Replay: none arise; an operation sends no more than the preference asks for.
  DoS: none arise; an operation makes the same one request as before.
  Forgery and impersonation: none arise; authentication and the keys used are
  unchanged.

  Scenario Outline: Under remoteOnly, a write whose options leave useRemoteAtServer unset reaches the atServer before it returns
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls <operation> with <options> that set only <other field>
    Then the <command> reaches the atServer before <operation> returns
    Examples:
      | operation | options              | other field   | command |
      | put       | PutRequestOptions    | shouldEncrypt | update  |
      | delete    | DeleteRequestOptions | noCommit      | delete  |

  Scenario: Under remoteOnly, a get whose options leave useRemoteAtServer unset reads from the atServer
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls get with GetRequestOptions that leave useRemoteAtServer unset
    Then the lookup reaches the atServer

  Scenario: An explicit useRemoteAtServer false still routes local under remoteOnly
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls put with PutRequestOptions whose useRemoteAtServer is false
    Then the value is written to local storage and nothing is sent to the atServer before put returns

  Scenario: Under the default preference, options that leave useRemoteAtServer unset route local as before
    Given a client with the default remoteLocalPref
    When the app calls put with PutRequestOptions that set only shouldEncrypt
    Then the value is written to local storage and nothing is sent to the atServer before put returns

  Scenario: Reading useRemoteAtServer on options that never set it gives false
    Given PutRequestOptions, GetRequestOptions and DeleteRequestOptions on which useRemoteAtServer was never set
    When the app reads useRemoteAtServer on each
    Then each reads false

  Scenario: Under remoteOnly, a putMeta whose options leave useRemoteAtServer unset reaches the atServer before it returns
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls putMeta with PutRequestOptions that leave useRemoteAtServer unset
    Then the metadata update reaches the atServer before putMeta returns

  Scenario: Under remoteOnly, a delete or putMeta of a local: key stays on the device
    Given a client whose remoteLocalPref is remoteOnly, and a local: key
    When the app calls delete, and then putMeta, on that key with options that leave useRemoteAtServer unset
    Then each runs on local storage and nothing is sent to the atServer

  Scenario: Under remoteOnly, an encrypted put whose options leave useRemoteAtServer unset prepares and writes on the atServer
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls put with PutRequestOptions that leave useRemoteAtServer unset and keep shouldEncrypt true
    Then the put's preparation and its update both go to the atServer before put returns

  Scenario: An explicit useRemoteAtServer false on a get still reads local under remoteOnly
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls get with GetRequestOptions whose useRemoteAtServer is false
    Then the value is read from local storage and nothing is sent to the atServer

  Scenario: Under remoteOnly, a noCommit put whose options leave useRemoteAtServer unset reaches the atServer
    Given a client whose remoteLocalPref is remoteOnly
    When the app calls put with PutRequestOptions that set noCommit and leave useRemoteAtServer unset
    Then the update reaches the atServer with noCommit before put returns

  Scenario: A legacy fallback keeps an unset useRemoteAtServer unset
    Given PutRequestOptions on which useRemoteAtServer was never set
    When a put falls back to legacy encryption and copies those options
    Then useRemoteAtServer is still unset on the copy
