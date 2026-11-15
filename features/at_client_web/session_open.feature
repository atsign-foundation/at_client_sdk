Feature: A browser opens an atSign session only where it safely can

  AtClient.create, onboard and enroll open a session on an atSign's passkey.
  They check the page and the options before the Dart bundle is loaded or any
  passkey prompt is shown, and reject with an AtError whose code says why.
  onboard on a browser without passkey PRF refuses before it touches the
  passkey, the CRAM secret or the atServer.

  Races: none arise; each call opens its own session, and a second tab's
  first-setup is serialised by the setup lock (setup_lock_timeout).
  Replay: none arise; a new passkey is created with a fresh random challenge.
  DoS: a bad call is refused locally, before the bundle loads or any network
  request.
  Forgery: none arise; no value from the caller is trusted without a passkey.
  Impersonation: a passkey is bound to one rpId, so another hostname cannot
  use it; the CRAM secret is passed on and never stored by the package.

  Scenario: create defaults app to namespace, rpId to the hostname and rpName to app
    Given a secure page at app.example.com
    When create is called with only atSign and namespace
    Then the bridge is asked to open the session with app and rpName set to the namespace and rpId set to app.example.com

  Scenario: a missing namespace rejects bad_key before loading the bridge
    Given a secure page
    When create is called without a namespace
    Then it rejects with AtError code bad_key
    And the Dart bundle has not been loaded

  Scenario: a foreign rootDomain rejects unsupported
    Given a secure page
    When create is called with a rootDomain other than root.atsign.org
    Then it rejects with AtError code unsupported
    And the bridge has not been asked to open a session

  Scenario: a non-secure context rejects unsupported
    Given a page that is not a secure context
    When create is called
    Then it rejects with AtError code unsupported
    And the Dart bundle has not been loaded

  Scenario: onboard without PRF refuses before any passkey prompt, CRAM or setup write
    Given a browser whose client capabilities say it has no PRF extension
    When onboard is called with a CRAM secret
    Then it rejects with PrfUnavailableException, which the bridge reports as prf_unavailable
    And no passkey was created or asserted
    And the CRAM secret was not used to activate the atSign
    And nothing was written to the atServer
