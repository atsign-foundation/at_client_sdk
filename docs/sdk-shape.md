# The Atsign Dart SDK shape

## In one sentence

An app depends on its one **platform package**, imports only that (plus any
feature packages it uses), and gets the whole client API with a working default
for everything that differs by platform, any of which it can override.
Underneath, a platform-neutral **core** takes each of those things explicitly,
and the **foundation** libraries beneath it never assume a platform at all.

## The layers

| Layer          | Packages                                                    | What it is                                                                                                                       |
|----------------|-------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| **Platform**   | **at_client_cli**, **at_client_flutter**, **at_client_web** | What an app imports. Each supplies the platform defaults and re-exports the core API.                                            |
| **Feature**    | at_contact, at_policy, at_telemetry, and future ones        | Optional add-ons an app may import beside its platform package.                                                                  |
| **Core**       | at_client                                                   | Platform-neutral client. Public, for building platform packages and for advanced programs that pass every dependency explicitly. |
| **Foundation** | at_commons, at_utils, at_chops, at_lookup, at_auth          | The protocol, cryptography, transport and authentication building blocks.                                                        |

**The platform packages:**

- **at_client_cli** covers every native Dart program that isn't Flutter:
  command-line tools, daemons, servers and Dart on IoT. It carries `CLIBase`,
  `CliKeys` and the `at_activate` and `at_register` executables. It replaces
  at_onboarding_cli and at_cli_commons, whose last majors (2.0.0 and 4.0.0)
  are deprecated re-exports of it.
- **at_client_flutter** covers Flutter apps on mobile, desktop and embedded
  devices.
- **at_client_web** covers browser apps. It doesn't exist yet; the browser
  work under way as at_client_wasm takes this name when it's rebuilt.

## The rules

1. **One import.** An app's code imports its platform package's barrel and
   nothing else from the SDK, except feature packages.
2. **Complete re-export.** The platform package re-exports the core API and its
   own platform pieces. Nothing an app needs takes a second SDK import.
3. **A default for everything that differs by platform:**

   | | at_client_cli | at_client_flutter | at_client_web (to come) |
   |---|---|---|---|
   | Storage | Hive under `~/.atsign/storage/` | Hive in the app support directory | memory (a durable browser store later) |
   | Transport and atDirectory | TLS socket; cached TCP atDirectory finder | TLS socket; cached TCP atDirectory finder | `wss`; HTTPS atDirectory finder |
   | Keys | the `.atKeys` file | the OS keychain | a browser key store |
   | Logging | stderr, or a file | the console | the browser console |
   | Onboarding and enrollment | `at_activate`, `CLIBase`, `CliKeys` | dialogs and widgets | to come |

4. **Every default can be overridden** by passing the same core type explicitly.
5. **Core has no hidden defaults.** What it needs is a required parameter, so a
   missing one fails at compile time, not at runtime.
6. **Feature packages are platform-neutral.** They depend only on core and the
   foundation, never on a platform package. They pass the same wasm gate as core,
   and those that build on core move majors with it.
7. **Neutrality is enforced, not promised.** Platform-specific code lives only
   in named `*_io.dart` and `*_web.dart` libraries, which the platform packages
   pick. The wasm gates in
   [`.github/wasm_gates.yaml`](../.github/wasm_gates.yaml) walk each default
   library of at_chops, at_auth, at_utils, at_lookup, at_client, at_contact,
   at_policy and at_telemetry, hold it at zero packages reaching a platform
   library, and compile it with dart2wasm. at_commons imports no platform
   library at all, and the walks above it count any it reached.
8. **The architecture is the same everywhere:** local-first, with a local
   `AtClientStorage` on every platform. It's durable on CLI and Flutter, and
   memory-only on the web for now.
9. **Core is public, but not the app path.** READMEs, the upgrade guide and the
   examples always point an app at its platform package. A direct `at_client`
   import is for platform builders and for programs that supply every dependency
   themselves.
10. **Upgrading is a platform-package bump.** A core major brings a major of
    each platform package. An app moves by changing its platform package's
    constraint, plus any feature packages', following
    [the upgrade guide](upgrade-to-4.md).
