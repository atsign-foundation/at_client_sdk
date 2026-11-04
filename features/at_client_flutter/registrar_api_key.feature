Feature: The at_client_flutter example takes its registrar API key from the build

  The example's source carries no registrar API key. An app developer
  creates one via the registrar at my.atsign.com and passes it with
  --dart-define=REGISTRAR_API_KEY=<key>.

  Races, replay: none arise.
  DoS: without a key nothing is sent to the registrar.
  Forgery and impersonation: none arise; the key names the app to the
  registrar and acts for no atSign.

  Scenario: Activating a new atSign with no registrar API key given says where to get one
    Given the example built without a REGISTRAR_API_KEY
    When the user starts activating a new atSign
    Then nothing is sent to the registrar, and the app says to create an API key via the registrar at my.atsign.com and pass it as REGISTRAR_API_KEY
