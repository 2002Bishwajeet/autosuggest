# Accessibility Compatibility Matrix

Date: 2026-02-18
Scope: AutoSuggest MVP manual verification matrix for VoiceOver and Switch Control.

## Test Matrix

| Feature | Target App | VoiceOver | Switch Control | Expected Result | Status |
|---|---|---|---|---|---|
| Suggestion announcement on render | Notes | Yes | N/A | Suggestion is announced once and does not spam | Pending manual run |
| Suggestion announcement on render | Safari text area | Yes | N/A | Suggestion is announced and remains readable | Pending manual run |
| Accept suggestion (`Tab`) | Notes | Yes | Yes | Text inserts, focus remains in field | Pending manual run |
| Accept suggestion (`Enter`) | Messages | Yes | Yes | Text inserts without losing accessibility focus | Pending manual run |
| Dismiss suggestion (`Esc`) | Notes | Yes | Yes | Overlay hides and no text mutation | Pending manual run |
| Secure field suppression | Safari login field | Yes | Yes | No suggestion shown, no announcement | Pending manual run |
| URL bar suppression | Safari address bar | Yes | Yes | No suggestion shown, no announcement | Pending manual run |
| IME guard | Any IME-enabled field | Yes | Yes | Suggestions suppressed during IME active state | Pending manual run |
| Low power pause mode | Notes | Yes | Yes | No suggestion when low power mode + pause setting enabled | Pending manual run |
| Exclusion rule by app | Excluded app | Yes | Yes | No overlay or suggestion in excluded app | Pending manual run |

## Execution Notes

- Run with system permissions enabled:
  - Accessibility
  - Input Monitoring
- Use the menu bar controls to enable/disable and to apply exclusions.
- Capture issues with:
  - app name
  - field type
  - expected vs actual behavior
  - whether VoiceOver/Switch Control focus changed unexpectedly

## Sign-off

- MVP accessibility baseline is considered validated when all rows above are manually tested and marked pass/fail with notes.
