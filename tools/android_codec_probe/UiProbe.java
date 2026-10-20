package com.bdkaudio.codecprobe;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Finite own-app UI QA. Does not wait for idle or inject input coordinates. */
public final class UiProbe extends Instrumentation {
    private static final String PROBE_PACKAGE = "com.bdkaudio.codecprobe";
    private static final String APP_PACKAGE = "com.bdkaudio.controller";
    private static final long ROOT_POLL_MILLIS = 3000;
    private static final int MAX_NODES = 512;
    private static final int MAX_DEPTH = 64;
    private static final int MAX_LABEL_LENGTH = 2048;
    private static final int MAX_DUMP_CHARS = 65536;
    private Bundle arguments;

    @Override public void onCreate(Bundle supplied) {
        super.onCreate(supplied);
        arguments = supplied == null ? new Bundle() : new Bundle(supplied);
        start();
    }

    @Override public void onStart() {
        Bundle output = new Bundle();
        output.putBoolean("action_attempted", false);
        output.putBoolean("action_result", false);
        output.putString("allowed_package", APP_PACKAGE);
        Scan before = null;
        Scan fresh = null;
        AccessibilityNodeInfo finalRoot = null;
        try {
            if (!PROBE_PACKAGE.equals(getTargetContext().getPackageName())) {
                throw new IllegalStateException("UiProbe must target its own independent probe package");
            }
            Request request = new Request(arguments);
            output.putString("mode", request.mode);
            UiAutomation automation = Build.VERSION.SDK_INT >= 24
                ? getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
                : getUiAutomation();
            if (automation == null) throw new IllegalStateException("UiAutomation is unavailable");
            AccessibilityServiceInfo service = automation.getServiceInfo();
            if (service == null) throw new IllegalStateException("UI accessibility connection is unavailable");
            service.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
            automation.setServiceInfo(service);

            before = scan(ownedFocusedRoot(automation, true, output, "initial"), request);
            output.putString("root_package", APP_PACKAGE);
            output.putInt("root_window_id", before.windowId);
            output.putLong("captured_at_elapsed_ms", SystemClock.elapsedRealtime());
            output.putParcelableArrayList("nodes", before.bundles);
            output.putInt("node_count", before.bundles.size());

            if (!"dump".equals(request.mode)) {
                AccessibilityNodeInfo selected = uniqueCandidate(before);
                // A second, independently fetched tree must still identify the
                // same unique node. Never fall back to an ancestor or position.
                fresh = scan(ownedFocusedRoot(automation, false, output, "target_recheck"), request);
                AccessibilityNodeInfo current = uniqueCandidate(fresh);
                if (before.windowId != fresh.windowId || !selected.equals(current)
                        || !fingerprint(selected).equals(fingerprint(current))) {
                    throw new IllegalStateException("UI target changed; no action performed");
                }
                if (!current.refresh() || !eligible(current, request)
                        || !fingerprint(selected).equals(fingerprint(current))) {
                    throw new IllegalStateException("UI target is stale; no action performed");
                }
                // Recheck focus immediately before every action. The action
                // itself remains bound to the validated own-package node.
                finalRoot = ownedFocusedRoot(automation, false, output, "pre_action");
                if (finalRoot.getWindowId() != fresh.windowId) {
                    throw new IllegalStateException("Focused window changed; no action performed");
                }
                if (!supports(current, request.action)) {
                    throw new IllegalStateException("Unique node does not advertise the requested action");
                }
                output.putBundle("target_node", describe(current, -1, -1, -1));
                output.putBoolean("action_attempted", true);
                boolean accepted = current.performAction(request.action);
                output.putBoolean("action_result", accepted);
                if (!accepted) throw new IllegalStateException("Own-app accessibility action returned false");
            }
            output.putString("ui_probe", encode(output).toString());
            finish(Activity.RESULT_OK, output);
        } catch (Throwable error) {
            output.putString("ui_probe_error", error.toString());
            try { output.putString("ui_probe", encode(output).toString()); }
            catch (Exception ignored) { /* Keep the structured Bundle on encoding failure. */ }
            finish(Activity.RESULT_CANCELED, output);
        } finally {
            recycle(finalRoot);
            if (fresh != null) fresh.close();
            if (before != null) before.close();
        }
    }

