import java.nio.charset.StandardCharsets;
import java.util.Base64;

public final class BdkBuildIdentityTest {
    private static String define(String value) {
        return Base64.getEncoder().encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }
    private static void reject(String target, String flags) {
        try { BdkBuildIdentity.applicationId(target, flags); }
        catch (IllegalArgumentException expected) { return; }
        throw new AssertionError("Diagnostic target was admitted without QA: " + target);
    }
    public static void main(String[] args) {
        String yes = define("BDK_NATIVE_QA=true"), no = define("BDK_NATIVE_QA=false");
        for (String target : new String[] {"tools/native_preview_profile.dart",
                "./tools/native_preview_profile.dart", "D:\\project\\tools\\native_preview_profile.dart",
                "/project/tools/native_preview_profile.dart", "tools/light_diffusion_probe.dart"}) {
            reject(target, null); reject(target, no); reject(target, "not-base64!");
            if (!BdkBuildIdentity.applicationId(target, yes).equals("com.bdkaudio.controller.nativeqa"))
                throw new AssertionError("Wrong isolated identity");
        }
        reject("tools/native_preview_profile.dart", yes + "," + no);
        if (!BdkBuildIdentity.applicationId("lib/main.dart", define("BDK_PREVIEW_ONLY=true"))
                .equals("com.bdkaudio.controller")) throw new AssertionError("Normal app identity changed");
        System.out.println("PASS 22 build-identity cases: missing/false/malformed/true, Windows and absolute paths, duplicate flags, normal app");
    }
}
