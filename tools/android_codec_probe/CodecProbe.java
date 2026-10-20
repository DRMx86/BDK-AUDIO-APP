package com.bdkaudio.codecprobe;

import android.Manifest;
import android.app.Activity;
import android.app.Instrumentation;
import android.bluetooth.BluetoothA2dp;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Bundle;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/** Read-only target-app API research. Never invokes a setter, connect or pair. */
public final class CodecProbe extends Instrumentation {
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }
    private Object getter(Object object, String name) {
        try { return object.getClass().getMethod(name).invoke(object); }
        catch (Exception error) { return JSONObject.NULL; }
    }
    private JSONObject config(Object value) throws Exception {
        JSONObject item = new JSONObject();
        String[] names = {"CodecType", "CodecName", "SampleRate", "BitsPerSample", "ChannelMode",
            "CodecSpecific1", "CodecSpecific2", "CodecSpecific3", "CodecSpecific4"};
        for (String name : names) item.put(name, getter(value, "get" + name));
        Object extended = getter(value, "getExtendedCodecType");
        if (extended != JSONObject.NULL) {
            item.put("extendedCodecId", getter(extended, "getCodecId"));
            item.put("extendedCodecName", getter(extended, "getCodecName"));
        }
        item.put("reportedText", value.toString());
        return item;
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        Context context = getTargetContext();
        BluetoothA2dp[] profile = new BluetoothA2dp[1];
        try {
            if (!"com.bdkaudio.controller".equals(context.getPackageName())) {
                throw new IllegalStateException("Unexpected target package");
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                throw new IllegalStateException("Target app has no Bluetooth connect permission");
            }
            BluetoothManager manager = context.getSystemService(BluetoothManager.class);
            CountDownLatch ready = new CountDownLatch(1);
            boolean requested = manager.getAdapter().getProfileProxy(context, new BluetoothProfile.ServiceListener() {
                @Override public void onServiceConnected(int id, BluetoothProfile proxy) {
                    if (id == BluetoothProfile.A2DP) { profile[0] = (BluetoothA2dp) proxy; ready.countDown(); }
                }
                @Override public void onServiceDisconnected(int id) { }
            }, BluetoothProfile.A2DP);
            if (!requested || !ready.await(8, TimeUnit.SECONDS) || profile[0] == null) {
                throw new IllegalStateException("A2DP profile did not become available");
            }
            List<BluetoothDevice> matches = new ArrayList<>();
            for (BluetoothDevice device : profile[0].getConnectedDevices()) {
                if ("BDK SPEAKER".equals(device.getName()) &&
                    profile[0].getConnectionState(device) == BluetoothProfile.STATE_CONNECTED) matches.add(device);
            }
            if (matches.size() != 1) throw new IllegalStateException("Expected exactly one connected BDK SPEAKER");
            BluetoothDevice device = matches.get(0);
            Object status = profile[0].getClass().getMethod("getCodecStatus", BluetoothDevice.class).invoke(profile[0], device);
            if (status == null) throw new IllegalStateException("No current codec status exposed");
            JSONObject output = new JSONObject();
            output.put("targetPackage", context.getPackageName());
            output.put("readOnly", true);
            output.put("active", config(getter(status, "getCodecConfig")));
            Object caps = getter(status, "getCodecsSelectableCapabilities");
            JSONArray capabilities = new JSONArray();
            if (caps instanceof Iterable<?>) for (Object cap : (Iterable<?>) caps) capabilities.put(config(cap));
            else if (caps instanceof Object[]) for (Object cap : (Object[]) caps) capabilities.put(config(cap));
            output.put("selectable", capabilities);
            JSONArray methods = new JSONArray();
            for (Method method : profile[0].getClass().getMethods()) {
                if (method.getName().toLowerCase(java.util.Locale.ROOT).matches(".*(codec|lhdc).*")) {
                    methods.put(method.toGenericString());
                }
            }
            output.put("profileMethods", methods);
            result.putString("codec_probe", output.toString());
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            result.putString("codec_probe_error", error.toString());
            if (error.getCause() != null) result.putString("cause", error.getCause().toString());
            finish(Activity.RESULT_CANCELED, result);
        } finally {
            if (profile[0] != null) {
                BluetoothManager manager = context.getSystemService(BluetoothManager.class);
                manager.getAdapter().closeProfileProxy(BluetoothProfile.A2DP, profile[0]);
            }
        }
    }
}
