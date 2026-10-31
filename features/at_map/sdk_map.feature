Feature: The SDK map draws share-record from a curated model, checked against the code

  `dart run at_map build` reads the model in docs/map/model, this
  checkout of at_client_sdk, and at_server at the trunk SHA the model pins.
  It writes the generated flow files in docs/map/data/flows. `build --indexes`
  writes docs/map/data/indexes.js. Nothing else writes that file.
  `dart run at_map check` runs as the map job on every pull request and
  every push to trunk. A reader opens docs/map/index.html from disk, with no
  server and no network.

  The first slice is one flow, share-record. @alice's client puts
  @bob:note.ns@alice, sync pushes it in a batch: command, and @alice's atServer
  stores it and auto-notifies. That atServer proves itself to @bob's atServer
  by from: and pol, then sends notify:. @bob's atServer accepts the
  notification and pushes it to @bob's monitor connection, and @bob's client
  receives it. The model gives the step order, a one-line intent for each step,
  and the claims. The generator extracts everything else: snippets, skeletons,
  call edges, verb dispatch, and the exits of each server handler on the
  flow's path.

  Races: two pull requests that each pass could fail together. Trunk's
  protection already requires a branch to be up to date before it merges, so
  making the map job a required check prevents that; until then, its run on
  every push to trunk only detects it. A build
  writes to a temporary directory and renames it, so an interrupted build
  leaves the old files whole. The production tag is pinned by name and SHA.
  A tag published later changes no build, and a tag moved to another commit
  fails the job.
  Replay: each generated flow file records the inputs it was built from: the
  model hash, the at_server SHA and the production tag's SHA. The gate refuses
  a file that a fresh build would not reproduce byte for byte, so an old map
  cannot pass as the current one. The page's lane note shows both pins.
  A retired step id is never reused.
  DoS: a contains anchor is a token sequence, never a regular expression. Each
  generated file has a size budget, and every parsed file has a size cap. A
  path condition longer than its bound is reported as not expanded. YAML
  aliases are capped.
  Forgery: a claim that an atServer refuses or authorizes something must be
  backed from the claimed lane's own repository, by an exit on the step's own
  branch path or by a Gherkin clause whose text still matches. A check on a
  client lane carries no "enforced by" label. Fixture controls test the
  extractor.
  Text from code, docs or the model is only ever rendered as text, and links
  come from an allowlist.
  Impersonation: lanes are roles held by @alice and @bob, never real atSigns.
  The generator connects to no atServer and reads no keys, and nothing from a
  live atSign is committed.

  Scenario: A build writes share-record's files
    Given the model, this checkout, and at_server checked out at the pinned trunk SHA
    When at_map build runs
    Then docs/map/data/flows/share-record.js and docs/map/data/flows/share-record.md are written, each recording the model hash, the at_server SHA and the production tag's SHA

  Scenario: A rebuild is byte-identical
    Given a build of share-record
    When at_map build runs again on the same inputs
    Then every file in docs/map/data/flows is byte-identical to the first build

  @race
  Scenario: A new production tag changes no build
    Given the model pins production tag p3.19.0 and its SHA
    When at_server publishes a later p tag and at_map build runs
    Then the generated files are unchanged

  @race
  Scenario: A production tag moved to another commit fails the map job
    Given the model pins production tag p3.19.0 and its SHA
    When the tag p3.19.0 resolves to a different SHA and the map job runs
    Then it fails, naming the tag, the pinned SHA and the SHA it now resolves to

  Scenario: A renamed anchored method fails the map job
    Given a pull request that renames NotificationServiceImpl.handleNotificationReceipt
    When the map job runs at_map check
    Then it fails, naming share-record.bob-deliver, the anchor, and the renamed method as a candidate

  Scenario: An anchored statement edited in place fails the map job
    Given a pull request that changes "await q.enqueue(atKey, op);" in LocalSecondary._enqueueForSync
    When the map job runs at_map check
    Then it fails, naming share-record.alice-enqueue and the statement it no longer finds exactly once

  Scenario: A reformatted anchored statement still resolves
    Given a pull request that only rewraps "await q.enqueue(atKey, op);" in LocalSecondary._enqueueForSync
    When the map job runs at_map check
    Then the anchor of share-record.alice-enqueue resolves, compared as tokens

  Scenario: A broken call edge fails the map job
    Given a pull request in which AtClientImpl._putInternal reaches executeUpdateOrDelete only through a new method, with every anchor still resolving
    When the map job runs at_map check
    Then it fails, naming the edge from share-record.alice-put to share-record.alice-route and the call it no longer finds

  Scenario: A transition that is neither an edge nor a hop fails the map job
    Given a step whose predecessor's symbol does not call its symbol, with no via, hop, wire or push declared and no binder that binds the two
    When the map job runs at_map check
    Then it fails, naming both steps

  Scenario: A transition a binder binds needs no declaration
    Given share-record.bob-deliver declares nothing about how share-record.bob-receive reaches it
    When at_map build runs
    Then the transition resolves as a function-field hop, because Monitor is constructed with handleNotification: handleNotificationReceipt

  Scenario: A hop with an unresolved end fails the map job
    Given share-record.alice-server-send is reached by a stream hop through PerAtSignNotifSender.notifs
    When the pinned at_server SHA moves to one where that field is renamed, and the map job runs
    Then it fails, naming the hop and the end it cannot resolve

  Scenario: A sample dispatching elsewhere fails the map job
    Given share-record.bob-server-accept is reached by a notify: sample
    When its sample is changed to a notify:list command and the map job runs
    Then it fails, naming the step, NotifyListVerbHandler as the handler dispatch chose, and the at_commons version that chose it

  Scenario: A sample one at_commons version rejects fails the map job
    Given a wire sample that the client's at_commons VerbSyntax accepts and the at_commons version in at_server's lock rejects
    When the map job runs at_map check
    Then it fails, naming the step, the sample and the at_commons version that rejects it

  @replay
  Scenario: A stale flow file fails the map job
    Given a pull request that changes the body of an anchored method without running at_map build
    When the map job runs at_map check
    Then it fails, naming docs/map/data/flows/share-record.js as not what a build produces

  @replay
  Scenario: A retired step id cannot be reused
    Given the model lists share-record.old-step as retired
    When a step with that id is added and the map job runs
    Then it fails, naming the id

  @forgery
  Scenario: An unbacked refusal claim fails the map job
    Given a step on a server lane claiming a refusal that matches no extracted exit and cites no Gherkin clause
    When the map job runs at_map check
    Then it fails, naming the step and the claim

  @forgery
  Scenario: A server claim backed only from at_client_sdk fails the map job
    Given share-record.bob-server-accept claims a refusal backed only by a feature under at_client_sdk's features/
    When the map job runs at_map check
    Then it fails, naming the claim and saying its backing is not from at_server

  @forgery
  Scenario: A claim backed by an exit on another branch fails the map job
    Given share-record.bob-server-accept claims a refusal backed by the exit "reserved != null" in NotifyVerbHandler._handleAuthenticatedConnection
    When the map job runs at_map check
    Then it fails, naming the claim and the branch the exit is on

  @forgery
  Scenario: A Gherkin backing whose clause changed fails the map job
    Given a postcondition backed by the clause "Then it gets data:success" of a scenario in features/notify/peer_reserved_namespace.feature
    When that clause's text changes and the map job runs
    Then it fails, naming the postcondition and the clause it no longer finds

  @forgery
  Scenario: A client-lane check carries no enforced-by label
    Given a step on alice.client that refuses a write, backed by a client-side check
    When the reader selects the step
    Then the check is labelled "client-side, best effort" and carries no "enforced by" label

  Scenario: A changed client body is reported as changed since review
    Given a pull request, rebuilt, that adds an early return to LocalSecondary._enqueueForSync
    When the map job runs at_map check
    Then it passes and reports share-record.alice-enqueue as changed since reviewed

  Scenario: A client step changed since review is drawn amber
    Given a generated flow file in which share-record.alice-enqueue is changed since reviewed
    When the reader opens share-record
    Then that step is drawn amber

  Scenario: Blessing a step clears its amber
    Given share-record.alice-enqueue is changed since reviewed
    When at_map bless share-record.alice-enqueue runs and at_map build runs
    Then the step is no longer amber

  Scenario: A server step changed since review fails the map job
    Given a pull request that moves the at_server trunk pin to a SHA where NotifyVerbHandler._handlePolAuthenticatedConnection's body differs from its reviewed hash
    When the map job runs at_map check without the step blessed
    Then it fails, naming share-record.bob-server-accept and asking for at_map bless after its author has read the step

  Scenario: The job counts unverified contract text
    Given a postcondition that cites no Gherkin clause and no extracted exit, and is not an authorization or refusal claim
    When the map job runs at_map check
    Then it passes and reports one unverified contract line

  Scenario: The page marks unverified contract text
    Given a generated flow file with an unverified postcondition
    When the reader selects its step
    Then the postcondition is marked "unverified"

  Scenario: An exit a test's string literal holds is named by that test
    Given the exit "sharedBy != fromAtSign", whose message is "$sharedBy is not authorized to send notification as $fromAtSign"
    When at_map build --indexes runs
    Then the exit shows "named by (text match)" and the at_server tests whose string literals hold that message's fixed text

  Scenario: An exit no test names says so
    Given the exit in PolVerbHandler.processVerb raising AtException('Unable to verify signature')
    When at_map build --indexes runs
    Then the exit shows "no test names this"

  Scenario: The job reports test evidence against the recorded figure
    Given docs/map/model/ratchet.yaml records the number of exits on share-record's path named by a test
    When the map job runs at_map check and fewer exits are named
    Then it passes and reports the figure, the recorded figure and the exits no longer named

  Scenario: An index-only change passes the map job
    Given a pull request that only adds a "/// Catalogue:" line to a test
    When the map job runs at_map check
    Then it passes without that pull request changing docs/map/data

  Scenario: The pol path includes the checks before the branch
    Given NotifyVerbHandler at the pinned trunk SHA
    When at_map build extracts the exits on share-record.bob-server-accept's path
    Then they include, before the branch, the guards "verbParams[AtConstants.strategy] == 'latest' && verbParams[AtConstants.notifier] == null", "verbParams[AtConstants.notificationExpiresAt] != null && verbParams[AtConstants.ttlNotification] != null", "!atConnectionMetadata.isAuthenticated && !atConnectionMetadata.isPolAuthenticated" and "(verbParams[AtConstants.id]?.length ?? 0) > maxIdLength"

  Scenario: The pol path includes its refusals and drops
    Given NotifyVerbHandler at the pinned trunk SHA
    When at_map build extracts the exits on share-record.bob-server-accept's path
    Then they include, on the branch "!atConnectionMetadata.isAuthenticated", the guards "_isText(verbParams)", "sharedWith != currentAtSign", "sharedBy != fromAtSign", "!isWellFormedAtKey(atKey)", "reserved != null", "n.isExpired()" and "await notifMgr.isKeyExists(n.id!)"

  Scenario: A helper in another file is followed
    Given _handlePolAuthenticatedConnection calls refuseOverlongNotificationKey, declared in notification_key_length.dart
    When at_map build extracts the exits on share-record.bob-server-accept's path
    Then they include that helper's exit "length > maxNotificationKeyLength", raising InvalidAtKeyException, under the guard "caches"

  Scenario: The pol path shows no exit of the client branch
    Given NotifyVerbHandler at the pinned trunk SHA
    When at_map build extracts the exits on share-record.bob-server-accept's path
    Then they hold no exit of _handleAuthenticatedConnection

  Scenario: An else-branch exit carries the negated condition
    Given the extractor's fixture of a throw in the else of "if (digestFromClient == expectedDigest)"
    When the extractor's fixture tests run
    Then the exit's guard is "!(digestFromClient == expectedDigest)"

  Scenario: A throw caught inside the handler is not an exit
    Given the extractor's fixture of a throw inside a try whose catch returns normally
    When the extractor's fixture tests run
    Then that throw is not listed as an exit

  Scenario: A construct the walker does not know marks the inventory incomplete
    Given the extractor's fixture of a handler whose body uses a statement the walker does not handle
    When the extractor's fixture tests run
    Then the handler's inventory is marked incomplete, naming the construct

  @dos
  Scenario: A path condition over its bound is reported, not expanded
    Given the extractor's fixture of a guard whose path condition exceeds the bound
    When the extractor's fixture tests run
    Then the exit is listed with its guard and marked "path not expanded"

  @dos
  Scenario: YAML aliases over the cap fail the build
    Given a model file whose aliases expand past the cap
    When at_map build runs
    Then it fails, naming the file

  Scenario: The server lane carries one note about production
    Given the model pins at_server trunk at d654f25bd and production tag p3.19.0
    When the reader opens share-record
    Then the server lanes carry the note "Server lane at at_server trunk d654f25bd; production p3.19.0 is 160 commits behind."

  @forgery
  Scenario: Nothing public names a step as differing from production
    Given NotificationManager._pushToMonitors exists at the pinned trunk SHA and not at p3.19.0
    When at_map build and the map job run
    Then no file in docs/map/data and no line of the job's log names any step as missing or different at p3.19.0

  Scenario: diff-prod lists the differing steps locally
    Given a local checkout with at_server available at both pins
    When at_map diff-prod runs outside CI
    Then it prints share-record.bob-server-push as absent at p3.19.0

  @forgery
  Scenario: diff-prod refuses to run in CI
    Given the environment variable CI is set
    When at_map diff-prod runs
    Then it exits non-zero without printing any step

  Scenario: The map opens from disk in Chrome
    Given a clone of at_client_sdk at a trunk commit whose map job passed
    When a reader opens docs/map/index.html from disk in Chrome
    Then share-record is drawn in four lanes, alice.client, alice.server, bob.server and bob.client

  Scenario: The page requests nothing from the network
    Given a clone of at_client_sdk at a trunk commit whose map job passed
    When a reader opens docs/map/index.html from disk in Chrome and opens every step of share-record
    Then the page makes no network request

  Scenario: Selecting a step shows what it does and where
    Given share-record open on the page
    When the reader selects share-record.bob-server-accept
    Then the panel shows its intent, its skeleton, its exits with their guards, its snippet, and a permalink to at_server at the pinned SHA

  Scenario: A deep link opens the step it names
    Given the page opened from disk as index.html#flow=share-record&step=bob-server-accept
    When it loads
    Then share-record.bob-server-accept is selected

  @forgery
  Scenario: Embedded text cannot become markup
    Given a snippet, a scenario title or an intent containing "</pre><img src=x onerror=alert(1)>"
    When the page renders it
    Then the text appears literally and no element is created from it

  @forgery
  Scenario: A link outside the allowlist fails the build
    Given a model link that is neither a path in this repository nor under https://github.com/atsign-foundation/
    When at_map build runs
    Then it fails, naming the link and the step that holds it

  @dos
  Scenario: A file over its size budget fails the build
    Given a model change that would make docs/map/data/flows/share-record.js larger than its budget
    When at_map build runs
    Then it fails, naming the file, its size and the budget

  Scenario: The weekly drift job logs counts, not steps
    Given at_server trunk has moved past the pinned SHA
    When the weekly drift job runs at_map check against at_server trunk
    Then its log gives the number of steps whose anchors, edges, samples or exits would change, and names no step

  Scenario: The drift job moves no pin
    Given at_server trunk has moved past the pinned SHA and a later p tag exists
    When the weekly drift job runs
    Then docs/map/model/roots.yaml is unchanged and the job makes no commit

  Scenario: check --server lists the drifting steps locally
    Given a local checkout of at_server at its trunk
    When at_map check --server runs against that checkout outside CI
    Then it lists each step whose anchors, edges, samples or exits would change
