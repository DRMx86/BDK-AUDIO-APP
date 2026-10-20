import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Locale;

/** Build-time identity policy, before an APK can be installed. */
public final class BdkBuildIdentity {
    private BdkBuildIdentity() {}
    public static String applicationId(String target, String encodedDefines) {
        String normalized = (target == null ? "lib/main.dart" : target)
                .replace('\\', '/').replace("/./", "/").toLowerCase(Locale.ROOT);
        boolean diagnostic = normalized.endsWith("/tools/native_preview_profile.dart")
                || normalized.equals("tools/native_preview_profile.dart")
                || normalized.endsWith("/tools/light_diffusion_probe.dart")
                || normalized.equals("tools/light_diffusion_probe.dart");
        String qa = null;
        if (encodedDefines != null && !encodedDefines.isEmpty()) {
            for (String value : encodedDefines.split(",")) {
                String decoded;
                try { decoded = new String(Base64.getDecoder().decode(value), StandardCharsets.UTF_8); }
                catch (IllegalArgumentException error) {
                    throw new IllegalArgumentException("Malformed Dart defines; refusing ambiguous build identity.");
                }
                if (decoded.startsWith("BDK_NATIVE_QA=")) qa = decoded.substring("BDK_NATIVE_QA=".length());
            }
        }
        boolean isolated = "true".equals(qa);
        if (diagnostic && !isolated) {
            throw new IllegalArgumentException("Diagnostic targets require --dart-define=BDK_NATIVE_QA=true; the installed app must not be replaced.");
        }
        return isolated ? "com.bdkaudio.controller.nativeqa" : "com.bdkaudio.controller";
    }
}
