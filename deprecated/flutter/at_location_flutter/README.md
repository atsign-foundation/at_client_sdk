# at_location_flutter tombstone

`at_location_flutter` has been removed from this repository.

The old package bundled location-sharing state, map UI, dialogs, helper
widgets, and platform plugin scaffolding into a reusable Flutter package. The
replacement direction is app-owned code built directly on `at_client` and
`at_client_flutter`.

See the official example instead:

- `packages/at_client_flutter/examples/location_sharing`

That example demonstrates time-limited `AtCollection<LocationShare>` records,
stream-returning service methods for `StreamBuilder`, explicit start / publish /
stop commands, and realtime UI updates without package-owned map screens,
dialogs, or helper UI.

