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

/** Explicit finite preference experiment. CodecProbe remains a separate read-only entry point. */
public final class LHDCPreferenceCheck extends Instrumentation {
    private static final String TARGET = "com.bdkaudio.controller";
    private static final String NAME = "BDK SPEAKER";
    private static final long ORIGINAL_QUALITY = 0x8008L;
    private static final long REQUESTED_QUALITY = 0x8007L;
    private static final long POLL_MS = 3000;
    private static final long CALL_MS = 1000;
    private final StageGuard experimentStage = new StageGuard();
    private final StageGuard restoreStage = new StageGuard();

    /** Commit bookkeeping and deadline closure are atomic; Binder never holds this lock. */
    private static final class StageGuard {
        private boolean allowed = true, invoked = false;
        synchronized void commit(String refused) {
            if (!allowed) throw new IllegalStateException(refused);
            invoked = true;
        }
        synchronized boolean close() {
            allowed = false;
            return invoked;
        }
    }

    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    private static Object get(Object object, String name) throws Exception {
        if (object == null) throw new IllegalStateException("No object for " + name);
        return object.getClass().getMethod(name).invoke(object);
    }

    private static long number(Object object, String name) throws Exception {
        Object value = get(object, name);
        if (!(value instanceof Number)) throw new IllegalStateException("No numeric " + name);
        return ((Number) value).longValue();
    }

    private static final class Config {
        final Object raw;
        final int type, priority, rate, bits, channels;
        final long cs1, cs2, cs3, cs4, extendedId;
        final String extendedName, reportedText;
        Config(Object raw) throws Exception {
            this.raw = raw;
            type = (int) number(raw, "getCodecType");
            priority = (int) number(raw, "getCodecPriority");
            rate = (int) number(raw, "getSampleRate");
            bits = (int) number(raw, "getBitsPerSample");
            channels = (int) number(raw, "getChannelMode");
            cs1 = number(raw, "getCodecSpecific1");
            cs2 = number(raw, "getCodecSpecific2");
            cs3 = number(raw, "getCodecSpecific3");
            cs4 = number(raw, "getCodecSpecific4");
            Object extended = get(raw, "getExtendedCodecType");
            extendedId = number(extended, "getCodecId");
            Object name = get(extended, "getCodecName");
            if (!(name instanceof String)) throw new IllegalStateException("Extended codec name unavailable");
            extendedName = (String) name;
            reportedText = raw.toString();
        }
        boolean sameNonQuality(Config other) {
            return type == other.type && priority == other.priority && rate == other.rate &&
                bits == other.bits && channels == other.channels &&
                (cs1 & ~0xFFL) == (other.cs1 & ~0xFFL) && cs2 == other.cs2 &&
                cs3 == other.cs3 && cs4 == other.cs4 && extendedId == other.extendedId &&
                extendedName.equals(other.extendedName);
        }
        boolean same(Config other) { return sameNonQuality(other) && cs1 == other.cs1; }
        void requireFixture() {
            if (type != 15 || priority != 1000000 || rate != 32 || bits != 2 || channels != 2 ||
                cs1 != ORIGINAL_QUALITY || cs2 != 0 || cs3 != 0x5C000000L || cs4 != 0 ||
                extendedId != 889535231L || !"LHDC V5".equals(extendedName)) {
                throw new IllegalStateException("Active configuration does not match the approved LHDC V5 fixture");
            }
        }
        JSONObject json() throws Exception {
            return new JSONObject().put("CodecType", type).put("CodecPriority", priority)
                .put("SampleRate", rate).put("BitsPerSample", bits).put("ChannelMode", channels)
                .put("CodecSpecific1", cs1).put("CodecSpecific2", cs2)
                .put("CodecSpecific3", cs3).put("CodecSpecific4", cs4)
                .put("extendedCodecId", extendedId).put("extendedCodecName", extendedName)
                .put("reportedText", reportedText);
        }
    }

    private static final class Observation {
        final BluetoothDevice device;
        final String address;
        final Config config;
        Observation(BluetoothDevice device, Config config) {
            this.device = device;
            this.address = device.getAddress();
            this.config = config;
        }
    }

    /** One actual native call at a time; timing out never cancels/releases its lease. */
    private static final class NativeLease {
        final ExecutorService executor = Executors.newSingleThreadExecutor(work -> {
            Thread thread = new Thread(work, "BDK-LHDC-preference-check");
            thread.setDaemon(true);
            return thread;
        });
        Future<?> pending;
        <T> T call(Callable<T> action, long timeoutMs) throws Exception {
            if (pending != null && !pending.isDone()) {
                throw new IllegalStateException("Previous native call is still pending; refusing overlap");
            }
            Future<T> task = executor.submit(action);
            pending = task;
            try { return task.get(timeoutMs, TimeUnit.MILLISECONDS); }
            finally { if (task.isDone()) pending = null; }
        }
        boolean awaitIdle(long timeoutMs) {
            Future<?> task = pending;
            if (task == null) return true;
            try { task.get(timeoutMs, TimeUnit.MILLISECONDS); }
            catch (Exception error) { /* A thrown call is idle; a pending one is not. */ }
            if (!task.isDone()) return false;
            pending = null;
            return true;
        }
        void close() { executor.shutdown(); }
    }