    /** Retry only null roots, and only for a bounded three-second window. */
    private AccessibilityNodeInfo ownedFocusedRoot(UiAutomation automation, boolean pollNull,
            Bundle output, String phase) {
        Bundle diagnostic = new Bundle();
        diagnostic.putString("phase", phase);
        diagnostic.putBoolean("root_present", false);
        diagnostic.putBoolean("refresh_attempted", false);
        output.putBundle("root_diagnostic", diagnostic);
        long deadline = SystemClock.elapsedRealtime() + (pollNull ? ROOT_POLL_MILLIS : 0);
        while (true) {
            AccessibilityNodeInfo root = automation.getRootInActiveWindow();
            if (root != null) {
                try {
                    // Metadata only: do not inspect another package's UI text.
                    diagnostic.putBoolean("root_present", true);
                    diagnostic.putString("package_before", metadata(root.getPackageName()));
                    diagnostic.putString("class_before", metadata(root.getClassName()));
                    diagnostic.putInt("window_id_before", root.getWindowId());
                    if (!own(root)) {
                        throw new IllegalStateException("Active root package rejected before refresh");
                    }
                    diagnostic.putBoolean("refresh_attempted", true);
                    boolean refreshed = root.refresh();
                    diagnostic.putBoolean("refresh_result", refreshed);
                    diagnostic.putString("package_after", metadata(root.getPackageName()));
                    diagnostic.putString("class_after", metadata(root.getClassName()));
                    diagnostic.putInt("window_id_after", root.getWindowId());
                    if (!refreshed) {
                        throw new IllegalStateException("Allowed-app root refresh returned false");
                    }
                    if (!own(root)) {
                        throw new IllegalStateException("Active root package changed after refresh");
                    }
                    AccessibilityWindowInfo window = root.getWindow();
                    if (window == null) throw new IllegalStateException("Active root has no verifiable window");
                    try {
                        if (!window.isFocused() || !window.isActive()
                                || window.getId() != root.getWindowId()) {
                            throw new IllegalStateException("Allowed app is not the focused active window");
                        }
                    } finally {
                        window.recycle();
                    }
                    return root;
                } catch (Throwable failure) {
                    recycle(root);
                    throw failure;
                }
            }
            long remaining = deadline - SystemClock.elapsedRealtime();
            if (!pollNull || remaining <= 0) {
                throw new IllegalStateException("No active root within the bounded root polling window");
            }
            SystemClock.sleep(Math.min(50, remaining));
        }
    }

    private Scan scan(AccessibilityNodeInfo root, Request request) throws Exception {
        Scan result = new Scan(root.getWindowId());
        ArrayDeque<Pending> queue = new ArrayDeque<>();
        queue.add(new Pending(root, -1, 0));
        try {
            while (!queue.isEmpty()) {
                Pending pending = queue.removeFirst();
                AccessibilityNodeInfo node = pending.node;
                result.retained.add(node);
                if (!own(node)) continue; // Do not inspect other-package subtrees.
                if (result.bundles.size() >= MAX_NODES || pending.depth > MAX_DEPTH) {
                    throw new IllegalStateException("Own-app tree exceeds finite probe bounds");
                }
                int index = result.bundles.size();
                Bundle description = describe(node, index, pending.parent, pending.depth);
                result.encodedChars += encode(description).toString().length();
                if (result.encodedChars > MAX_DUMP_CHARS) {
                    throw new IllegalStateException("Own-app dump exceeds finite output bounds");
                }
                result.bundles.add(description);
                if (eligible(node, request)) result.candidates.add(node);
                int count = node.getChildCount();
                if (count > MAX_NODES || result.retained.size() + queue.size() + count > MAX_NODES) {
                    throw new IllegalStateException("Own-app tree exceeds finite probe bounds");
                }
                for (int child = 0; child < count; child++) {
                    AccessibilityNodeInfo next = node.getChild(child);
                    if (next == null) throw new IllegalStateException("Own-app tree changed during traversal");
                    queue.addLast(new Pending(next, index, pending.depth + 1));
                }
            }
            return result;
        } catch (Throwable failure) {
            while (!queue.isEmpty()) recycle(queue.removeFirst().node);
            result.close();
            throw failure;
        }
    }

    private AccessibilityNodeInfo uniqueCandidate(Scan scan) {
        if (scan.candidates.size() != 1) {
            throw new IllegalStateException("Expected exactly one eligible own-app target; found "
                + scan.candidates.size() + "; no action performed");
        }
        return scan.candidates.get(0);
    }

    private boolean eligible(AccessibilityNodeInfo node, Request request) {
        if ("dump".equals(request.mode) || !own(node) || !node.isEnabled()
                || !node.isVisibleToUser()) return false;
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        if (bounds.isEmpty()) return false;
        if (!"click".equals(request.mode)) return node.isScrollable();
        if (!node.isClickable()) return false;
        return (!"text".equals(request.field) && request.matches(text(node.getContentDescription())))
            || (!"description".equals(request.field) && request.matches(text(node.getText())));
    }

    private static boolean own(AccessibilityNodeInfo node) {
        return APP_PACKAGE.contentEquals(text(node.getPackageName()));
    }

