# OQ-P1 results

Status: open — 4 rows in (Brave + Safari + Chrome macOS, Brave Android: `prf` ✓). Brave reports a Chrome UA. Fill one row per browser × authenticator.

| UA | secure | caps `extension:prf` | create `prf.enabled` | create `results.first` bytes | get `results.first` bytes | `largeBlob.supported` | unlocked after reload | error | authenticator (fill by hand) |
|---|---|---|---|---|---|---|---|---|---|
| Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36 | true | true | true | 32 | 32 | false | true |  | Brave (Chromium 152) macOS, Touch ID — provider unknown: not in macOS Passwords, so not iCloud Keychain |
| Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Safari/605.1.15 | true | true | true | 32 | 32 | null | true |  | iCloud Keychain (Safari platform) |
| Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Mobile Safari/537.36 | true | true | true | 32 | 32 | null | true |  | Brave (Chromium 153) Android — Google Password Manager |
| Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36 | true | true | true | 32 | 32 | true | true |  | Chrome 153 macOS — Google Password Manager, Touch ID as the local unlock |

## Targets

- Chrome (desktop) — platform authenticator, security key, phone hybrid
- Safari 18+ macOS — iCloud Keychain
- Safari iOS 18+ — iCloud Keychain
- Firefox (desktop) — platform, security key
- Edge (desktop) — Windows Hello
- Chrome Android — Google Password Manager

## Decision

_Pending the table._
