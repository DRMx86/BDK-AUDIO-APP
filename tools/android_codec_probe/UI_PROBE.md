# Finite BDK UI instrumentation

`UiProbe` is an independent instrumentation entry targeting
`com.bdkaudio.codecprobe`, so invoking it does not instrument or restart the
production controller process. Root builds/signs/installs the separate helper;
the source helper is not included in the production app.

Arguments:

| Argument | Values |
| --- | --- |
| `mode` | `dump` (default), `click`, `scrollForward`, `scrollBackward` |
| `target` | Required nonempty actual node label for `click` |
| `match` | `exact` (default), `prefix` |
| `field` | `either` (default), `description`, `text` |

Example after the root agent has built and installed the helper:

```text
am instrument -w -r -e mode dump com.bdkaudio.codecprobe/.UiProbe
am instrument -w -r -e mode click -e field description -e match exact -e target Light com.bdkaudio.codecprobe/.UiProbe
am instrument -w -r -e mode scrollForward com.bdkaudio.codecprobe/.UiProbe
```

Only a focused, active root belonging to `com.bdkaudio.controller` is accepted.
Null roots are polled for at most three seconds with a finite 50 ms interval;
there is no idle wait. Other-package subtrees are skipped. Dumps contain bounded
own-app node Bundles (`nodes`) with actual text/content descriptions,
clickability, scrollability, enabled/visible flags and screen bounds, plus a
machine-readable JSON copy (`ui_probe`). Limits are 512 nodes, depth 64,
2048 characters per label and 65536 serialized node characters.

Clicks require exactly one visible, enabled, own-package clickable node matching
the requested actual description/text. No ancestor fallback, invented merged
label or coordinate injection is used. Scroll requires exactly one visible,
enabled own-package scrollable node. A second fresh tree must contain the same
unique node with the same identity and fingerprint; refresh, advertised action
and focused root are checked immediately before calling `performAction`.
Stale, absent, ambiguous or foreign-app targets fail without an action attempt.

`action_attempted` and `action_result` distinguish issuing an accessibility action
from its returned result. A true result is not a backend codec/readback receipt;
dump the UI again and inspect the app/native evidence separately. Platform API
calls are synchronous and are subject to Android's own binder behavior; the
three-second limit bounds retries for null roots, not an uninterruptible OS call.

`root_diagnostic` reports only the validation phase, root-present flag,
package/class/window ID before and after refresh, and refresh-attempt/result
booleans. `refresh_result` is absent if refresh was never called or threw. Root
package rejection, refresh returning false and package changes after refresh
have distinct errors. These diagnostics contain no other-app text or content
descriptions and do not relax freshness, identity, focus or action guards.

The helper uses public [Instrumentation.getUiAutomation](https://developer.android.com/reference/android/app/Instrumentation#getUiAutomation(int))
with [FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES](https://developer.android.com/reference/android/app/UiAutomation#FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
when available, [getRootInActiveWindow](https://developer.android.com/reference/android/app/UiAutomation#getRootInActiveWindow())
and [AccessibilityNodeInfo.performAction](https://developer.android.com/reference/android/view/accessibility/AccessibilityNodeInfo#performAction(int)).
It changes only its UiAutomation service's interactive-window retrieval flag. It
does not change OS settings, grant permissions, enable an accessibility service,
adopt shell identity, exempt hidden APIs, or interact with another app's nodes.