    private static boolean supports(AccessibilityNodeInfo node, int action) {
        for (AccessibilityNodeInfo.AccessibilityAction offered : node.getActionList()) {
            if (offered.getId() == action) return true;
        }
        return false;
    }

    private static String text(CharSequence value) {
        return value == null ? "" : value.toString();
    }

    private static String metadata(CharSequence value) {
        String result = text(value);
        return result.length() > 256 ? result.substring(0, 256) : result;
    }

    private static Bundle describe(AccessibilityNodeInfo node, int index, int parent, int depth) {
        String description = text(node.getContentDescription());
        String label = text(node.getText());
        if (description.length() > MAX_LABEL_LENGTH || label.length() > MAX_LABEL_LENGTH) {
            throw new IllegalStateException("Own-app label exceeds finite probe bounds");
        }
        Rect bounds = new Rect();
        node.getBoundsInScreen(bounds);
        Bundle result = new Bundle();
        result.putInt("index", index);
        result.putInt("parent", parent);
        result.putInt("depth", depth);
        result.putInt("window_id", node.getWindowId());
        result.putString("package", text(node.getPackageName()));
        result.putString("class", text(node.getClassName()));
        result.putString("view_id", node.getViewIdResourceName());
        result.putString("description", description);
        result.putString("text", label);
        result.putBoolean("enabled", node.isEnabled());
        result.putBoolean("visible", node.isVisibleToUser());
        result.putBoolean("clickable", node.isClickable());
        result.putBoolean("scrollable", node.isScrollable());
        result.putIntArray("bounds", new int[] {bounds.left, bounds.top, bounds.right, bounds.bottom});
        return result;
    }

    private static String fingerprint(AccessibilityNodeInfo node) throws Exception {
        return encode(describe(node, -1, -1, -1)).toString();
    }

    private static JSONObject encode(Bundle bundle) throws Exception {
        JSONObject output = new JSONObject();
        for (String key : bundle.keySet()) {
            if ("ui_probe".equals(key)) continue;
            Object value = bundle.get(key);
            if (value instanceof Bundle) value = encode((Bundle) value);
            else if (value instanceof List<?>) {
                JSONArray list = new JSONArray();
                for (Object item : (List<?>) value) {
                    list.put(item instanceof Bundle ? encode((Bundle) item) : item);
                }
                value = list;
            } else if (value instanceof int[]) {
                JSONArray numbers = new JSONArray();
                for (int number : (int[]) value) numbers.put(number);
                value = numbers;
            }
            output.put(key, value == null ? JSONObject.NULL : value);
        }
        return output;
    }

    @SuppressWarnings("deprecation")
    private static void recycle(AccessibilityNodeInfo node) {
        if (node != null) node.recycle();
    }

    private static final class Pending {
        final AccessibilityNodeInfo node;
        final int parent, depth;
        Pending(AccessibilityNodeInfo node, int parent, int depth) {
            this.node = node;
            this.parent = parent;
            this.depth = depth;
        }
    }

    private static final class Scan {
        final int windowId;
        final ArrayList<Bundle> bundles = new ArrayList<>();
        final ArrayList<AccessibilityNodeInfo> retained = new ArrayList<>();
        final ArrayList<AccessibilityNodeInfo> candidates = new ArrayList<>();
        int encodedChars = 0;
        Scan(int windowId) { this.windowId = windowId; }
        void close() {
            for (AccessibilityNodeInfo node : retained) recycle(node);
            retained.clear();
        }
    }

    private static final class Request {
        final String mode, target, match, field;
        final int action;
        Request(Bundle arguments) {
            mode = arguments.getString("mode", "dump");
            target = arguments.getString("target", "");
            match = arguments.getString("match", "exact");
            field = arguments.getString("field", "either");
            if (!"exact".equals(match) && !"prefix".equals(match)) {
                throw new IllegalArgumentException("match must be exact or prefix");
            }
            if (!"description".equals(field) && !"text".equals(field) && !"either".equals(field)) {
                throw new IllegalArgumentException("field must be description, text or either");
            }
            if ("dump".equals(mode)) action = 0;
            else if ("click".equals(mode)) {
                if (target.isEmpty() || target.length() > MAX_LABEL_LENGTH) {
                    throw new IllegalArgumentException("click requires a bounded nonempty target");
                }
                action = AccessibilityNodeInfo.ACTION_CLICK;
            } else if ("scrollForward".equals(mode)) action = AccessibilityNodeInfo.ACTION_SCROLL_FORWARD;
            else if ("scrollBackward".equals(mode)) action = AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD;
            else throw new IllegalArgumentException("Unsupported UiProbe mode");
        }
        boolean matches(String value) {
            return "prefix".equals(match) ? value.startsWith(target) : value.equals(target);
        }
    }
}
