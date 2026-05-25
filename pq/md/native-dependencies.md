# PQ Migration — Native Dependency Options

**Status: Draft.** Library candidates and the working preference (mlkem-native) are proposals, not decisions.

Comparison of native libraries that can supply ML-KEM-768 for the Track 1 hybrid KEM. X25519, HKDF-SHA256, and AES-256-GCM are deliberately **not** in this table — they're handled by `pointycastle` and `dart:typed_data` / `cryptography` already in the repo.

Related drafts: [`component-architecture.md`](component-architecture.md), [`algorithms-and-protocols.md`](algorithms-and-protocols.md), [`crypto-fundamentals.md`](crypto-fundamentals.md), [`pqxdh-spqr-deep-dive.md`](pqxdh-spqr-deep-dive.md).

## Candidate matrix

| Library | Scope | License | Recommended for at_chops_pq_native? | Notes |
|---|---|---|---|---|
| **mlkem-native** ([pq-code-package/mlkem-native](https://github.com/pq-code-package/mlkem-native)) | ML-KEM only | MIT | **Yes (preferred)** | Focused, portions formally verified, ~50 KB built; designed as a leaner alt to liboqs |
| **PQClean** ([PQClean/PQClean](https://github.com/PQClean/PQClean)) | Reference PQ impls (source-only) | CC0 / public domain per scheme | **Yes (alt)** | Vendor `.c` files directly; no build system; canonical "clean" reference upstream of liboqs |
| **liboqs** ([open-quantum-safe/liboqs](https://github.com/open-quantum-safe/liboqs)) | All NIST PQ candidates | MIT | Workable but heavy | Original Track 1 pick. Carries algos we don't use; needs CMake gating |
| **AWS-LC** ([aws/aws-lc](https://github.com/aws/aws-lc)) | Full crypto lib | ISC / OpenSSL | No — overkill | ML-KEM since 2024; battle-tested at AWS scale; pulling it for one algo is excessive |
| **BoringSSL** | Full crypto lib | OpenSSL-style | No | Same impl Chrome ships; **no stable ABI — Google explicitly discourages vendoring** |
| **OpenSSL ≥ 3.5** | Full crypto lib | Apache 2.0 | No | Native ML-KEM since Apr 2025; bumps minimum OpenSSL version on every platform |
| **wolfSSL** | Embedded crypto | GPLv2 / commercial | No | Commercial license required unless project is GPL-compatible |
| **Pure Dart re-implementation** | — | — | **No** | ML-KEM has NTT + Keccak + CBD sampling; ~10–50× slower in Dart VM; constant-time risk is real |
| **pointycastle** (existing Dart dep) | Classical crypto | MIT | N/A | Does **not** implement ML-KEM today; we keep it for X25519 only |

## Why mlkem-native over liboqs

| Axis | liboqs | mlkem-native |
|---|---|---|
| Algorithms shipped | ~30 KEMs + signatures | ML-KEM (512/768/1024) only |
| Built static lib size | ~1 MB+ per platform | ~50 KB |
| Build system | CMake with many feature flags | CMake (simpler) or single-file integration |
| Audit surface | Large | Small, partially formally verified |
| Maintainership | Open Quantum Safe (Amazon-backed) | PQ Code Package (Amazon + Quarkslab) |
| Maturity | Older, more battle-tested | Newer; widely adopted in 2024–2025 |

For Track 1 we only encapsulate/decapsulate one suite. Carrying liboqs means linking 30× the code, then disabling everything except ML-KEM-768 via CMake flags — and still shipping a fat binary. mlkem-native is purpose-built for this case.

## Fallback rationale

If mlkem-native bindings prove unstable across platforms, fall back to **PQClean source vendoring** (drop the C files directly into `at_chops_pq_native/third_party/pqclean/ml_kem_768/clean/`, compile per platform). PQClean is the upstream reference both mlkem-native and liboqs derive from — so semantics are byte-identical.

liboqs remains a viable last-resort if both above hit a wall, at the cost of binary size.

## Open questions (none of these are resolved)

1. **Native dep** — current working preference is mlkem-native. PQClean (source vendoring) and liboqs remain on the table. Needs a per-platform build proof before locking.
2. **Vendoring policy** — git submodule pinned to release tag vs tarball in `third_party/`. Tied to `../pq-migration.md` §10 Q5.
3. **Classical-crypto source for X25519** — proposed to keep pointycastle to avoid a second native dep. Not yet validated.
4. **Pure-Dart ML-KEM** — argued against earlier in this doc; remains a working position, not a final ruling.

## Build artifact targets (unchanged from `pq-migration.md` §4.3)

| Platform | Artifact |
|---|---|
| iOS | static `.a` via CocoaPods |
| Android | `.so` per ABI via Gradle/CMake |
| macOS | static `.a` via CocoaPods |
| Linux | `.so` |
| Windows | `.dll` |
| **Web** | unsupported in Track 1 — Track 4 (WASM build) |
