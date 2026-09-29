# Probes behind the key-sources design

Each script prints raw measurements, and [`design.md`](../design.md#3-measurements)
records what they showed on 2026-09-28 and 2026-09-29. Run them from this
directory. None of them leaves anything behind.

| Probe                                  | Where it runs                                                                                                     | Invocation                                                                                           |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `macos_keychain/run.sh`                | macOS, against your login keychain; creates and deletes items named `atsign-kc-probe-*`                           | `macos_keychain/run.sh`                                                                              |
| `linux_secret_service.sh`              | a throwaway Debian container                                                                                      | `docker run --rm -v "$PWD/linux_secret_service.sh:/probe.sh:ro" debian:bookworm-slim bash /probe.sh` |
| `systemd_creds_swtpm.sh`               | a throwaway Debian container with a software TPM                                                                  | `docker run --rm -v "$PWD/systemd_creds_swtpm.sh:/probe.sh:ro" debian:trixie bash /probe.sh`         |
| `systemd_load_credential.sh`           | a Linux host with systemd and passwordless `sudo`; measured on systemd 249                                        | `ssh <host> 'bash -s' < systemd_load_credential.sh`                                                  |
| `systemd_load_credential_encrypted.sh` | a Linux host with systemd and passwordless `sudo`; measured on systemd 255, and systemd 249 lacks `systemd-creds` | `ssh <host> 'bash -s' < systemd_load_credential_encrypted.sh`                                        |

The two systemd service probes can't run in a container under Docker Desktop
on macOS, because no credential reaches a service there. They need a VM or a
real host.
