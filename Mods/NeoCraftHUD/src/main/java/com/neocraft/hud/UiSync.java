package com.neocraft.hud;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Reads the NeoCraft UI theme ({@code config/neocraft_ui.json}) so the
 * HUD follows the same accent and corner style as the launcher and the
 * {@code neocraft-ui} screen mod. The file is written by Neo Studio and
 * hot-reloaded by the UI mod; this reader polls {@code lastModified}
 * once per second and keeps the last good values on parse errors.
 */
public final class UiSync {

    private static final Path CONFIG_PATH = Path.of("config", "neocraft_ui.json");

    private static volatile String accentColor = "";
    private static volatile String glowColor = "";
    private static volatile String cornerStyle = "";
    private static volatile long lastModified = 0L;
    private static final AtomicBoolean watcherRunning = new AtomicBoolean(false);

    private UiSync() { }

    /** Accent ARGB for HUD elements. Falls back to {@code fallback} when
     *  the UI config is missing or has no accent. */
    public static int accentColor(int fallback) {
        String hex = accentColor;
        return hex.isEmpty() ? fallback : HudConfig.parseColor(hex, fallback);
    }

    /** Secondary glow ARGB (bloom accents). */
    public static int glowColor(int fallback) {
        String hex = glowColor;
        return hex.isEmpty() ? fallback : HudConfig.parseColor(hex, fallback);
    }

    /** Panel corner radius mirroring the launcher corner style —
     *  "voxel" means sharp corners, anything else stays rounded. */
    public static int cornerRadius() {
        return "voxel".equals(cornerStyle) ? 3 : 6;
    }

    public static void startWatcher() {
        if (!watcherRunning.compareAndSet(false, true)) return;
        ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "neocraft-hud-ui-sync");
            t.setDaemon(true);
            return t;
        });
        exec.scheduleWithFixedDelay(() -> {
            try {
                if (!Files.isRegularFile(CONFIG_PATH)) return;
                long modified = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
                if (modified == lastModified) return;
                lastModified = modified;
                JsonObject root = JsonParser.parseString(
                        Files.readString(CONFIG_PATH, StandardCharsets.UTF_8)).getAsJsonObject();
                accentColor = str(root, "accentColor", "");
                glowColor = str(root, "launcherGlow", "");
                if (glowColor.isEmpty()) glowColor = str(root, "tintColor", "");
                cornerStyle = str(root, "cornerStyle", "");
            } catch (Exception ignored) { }
        }, 1, 1, TimeUnit.SECONDS);
    }

    private static String str(JsonObject o, String key, String def) {
        var e = o.get(key);
        if (e == null || !e.isJsonPrimitive()) return def;
        String s = e.getAsString();
        return s == null ? def : s;
    }
}
