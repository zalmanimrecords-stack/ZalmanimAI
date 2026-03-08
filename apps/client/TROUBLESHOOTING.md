# Flutter Client Troubleshooting

## Windows console errors (harmless)

When running the app on Windows (`flutter run -d windows`), you may see these in the console. They come from the **Flutter engine**, not from this app, and the app usually keeps working.

### AXTree / accessibility_bridge

```
[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(65)] Failed to update ui::AXTree, error: 27 will not be in the tree and is not the new root
```

- **Cause:** Known Flutter Windows accessibility bug; the engine’s accessibility tree can get out of sync (e.g. with dialogs, tabs, or when Windows Magnifier is on).
- **Impact:** Cosmetic; the app continues to run. Screen readers might occasionally get stale info.
- **What to do:**
  - Upgrade Flutter (`flutter upgrade`); newer versions include engine fixes (e.g. [flutter/flutter#98778](https://github.com/flutter/flutter/issues/98778), [flutter/engine#39441](https://github.com/flutter/engine/pull/39441)).
  - If you don’t need accessibility on Windows, you can ignore the message.

### Key event / Alt key

```
Attempted to send a key down event when no keys are in keysPressed. This state can occur if the key event being sent doesn't properly set its modifier flags...
RawKeyDownEvent ... (Alt Left) ... modifiers: 0
```

- **Cause:** Flutter on Windows doesn’t always sync modifier key state for Alt (and sometimes AltGr); the framework gets a key event for a key it didn’t record as pressed.
- **Impact:** The message is noisy but the app keeps working. Alt shortcuts may occasionally misbehave.
- **What to do:** Upgrade Flutter; otherwise ignore. See [flutter/flutter#101275](https://github.com/flutter/flutter/issues/101275), [flutter/flutter#75768](https://github.com/flutter/flutter/issues/75768).

### Empty JSON / DevTools

```
Unable to parse JSON message: The document is empty.
```

- **Cause:** Usually DevTools or hot reload trying to parse an empty or truncated message.
- **Impact:** None for normal use.
- **What to do:** Ignore, or restart the app / DevTools if it bothers you.

---

**Summary:** These are Flutter/Windows engine issues. Updating Flutter is the main mitigation; otherwise you can safely ignore the messages unless you rely on accessibility or Alt shortcuts on Windows.
