// - atSign acquisition, onboarding, enrollment and enrollment management
// - generic app behaviour
//   - require to be online (always use remote atServer)
//   - works when offline (use local atServer) without violating principe of least surprise
//     - this requires a sync overhaul; sync needs to be immediate, not batched / asynchronous
//   - for CLIs in particular
//     - use the canonical at_commons / at_utils functions to create storage paths
//     - singleton persistent storage (only one instance of this program can be running as this user on this device)
//     - multiple persistent storage (many instances but they need to retain data across runs)
//     - multiple ephemeral storage (many instances, which delete their storage upon completion)