    private Observation observe(BluetoothA2dp profile, String expectedAddress) throws Exception {
        List<BluetoothDevice> matches = new ArrayList<>();
        for (BluetoothDevice device : profile.getConnectedDevices()) {
            if (NAME.equals(device.getName()) &&
                profile.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED) matches.add(device);
        }
        if (matches.size() != 1) throw new IllegalStateException("Expected exactly one connected BDK SPEAKER");
        BluetoothDevice device = matches.get(0);
        if (expectedAddress != null && !expectedAddress.equalsIgnoreCase(device.getAddress())) {
            throw new IllegalStateException("Connected BDK SPEAKER identity changed");
        }
        Object status = profile.getClass().getMethod("getCodecStatus", BluetoothDevice.class).invoke(profile, device);
        if (status == null) throw new IllegalStateException("No direct codec status available");
        return new Observation(device, new Config(get(status, "getCodecConfig")));
    }

    private Object requestedConfig(Config original) throws Exception {
        Class<?> type = Class.forName("android.bluetooth.BluetoothCodecConfig");
        try {
            Constructor<?> ctor = type.getConstructor(int.class, int.class, int.class, int.class,
                int.class, long.class, long.class, long.class, long.class);
            return ctor.newInstance(original.type, original.priority, original.rate, original.bits,
                original.channels, REQUESTED_QUALITY, original.cs2, original.cs3, original.cs4);
        } catch (ReflectiveOperationException unavailable) {
            // Ordinary accessible builder fallback; never alter hidden-API policy/access checks.
            Class<?> builderType = Class.forName("android.bluetooth.BluetoothCodecConfig$Builder");
            Object builder = builderType.getConstructor().newInstance();
            String[] names = {"CodecType", "CodecPriority", "SampleRate", "BitsPerSample", "ChannelMode"};
            int[] values = {original.type, original.priority, original.rate, original.bits, original.channels};
            for (int i = 0; i < names.length; i++) {
                builderType.getMethod("set" + names[i], int.class).invoke(builder, values[i]);
            }
            long[] specifics = {REQUESTED_QUALITY, original.cs2, original.cs3, original.cs4};
            for (int i = 0; i < specifics.length; i++) {
                builderType.getMethod("setCodecSpecific" + (i + 1), long.class).invoke(builder, specifics[i]);
            }
            return builderType.getMethod("build").invoke(builder);
        }
    }

