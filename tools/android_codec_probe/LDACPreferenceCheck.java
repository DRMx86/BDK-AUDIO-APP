package com.bdkaudio.codecprobe;

import android.Manifest;
import android.app.Activity;
import android.app.Instrumentation;
import android.bluetooth.BluetoothA2dp;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.SystemClock;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/** Explicit finite LDAC experiment, separate from the unchanged read-only CodecProbe. */
public final class LDACPreferenceCheck extends Instrumentation {
    private static final String TARGET = "com.bdkaudio.controller", NAME = "BDK SPEAKER";
    private static final long POLL_MS = 3000, CALL_MS = 1000;
    private static final long[] QUALITIES = {1002, 1001, 1000, 1003};
    private static final int[] TARGETS = {330, 660, 990, 0};
    private final List<StageGuard> experimentStages = new ArrayList<>();
    private final StageGuard restoreStage = new StageGuard();

    /** Bookkeeping/closure is atomic; no native call holds the guard lock. */
    private static final class StageGuard {
        private boolean allowed = true, invoked;
        synchronized void commit() {
            if (!allowed) throw new IllegalStateException("Setter stage closed before commitment");
            invoked = true;
        }
        synchronized boolean close() { allowed = false; return invoked; }
    }
    /** A timeout retains the actual native lease; no uncertain call is retried. */
    private static final class NativeLease {
        final ExecutorService executor = Executors.newSingleThreadExecutor(work -> {
            Thread thread = new Thread(work, "BDK-LDAC-preference-check");
            thread.setDaemon(true);
            return thread;
        });
        Future<?> pending;
        <T> T call(Callable<T> action, long timeoutMs) throws Exception {
            if (pending != null && !pending.isDone()) throw new IllegalStateException("Native call still pending; overlap refused");
            Future<T> task = executor.submit(action);
            pending = task;
            try { return task.get(timeoutMs, TimeUnit.MILLISECONDS); }
            finally { if (task.isDone()) pending = null; }
        }
        boolean awaitIdle(long timeoutMs) {
            Future<?> task = pending;
            if (task == null) return true;
            try { task.get(timeoutMs, TimeUnit.MILLISECONDS); }
            catch (Exception failure) { /* Failed but settled work is idle. */ }
            if (!task.isDone()) return false;
            pending = null;
            return true;
        }
        void close() { executor.shutdown(); }
    }
    private static Object get(Object object, String method) throws Exception {
        if (object == null) throw new IllegalStateException("No object for " + method);
        return object.getClass().getMethod(method).invoke(object);
    }
    private static long number(Object object, String method) throws Exception {
        Object value = get(object, method);
        if (!(value instanceof Number)) throw new IllegalStateException("No numeric " + method);
        return ((Number) value).longValue();
    }
    private static final class Config {
        final Object raw;
        final int type, priority, rate, bits, channels;
        final long cs1, cs2, cs3, cs4, extendedId;
        final String name, text;
        Config(Object raw) throws Exception {
            this.raw = raw;
            type = (int) number(raw, "getCodecType");
            priority = (int) number(raw, "getCodecPriority");
            rate = (int) number(raw, "getSampleRate");
            bits = (int) number(raw, "getBitsPerSample");
            channels = (int) number(raw, "getChannelMode");
            cs1 = number(raw, "getCodecSpecific1"); cs2 = number(raw, "getCodecSpecific2");
            cs3 = number(raw, "getCodecSpecific3"); cs4 = number(raw, "getCodecSpecific4");
            Object extended = get(raw, "getExtendedCodecType");
            extendedId = number(extended, "getCodecId");
            Object named = get(extended, "getCodecName");
            if (!(named instanceof String)) throw new IllegalStateException("Extended codec name unavailable");
            name = (String) named;
            text = raw.toString();
        }
        boolean sameNonQuality(Config other) {
            return type == other.type && priority == other.priority && rate == other.rate &&
                bits == other.bits && channels == other.channels && cs2 == other.cs2 &&
                cs3 == other.cs3 && cs4 == other.cs4 && extendedId == other.extendedId && name.equals(other.name);
        }
        boolean same(Config other) { return sameNonQuality(other) && cs1 == other.cs1; }
        boolean ldacIdentity() { return type == 4 && extendedId == 2852204031L && "LDAC".equals(name); }
        boolean ldac96() { return ldacIdentity() && rate == 8 && bits == 4 && channels == 2; }
        boolean knownLdacQuality() { return cs1 == 0 || cs1 >= 1000 && cs1 <= 1003; }
        boolean validLdacBaseline() {
            return ldacIdentity() && knownLdacQuality() &&
                (rate == 1 || rate == 2 || rate == 4 || rate == 8) &&
                (bits == 1 || bits == 2 || bits == 4) && (channels == 1 || channels == 2);
        }
        boolean validLhdcV5() {
            int index = (int) (cs1 & 0xffL);
            boolean rateKnown = rate == 1 || rate == 2 || rate == 8 || rate == 32;
            if (type <= 6 || extendedId != 889535231L || !"LHDC V5".equals(name) ||
                !rateKnown || (bits != 1 && bits != 2) || channels != 2 ||
                (cs1 & 0xc000L) != 0x8000L || index > 9 ||
                (cs3 & 0xff000000L) != 0x5c000000L) return false;
            if (index == 9) return true;
            if ((cs3 & 0x180L) != 0) return false;
            return rate == 8 || rate == 32 ? index >= 3 : index <= 7;
        }
        JSONObject json() throws Exception {
            return new JSONObject().put("CodecType", type).put("CodecPriority", priority)
                .put("SampleRate", rate).put("BitsPerSample", bits).put("ChannelMode", channels)
                .put("CodecSpecific1", cs1).put("CodecSpecific2", cs2)
                .put("CodecSpecific3", cs3).put("CodecSpecific4", cs4)
                .put("extendedCodecId", extendedId).put("extendedCodecName", name).put("reportedText", text);
        }
    }
    private static final class Observation {
        final BluetoothDevice device;
        final String address;
        final Config active;
        final List<Config> selectable;
        Observation(BluetoothDevice device, Config active, List<Config> selectable) {
            this.device = device; this.address = device.getAddress();
            this.active = active; this.selectable = selectable;
        }
        void requireLdacCapability() {
            for (Config cap : selectable) {
                if (cap.ldacIdentity() && (cap.rate & 8) == 8 && (cap.bits & 4) == 4 && (cap.channels & 2) == 2) return;
            }
            throw new IllegalStateException("Fresh selectable LDAC 96 kHz/32-bit/stereo capability absent");
        }
        void requireActiveCapability() {
            for (Config cap : selectable) {
                if (cap.type == active.type && cap.extendedId == active.extendedId &&
                    (cap.rate & active.rate) == active.rate && (cap.bits & active.bits) == active.bits &&
                    (cap.channels & active.channels) == active.channels) return;
            }
            throw new IllegalStateException("Captured active format is absent from fresh selectable capabilities");
        }
    }
    private static void permission(Context context) {
        if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            throw new IllegalStateException("Target Bluetooth connect permission absent");
        }
    }
    private Observation observe(Context context, BluetoothA2dp profile, String expectedAddress, boolean capabilities) throws Exception {
        permission(context);
        List<BluetoothDevice> matches = new ArrayList<>();
        for (BluetoothDevice device : profile.getConnectedDevices()) {
            if (NAME.equals(device.getName()) && profile.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED) matches.add(device);
        }
        if (matches.size() != 1) throw new IllegalStateException("Expected exactly one connected BDK SPEAKER");
        BluetoothDevice device = matches.get(0);
        if (expectedAddress != null && !expectedAddress.equalsIgnoreCase(device.getAddress())) throw new IllegalStateException("BDK SPEAKER identity changed");
        Object status = profile.getClass().getMethod("getCodecStatus", BluetoothDevice.class).invoke(profile, device);
        Config active = new Config(get(status, "getCodecConfig"));
        List<Config> rows = new ArrayList<>();
        if (capabilities) {
            Object raw = get(status, "getCodecsSelectableCapabilities");
            if (raw instanceof Iterable<?>) for (Object row : (Iterable<?>) raw) rows.add(new Config(row));
            else if (raw instanceof Object[]) for (Object row : (Object[]) raw) rows.add(new Config(row));
            else throw new IllegalStateException("Selectable capability collection unavailable");
        }
        return new Observation(device, active, rows);
    }
    private Object build(int type, int priority, int rate, int bits, int channels, long cs1, long cs2, long cs3, long cs4) throws Exception {
        Class<?> config = Class.forName("android.bluetooth.BluetoothCodecConfig");
        try {
            Constructor<?> ctor = config.getConstructor(int.class, int.class, int.class, int.class, int.class,
                long.class, long.class, long.class, long.class);
            return ctor.newInstance(type, priority, rate, bits, channels, cs1, cs2, cs3, cs4);
        } catch (ReflectiveOperationException unavailable) {
            Class<?> builderType = Class.forName("android.bluetooth.BluetoothCodecConfig$Builder");
            Object builder = builderType.getConstructor().newInstance();
            String[] names = {"CodecType", "CodecPriority", "SampleRate", "BitsPerSample", "ChannelMode"};
            int[] values = {type, priority, rate, bits, channels};
            for (int i = 0; i < names.length; i++) builderType.getMethod("set" + names[i], int.class).invoke(builder, values[i]);
            long[] specifics = {cs1, cs2, cs3, cs4};
            for (int i = 0; i < specifics.length; i++) builderType.getMethod("setCodecSpecific" + (i + 1), long.class).invoke(builder, specifics[i]);
            return builderType.getMethod("build").invoke(builder);
        }
    }
    private void submit(Context context, BluetoothA2dp profile, String address, Config expected,
        Object desired, StageGuard guard, NativeLease lease, JSONObject stage) throws Exception {
        try {
            lease.call(() -> {
                Observation fresh = observe(context, profile, address, true);
                fresh.requireLdacCapability();
                if (!expected.same(fresh.active)) throw new IllegalStateException("Current tuple changed before setter");
                Method setter = profile.getClass().getMethod("setCodecConfigPreference", BluetoothDevice.class,
                    Class.forName("android.bluetooth.BluetoothCodecConfig"));
                permission(context);
                guard.commit();
                setter.invoke(profile, fresh.device, desired);
                return null;
            }, CALL_MS);
            stage.put("setterReturned", true);
        } finally {
            boolean committed = guard.close();
            stage.put("setterCommitted", committed)
                .put("setterOutcomeUnknown", committed && !stage.optBoolean("setterReturned"));
        }
    }
    private Config poll(Context context, BluetoothA2dp profile, String address, Config expected,
        boolean switching, boolean restoring, long quality, NativeLease lease, JSONObject stage) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + POLL_MS;
        do {
            long remaining = deadline - SystemClock.elapsedRealtime();
            if (remaining <= 0) break;
            Config active = lease.call(() -> observe(context, profile, address, false).active, Math.min(CALL_MS, remaining));
            stage.put("after", active.json());
            if (restoring) {
                if (expected.same(active)) return active;
                if (!(active.ldacIdentity() && active.knownLdacQuality()) && !active.validLhdcV5()) {
                    throw new IllegalStateException("Unexpected codec during restoration readback");
                }
            } else if (switching) {
                if (active.ldac96() && active.knownLdacQuality()) return active;
                if (!expected.same(active)) throw new IllegalStateException("Unexpected tuple during initial LDAC switch");
            } else {
                if (!expected.sameNonQuality(active)) throw new IllegalStateException("Non-quality tuple changed during LDAC check");
                if (!active.knownLdacQuality()) throw new IllegalStateException("Unknown LDAC quality readback");
                if (active.cs1 == quality) return active;
            }
            remaining = deadline - SystemClock.elapsedRealtime();
            if (remaining > 0) Thread.sleep(Math.min(100, remaining));
        } while (SystemClock.elapsedRealtime() < deadline);
        throw new IllegalStateException("Matching direct codec readback not confirmed within 3000 ms");
    }
    private static void error(JSONArray errors, String stage, Throwable failure) {
        try {
            JSONObject value = new JSONObject().put("stage", stage).put("error", failure.toString());
            if (failure.getCause() != null) value.put("cause", failure.getCause().toString());
            errors.put(value);
        } catch (Exception ignored) { }
    }
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    @Override public void onStart() {
        Context context = getTargetContext();
        Bundle result = new Bundle();
        JSONObject output = new JSONObject(), restoration = new JSONObject();
        JSONArray stages = new JSONArray(), errors = new JSONArray();
        BluetoothAdapter adapter = null;
        BluetoothA2dp[] holder = new BluetoothA2dp[1];
        Object profileLock = new Object();
        boolean[] closed = {false};
        NativeLease lease = new NativeLease();
        Observation initial = null;
        boolean allVerified = false, restored = false, mutated = false, restoreInvoked = false;
        String currentStage = "setup";
        try {
            output.put("targetPackage", context.getPackageName()).put("readOnly", false)
                .put("before", JSONObject.NULL).put("stages", stages).put("restoration", restoration)
                .put("restored", JSONObject.NULL).put("errors", errors).put("measuredBitrateKbps", JSONObject.NULL);
            if (!TARGET.equals(context.getPackageName())) throw new IllegalStateException("Unexpected target package");
            if (context.getPackageManager().checkSignatures(getContext().getPackageName(), TARGET) != PackageManager.SIGNATURE_MATCH) throw new IllegalStateException("Instrumentation and target certificates differ");
            permission(context);
            BluetoothManager manager = context.getSystemService(BluetoothManager.class);
            adapter = manager == null ? null : manager.getAdapter();
            if (adapter == null) throw new IllegalStateException("No Bluetooth adapter");
            final BluetoothAdapter ownedAdapter = adapter;
            CountDownLatch ready = new CountDownLatch(1);
            boolean requested = adapter.getProfileProxy(context, new BluetoothProfile.ServiceListener() {
                @Override public void onServiceConnected(int id, BluetoothProfile proxy) {
                    if (id != BluetoothProfile.A2DP) return;
                    synchronized (profileLock) {
                        if (closed[0]) ownedAdapter.closeProfileProxy(BluetoothProfile.A2DP, proxy);
                        else holder[0] = (BluetoothA2dp) proxy;
                    }
                    ready.countDown();
                }
                @Override public void onServiceDisconnected(int id) { if (id == BluetoothProfile.A2DP) ready.countDown(); }
            }, BluetoothProfile.A2DP);
            if (!requested || !ready.await(8, TimeUnit.SECONDS) || holder[0] == null) throw new IllegalStateException("A2DP profile unavailable");
            final BluetoothA2dp profile = holder[0];
            initial = lease.call(() -> observe(context, profile, null, true), CALL_MS);
            output.put("identityVerified", true).put("deviceName", NAME).put("before", initial.active.json());
            if (!initial.active.validLhdcV5() && !initial.active.validLdacBaseline()) {
                throw new IllegalStateException("Current configuration is not a valid recognized LHDC V5 or LDAC baseline");
            }
            initial.requireActiveCapability();
            initial.requireLdacCapability();
            final Observation original = initial;
            Config current = initial.active;
            output.put("initialCodecSwitchSkipped", current.ldac96());
            if (!current.ldac96()) {
                Object switchConfig = build(4, 1000000, 8, 4, 2, 0, 0, 0, 0);
                Config switchedRequest = new Config(switchConfig);
                if (!switchedRequest.ldac96() || switchedRequest.cs1 != 0 || switchedRequest.cs2 != 0 ||
                    switchedRequest.cs3 != 0 || switchedRequest.cs4 != 0) throw new IllegalStateException("Invalid constructed LDAC default request");
                currentStage = "switchToLdac96";
                StageGuard switchGuard = new StageGuard(); experimentStages.add(switchGuard);
                JSONObject switching = new JSONObject().put("name", currentStage).put("before", initial.active.json())
                    .put("requested", switchedRequest.json()).put("verified", false).put("setterReturned", false);
                stages.put(switching);
                submit(context, profile, original.address, original.active, switchConfig, switchGuard, lease, switching);
                current = poll(context, profile, original.address, original.active, true, false, 0, lease, switching);
                switching.put("verified", true);
            }
            for (int index = 0; index < QUALITIES.length; index++) {
                long quality = QUALITIES[index];
                currentStage = quality == 1003 ? "adaptive" : "nominal" + TARGETS[index];
                Object desired = build(current.type, current.priority, current.rate, current.bits, current.channels,
                    quality, current.cs2, current.cs3, current.cs4);
                Config desiredFields = new Config(desired);
                if (!current.sameNonQuality(desiredFields) || desiredFields.cs1 != quality) throw new IllegalStateException("Quality request changed non-quality fields");
                StageGuard guard = new StageGuard(); experimentStages.add(guard);
                JSONObject stage = new JSONObject().put("name", currentStage).put("before", current.json())
                    .put("requested", desiredFields.json()).put("verified", false).put("setterReturned", false)
                    .put("nominalTargetKbps", quality == 1003 ? JSONObject.NULL : TARGETS[index]);
                stages.put(stage);
                submit(context, profile, original.address, current, desired, guard, lease, stage);
                current = poll(context, profile, original.address, current, false, false, quality, lease, stage);
                stage.put("verified", true);
            }
            allVerified = true;
        } catch (Throwable failure) {
            error(errors, currentStage, failure);
        } finally {
            // Closing each guard before collecting flags prevents a timed-out
            // preflight from committing after restoration eligibility is decided.
            for (StageGuard guard : experimentStages) mutated |= guard.close();
            try {
                restoration.put("required", mutated).put("attempted", false).put("verified", false).put("setterReturned", false);
                if (initial != null && mutated) {
                    if (!lease.awaitIdle(POLL_MS)) {
                        restoration.put("skippedReason", "Native lease is still pending; fresh restore eligibility cannot be checked");
                    } else {
                        final BluetoothA2dp profile = holder[0];
                        final Observation original = initial;
                        restoration.put("attempted", true);
                        Config beforeRestore = lease.call(() -> {
                            Observation fresh = observe(context, profile, original.address, false);
                            if (!(fresh.active.ldacIdentity() && fresh.active.knownLdacQuality()) && !fresh.active.validLhdcV5()) {
                                throw new IllegalStateException("Restore refused: current codec is outside recognized experiment states");
                            }
                            // Require a stable complete fresh tuple immediately
                            // before switching back, including opaque fields.
                            Observation stable = observe(context, profile, original.address, false);
                            if (!fresh.active.same(stable.active)) throw new IllegalStateException("Restore refused: current tuple is changing");
                            Method setter = profile.getClass().getMethod("setCodecConfigPreference", BluetoothDevice.class,
                                Class.forName("android.bluetooth.BluetoothCodecConfig"));
                            permission(context);
                            restoreStage.commit();
                            setter.invoke(profile, stable.device, original.active.raw);
                            return stable.active;
                        }, CALL_MS);
                        restoration.put("before", beforeRestore.json()).put("setterReturned", true);
                        Config restoredFields = poll(context, profile, original.address, original.active, false, true,
                            original.active.cs1, lease, restoration);
                        restored = original.active.same(restoredFields);
                        restoration.put("verified", restored);
                        output.put("restored", restoredFields.json());
                    }
                }
            } catch (Throwable failure) {
                error(errors, "restore", failure);
            } finally {
                restoreInvoked = restoreStage.close();
                lease.close();
                synchronized (profileLock) {
                    closed[0] = true;
                    if (adapter != null && holder[0] != null) {
                        try { adapter.closeProfileProxy(BluetoothProfile.A2DP, holder[0]); }
                        catch (Throwable failure) { error(errors, "closeProfileProxy", failure); }
                        finally { holder[0] = null; }
                    }
                }
            }
            try {
                restoration.put("setterCommitted", restoreInvoked)
                    .put("setterOutcomeUnknown", restoreInvoked && !restoration.optBoolean("setterReturned"));
                output.put("anyExperimentSetterCommitted", mutated).put("allLdacStagesVerified", allVerified)
                    .put("restoreVerified", restored).put("success", allVerified && restored && errors.length() == 0);
                result.putString("ldac_preference_check", output.toString());
            } catch (Exception failure) { result.putString("ldac_preference_check_error", failure.toString()); }
            finish(allVerified && restored && errors.length() == 0 ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }
}
