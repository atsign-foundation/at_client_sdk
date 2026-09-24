# OQ-P1 results

Status: open — 3 rows in (Chrome + Safari macOS, Brave Android: `prf` ✓); fill one row per browser × authenticator.

| UA | secure | caps `extension:prf` | create `prf.enabled` | create `results.first` bytes | get `results.first` bytes | `largeBlob.supported` | unlocked after reload | error | authenticator (fill by hand) |
|---|---|---|---|---|---|---|---|---|---|
| Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36 | true | true | true | 32 | 32 | false | true |  | macOS platform — provider TBD |
| Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Safari/605.1.15 | true | true | true | 32 | 32 | null | true |  | iCloud Keychain (Safari platform) |
| Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Mobile Safari/537.36 | true | true | true | 32 | 32 | null | true |  | Brave (Chromium 153) Android — provider TBD |

## Targets

- Chrome (desktop) — platform authenticator, security key, phone hybrid
- Safari 18+ macOS — iCloud Keychain
- Safari iOS 18+ — iCloud Keychain
- Firefox (desktop) — platform, security key
- Edge (desktop) — Windows Hello
- Chrome Android — Google Password Manager

## Decision

_Pending the table._