    private Config poll(BluetoothA2dp profile, String address, Config original,
        long wantedQuality, NativeLease lease, JSONObject output, String key) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + POLL_MS;
        do {
            long remaining = deadline - SystemClock.elapsedRealtime();
            if (remaining <= 0) break;
            Observation value = lease.call(() -> observe(profile, address), Math.min(CALL_MS, remaining));
            output.put(key, value.config.json());
            if (!original.sameNonQuality(value.config)) {
                throw new IllegalStateException("Unexpected identity, format, priority or opaque-field change during " + key);
            }
            if (value.config.cs1 == wantedQuality) return value.config;
            if (value.config.cs1 != ORIGINAL_QUALITY && value.config.cs1 != REQUESTED_QUALITY) {
                throw new IllegalStateException("Unexpected quality code during " + key);
            }
            remaining = deadline - SystemClock.elapsedRealtime();
            if (remaining > 0) Thread.sleep(Math.min(100, remaining));
        } while (SystemClock.elapsedRealtime() < deadline);
        throw new IllegalStateException("Direct " + key + " readback did not match within 3000 ms");
    }

    private static void error(JSONArray errors, String stage, Throwable error) {
        JSONObject entry = new JSONObject();
        try {
            entry.put("stage", stage).put("error", error.toString());
            Throwable cause = error.getCause();
            if (cause != null) entry.put("cause", cause.toString());
            errors.put(entry);
        } catch (Exception ignored) { /* Preserve the remaining structured result. */ }
    }

    @Override public void onStart() {
        Context context = getTargetContext();
        Bundle result = new Bundle();
        JSONObject output = new JSONObject(), restoration = new JSONObject();
        JSONArray errors = new JSONArray();
        BluetoothAdapter adapter = null;
        BluetoothA2dp[] holder = new BluetoothA2dp[1];
        Object profileLock = new Object();
        boolean[] closed = {false};
        NativeLease lease = new NativeLease();
        Observation initial = null;
        boolean changeVerified = false, restoreVerified = false, setterReturned = false;
        boolean restoreWasInvoked = false;
        try {
            output.put("targetPackage", context.getPackageName()).put("readOnly", false)
                .put("before", JSONObject.NULL).put("after", JSONObject.NULL)
                .put("restored", JSONObject.NULL).put("restoration", restoration)
                .put("errors", errors).put("requestedNominalTargetKbps", 900)
                .put("measuredBitrateKbps", JSONObject.NULL).put("setterReturned", false);
            if (!TARGET.equals(context.getPackageName())) throw new IllegalStateException("Unexpected target package");
            if (context.getPackageManager().checkSignatures(getContext().getPackageName(), TARGET) != PackageManager.SIGNATURE_MATCH) {
                throw new IllegalStateException("Instrumentation and target must have the same certificate");
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                throw new IllegalStateException("Target app has no Bluetooth connect permission");
            }
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
            if (!requested || !ready.await(8, TimeUnit.SECONDS) || holder[0] == null) {
                throw new IllegalStateException("A2DP profile did not become available");
            }
            final BluetoothA2dp profile = holder[0];
            initial = lease.call(() -> observe(profile, null), CALL_MS);
            output.put("deviceName", NAME).put("identityVerified", true)
                .put("before", initial.config.json());
            initial.config.requireFixture();
            final Observation original = initial;
            final Object desired = requestedConfig(original.config);
            Config desiredFields = new Config(desired);
            if (!original.config.sameNonQuality(desiredFields) || desiredFields.cs1 != REQUESTED_QUALITY) {
                throw new IllegalStateException("Constructed preference changed fields other than quality");
            }
            output.put("requested", desiredFields.json());
            final Method setter = profile.getClass().getMethod("setCodecConfigPreference", BluetoothDevice.class,
                Class.forName("android.bluetooth.BluetoothCodecConfig"));
            lease.call(() -> {
                Observation fresh = observe(profile, original.address);
                if (!original.config.same(fresh.config)) throw new IllegalStateException("Configuration changed before 900 kbps submission");
                experimentStage.commit("Experiment deadline passed before setter");
                setter.invoke(profile, fresh.device, desired);
                return null;
            }, CALL_MS);
            setterReturned = true;
            output.put("setterReturned", true);
            poll(profile, original.address, original.config, REQUESTED_QUALITY, lease, output, "after");
            changeVerified = true;
        } catch (Throwable failure) {
            error(errors, "preferenceCheck", failure);
        } finally {
            boolean experimentWasInvoked = experimentStage.close();
            try {
                restoration.put("required", experimentWasInvoked).put("attempted", false)
                    .put("setterReturned", false).put("verified", false);
                if (initial != null && experimentWasInvoked) {
                    // Do not enqueue a delayed setter behind an unknown native call.
                    // Without a fresh eligible observation, restoring is unsafe.
                    if (!lease.awaitIdle(POLL_MS)) {
                        restoration.put("skippedReason", "Native call is still pending; identity and non-quality fields cannot be rechecked");
                    } else {
                        final BluetoothA2dp profile = holder[0];
                        final Observation original = initial;
                        restoration.put("attempted", true);
                        Observation restorePreflight = lease.call(() -> {
                            Observation fresh = observe(profile, original.address);
                            if (!original.config.sameNonQuality(fresh.config)) {
                                throw new IllegalStateException("Restoration refused: identity, format, priority or opaque fields changed");
                            }
                            Method setter = profile.getClass().getMethod("setCodecConfigPreference", BluetoothDevice.class,
                                Class.forName("android.bluetooth.BluetoothCodecConfig"));
                            restoreStage.commit("Restoration deadline passed before setter");
                            // Reuse the captured immutable config, including its exact original priority/opaque fields.
                            setter.invoke(profile, fresh.device, original.config.raw);
                            return fresh;
                        }, CALL_MS);
                        restoration.put("setterReturned", true).put("before", restorePreflight.config.json());
                        if (output.isNull("after")) output.put("after", restorePreflight.config.json());
                        Config restored = poll(profile, original.address, original.config, ORIGINAL_QUALITY,
                            lease, output, "restored");
                        restoreVerified = original.config.same(restored);
                        restoration.put("verified", restoreVerified);
                    }
                }
            } catch (Throwable failure) {
                error(errors, "restore", failure);
            } finally {
                restoreWasInvoked = restoreStage.close();
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
                output.put("experimentSetterInvoked", experimentWasInvoked)
                    .put("experimentSetterOutcomeUnknown", experimentWasInvoked && !setterReturned)
                    .put("changedPreferenceVerified", changeVerified)
                    .put("restoreSetterInvoked", restoreWasInvoked)
                    .put("restoreVerified", restoreVerified)
                    .put("success", changeVerified && restoreVerified && errors.length() == 0);
                result.putString("lhdc_preference_check", output.toString());
            } catch (Exception failure) {
                result.putString("lhdc_preference_check_error", failure.toString());
            }
            finish(changeVerified && restoreVerified && errors.length() == 0 ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }
}
