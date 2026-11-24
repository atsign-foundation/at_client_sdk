Feature: Builds of one principal started together leave one live client

  A process holds at most one live client per (Atsign, enrollment). A build
  claims its Atsign and enrollment once it has read its keys, before it
  opens its data store or a connection. A build that reaches its claim while
  a client for the same principal is live, or another build holds the claim,
  is refused at once rather than built beside it. A build that reads a retrofitted enrollment before the
  retrofitting build has claimed it builds beside that one, and whichever
  of the two files second is refused as it files.

  Races: two builds of one principal at once are the case this covers; the
  claim is taken in the same step as the live-client check. Replay: a build
  refused at the claim sends nothing. A build refused as it files has
  already run its startup, which for a retrofitting build includes its
  enrollment request; a second retrofitting build of the same principal is
  refused at the claim and sends none. DoS: a claim is given up however
  its build ends, so a failed build never blocks the next. Forgery and
  impersonation: the builds that race are the app's own, and it already
  holds the keys and both data stores.

  Scenario: Two builds of one principal at once, each on its own data store, leave one live client
    Given no live client for @alice
    When an app starts two buildAtClient calls for @alice as the primary enrollment at once, each on its own data store
    Then one returns a client filed as @alice's, and the other throws StateError before it opens its data store or a connection

  Scenario: A build that fails gives up its claim
    Given a buildAtClient call for @alice that threw while building
    When the app calls buildAtClient for @alice again
    Then it builds a live client

  Scenario: A build never hands back a client another build made
    Given a buildAtClient call for @alice that files its client while a second call for @alice, given the same data store, is still reading its keys
    When the second call goes on to build
    Then it throws StateError, and the first client keeps the services it was built with

  Scenario: A build that retrofits to a new enrollment still holds off a second build
    Given a buildAtClient call for @alice whose retrofit has moved it to a new enrollment id, and which has not yet filed
    When a second buildAtClient call for @alice reads keys naming the new id
    Then the second call throws StateError

  Scenario: A build that reads a retrofitted enrollment before its retrofit has claimed it is refused as it files
    Given a buildAtClient call for @alice that has filed enrollment E2 in the keys and not yet claimed E2
    When a second buildAtClient call for @alice reads those keys and builds as E2, and both calls finish
    Then one returns a client filed as E2 and the other throws StateError, and the filed client keeps running
