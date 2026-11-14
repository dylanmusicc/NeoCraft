package com.neocraft.ui;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Live config store for the NeoCraft UI theme.
 *
 * <p>Reads and writes {@code config/neocraft_ui.json} — the document Neo
 * Studio produces via {@code UIConfigWriter}. Parsing is tolerant: every
 * field falls back to a default and the {@code screens} map may be
 * partially populated. A daemon thread polls {@code lastModified} once
 * per second so Studio edits hot-reload in-game; saves are debounced
 * (300 ms) so the in-game settings screen can mark dirty per click.</p>
 */
public final class UiConfig {

    public static final String FORMAT = "neocraft-ui";
    public static final int VERSION = 1;

    /** Screen ids the mod knows how to skin. */
    public static final String[] SCREEN_IDS = {"title", "pause", "death", "options"};

    /** Accent presets offered by the in-game settings screen — mirrors
     *  the Studio swatches. */
    public static final String[] ACCENT_PRESETS = {
            "#5B8CFF", "#4ADE80", "#A78BFA", "#FBBF24", "#9AA4B2"
    };

    private static final Gson GSON = new GsonBuilder()
            .setPrettyPrinting().disableHtmlEscaping().create();
    private static final Path CONFIG_PATH = Path.of("config", "neocraft_ui.json");
    private static final Path TMP_PATH = CONFIG_PATH.resolveSibling("neocraft_ui.json.tmp");
    private static final long SAVE_DEBOUNCE_MS = 300L;

    private static volatile UiState state = defaultState();
    private static volatile long lastModified = 0L;
    private static final AtomicBoolean watcherRunning = new AtomicBoolean(false);
    private static final Object SAVE_LOCK = new Object();
    private static ScheduledExecutorService saver;
    private static ScheduledFuture<?> pendingSave;

    private UiConfig() { }

    // ------------------------------------------------------------------
    // Model
    // ------------------------------------------------------------------

    public static final class UiState {
        public boolean enabled = true;
        public boolean fullRedesign = false;
        public String accentColor = "#5B8CFF";
        public String tintColor = "#5B8CFF";
        public double tintOpacity = 0.14;
        public Map<String, Boolean> screens = defaultScreens();
        // Launcher chrome sync — written by NeoCraft's UIConfigWriter so
        // the in-game NeoCraft menu mirrors the launcher theme. Optional:
        // older documents simply don't carry them.
        public String launcherAccent = "";
        public String launcherGlow = "";
        public String themeMode = "";
        public String cornerStyle = "";
        public String wallpaperStyle = "";
    }

    private static Map<String, Boolean> defaultScreens() {
        Map<String, Boolean> m = new LinkedHashMap<>();
        m.put("title", true);
        m.put("pause", true);
        m.put("death", true);
        m.put("options", false);
        return m;
    }

    // ------------------------------------------------------------------
    // Accessors
    // ------------------------------------------------------------------

    public static UiState state() { return state; }

    /** True when the given screen id should be themed. */
    public static boolean screenEnabled(String id) {
        UiState s = state;
        if (!s.enabled) return false;
        Boolean v = s.screens.get(id);
        return v == null ? true : v;
    }

    public static int parseColor(String hex, int fallback) {
        if (hex == null) return fallback;
        String h = hex.trim();
        if (h.startsWith("#")) h = h.substring(1);
        if (h.length() != 6 && h.length() != 8) return fallback;
        try {
            long rgb = Long.parseLong(h.length() == 8 ? h.substring(2) : h, 16);
            int alpha = h.length() == 8
                    ? (int) Long.parseLong(h.substring(0, 2), 16) : 0xFF;
            return (alpha << 24) | (int) rgb;
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** Accent used by the NeoCraft menu chrome. The launcher writes
     *  {@code accentColor} from the Studio theme on every launch/apply,
     *  so it already mirrors the launcher — in-game edits override it
     *  until the next sync. */
    public static String chromeAccent() {
        return state.accentColor;
    }

    public static String chromeGlow() {
        UiState s = state;
        return (s.launcherGlow != null && !s.launcherGlow.isEmpty())
                ? s.launcherGlow : s.accentColor;
    }

    public static int chromeAccentColor(int fallback) {
        return parseColor(chromeAccent(), fallback);
    }

    public static int chromeGlowColor(int fallback) {
        return parseColor(chromeGlow(), fallback);
    }

    /** Panel corner radius mirroring the launcher's corner style
     *  ("voxel" = sharp, anything else = rounded). */
    public static int cornerRadius() {
        return "voxel".equals(state.cornerStyle) ? 4 : 10;
    }

    // ------------------------------------------------------------------
    // Parsing / serialization
    // ------------------------------------------------------------------

    private static UiState defaultState() {
        return new UiState();
    }

    public static UiState parse(String json) {
        UiState s = new UiState();
        try {
            JsonObject root = JsonParser.parseString(json).getAsJsonObject();
            s.enabled = bool(root, "enabled", true);
            s.fullRedesign = bool(root, "fullRedesign", false);
            s.accentColor = str(root, "accentColor", "#5B8CFF");
            s.tintColor = str(root, "tintColor", s.accentColor);
            s.tintOpacity = clamp(num(root, "tintOpacity", 0.14), 0.0, 1.0);
            JsonObject screens = obj(root, "screens");
            if (screens != null) {
                Map<String, Boolean> m = defaultScreens();
                for (Map.Entry<String, JsonElement> e : screens.entrySet()) {
                    if (e.getValue().isJsonPrimitive()) {
                        m.put(e.getKey(), e.getValue().getAsBoolean());
                    }
                }
                s.screens = m;
            }
            s.launcherAccent = str(root, "launcherAccent", "");
            s.launcherGlow = str(root, "launcherGlow", "");
            s.themeMode = str(root, "themeMode", "");
            s.cornerStyle = str(root, "cornerStyle", "");
            s.wallpaperStyle = str(root, "wallpaperStyle", "");
        } catch (Exception e) {
            return defaultState();
        }
        return s;
    }

    public static String toJson(UiState s) {
        JsonObject root = new JsonObject();
        root.addProperty("format", FORMAT);
        root.addProperty("version", VERSION);
        root.addProperty("updatedAt", Instant.now().toString());
        root.addProperty("enabled", s.enabled);
        root.addProperty("fullRedesign", s.fullRedesign);
        root.addProperty("accentColor", s.accentColor);
        root.addProperty("tintColor", s.tintColor);
        root.addProperty("tintOpacity", s.tintOpacity);
        JsonObject screens = new JsonObject();
        for (Map.Entry<String, Boolean> e : s.screens.entrySet()) {
            screens.addProperty(e.getKey(), e.getValue());
        }
        root.add("screens", screens);
        // Round-trip the launcher chrome fields — an in-game save must
        // not strip the sync data the launcher wrote.
        if (s.launcherAccent != null && !s.launcherAccent.isEmpty()) {
            root.addProperty("launcherAccent", s.launcherAccent);
        }
        if (s.launcherGlow != null && !s.launcherGlow.isEmpty()) {
            root.addProperty("launcherGlow", s.launcherGlow);
        }
        if (s.themeMode != null && !s.themeMode.isEmpty()) {
            root.addProperty("themeMode", s.themeMode);
        }
        if (s.cornerStyle != null && !s.cornerStyle.isEmpty()) {
            root.addProperty("cornerStyle", s.cornerStyle);
        }
        if (s.wallpaperStyle != null && !s.wallpaperStyle.isEmpty()) {
            root.addProperty("wallpaperStyle", s.wallpaperStyle);
        }
        return GSON.toJson(root);
    }

    // ------------------------------------------------------------------
    // File IO + watcher
    // ------------------------------------------------------------------

    public static void ensureExists() {
        try {
            Files.createDirectories(CONFIG_PATH.getParent());
            if (!Files.exists(CONFIG_PATH)) {
                Files.writeString(CONFIG_PATH, toJson(defaultState()), StandardCharsets.UTF_8);
            }
        } catch (IOException ignored) { }
    }

    public static void load() {
        try {
            if (!Files.isRegularFile(CONFIG_PATH)) return;
            lastModified = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
            UiState parsed = parse(Files.readString(CONFIG_PATH, StandardCharsets.UTF_8));
            synchronized (SAVE_LOCK) {
                state = parsed;
            }
        } catch (Exception ignored) { }
    }

    public static void startWatcher() {
        if (!watcherRunning.compareAndSet(false, true)) return;
        ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "neocraft-ui-config-watch");
            t.setDaemon(true);
            return t;
        });
        exec.scheduleWithFixedDelay(() -> {
            try {
                if (!Files.isRegularFile(CONFIG_PATH)) return;
                long modified = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
                if (modified != lastModified) {
                    lastModified = modified;
                    UiState parsed = parse(Files.readString(CONFIG_PATH, StandardCharsets.UTF_8));
                    // Swap under SAVE_LOCK so an in-flight update() can't
                    // mutate the object being replaced mid-snapshot.
                    synchronized (SAVE_LOCK) {
                        state = parsed;
                    }
                }
            } catch (Exception ignored) { }
        }, 1, 1, TimeUnit.SECONDS);
    }

    /** Debounced save — the in-game editor calls this after every change. */
    public static void requestSave() {
        synchronized (SAVE_LOCK) {
            scheduleSaveLocked(state);
        }
    }

    /**
     * Atomically mutates the live state and schedules a save. Use this
     * for every in-game edit: reading {@link #state()} into a local and
     * mutating it later races the config watcher, which swaps the whole
     * {@link UiState} instance whenever Neo Studio rewrites the file —
     * edits made through a stale reference would be silently dropped.
     */
    public static void update(java.util.function.Consumer<UiState> mutator) {
        synchronized (SAVE_LOCK) {
            UiState s = state;
            mutator.accept(s);
            scheduleSaveLocked(s);
        }
    }

    /** Snapshots {@code s} and schedules the debounced write. Caller
     *  must hold {@link #SAVE_LOCK}. */
    private static void scheduleSaveLocked(UiState s) {
        if (saver == null) {
            saver = Executors.newSingleThreadScheduledExecutor(r -> {
                Thread t = new Thread(r, "neocraft-ui-config-save");
                t.setDaemon(true);
                return t;
            });
        }
        if (pendingSave != null) pendingSave.cancel(false);
        UiState snapshot = new UiState();
        snapshot.enabled = s.enabled;
        snapshot.fullRedesign = s.fullRedesign;
        snapshot.accentColor = s.accentColor;
        snapshot.tintColor = s.tintColor;
        snapshot.tintOpacity = s.tintOpacity;
        snapshot.screens = new LinkedHashMap<>(s.screens);
        snapshot.launcherAccent = s.launcherAccent;
        snapshot.launcherGlow = s.launcherGlow;
        snapshot.themeMode = s.themeMode;
        snapshot.cornerStyle = s.cornerStyle;
        snapshot.wallpaperStyle = s.wallpaperStyle;
        pendingSave = saver.schedule(() -> saveNow(snapshot), SAVE_DEBOUNCE_MS, TimeUnit.MILLISECONDS);
    }

    public static void saveNow() { saveNow(state); }

    private static void saveNow(UiState s) {
        try {
            Files.createDirectories(CONFIG_PATH.getParent());
            Path tmp = TMP_PATH;
            try (Writer w = Files.newBufferedWriter(tmp, StandardCharsets.UTF_8)) {
                w.write(toJson(s));
            }
            Files.move(tmp, CONFIG_PATH, StandardCopyOption.REPLACE_EXISTING);
            lastModified = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
        } catch (Exception ignored) { }
    }

    // ------------------------------------------------------------------
    // Small parse helpers (tolerant)
    // ------------------------------------------------------------------

    private static JsonObject obj(JsonObject o, String key) {
        JsonElement e = o.get(key);
        return e != null && e.isJsonObject() ? e.getAsJsonObject() : null;
    }

    private static String str(JsonObject o, String key, String def) {
        JsonElement e = o.get(key);
        if (e == null || !e.isJsonPrimitive()) return def;
        String s = e.getAsString();
        return s.isEmpty() ? def : s;
    }

    private static boolean bool(JsonObject o, String key, boolean def) {
        JsonElement e = o.get(key);
        return e != null && e.isJsonPrimitive() ? e.getAsBoolean() : def;
    }

    private static double num(JsonObject o, String key, double def) {
        JsonElement e = o.get(key);
        if (e == null || !e.isJsonPrimitive()) return def;
        try { return e.getAsDouble(); } catch (Exception ex) { return def; }
    }

    private static double clamp(double v, double lo, double hi) {
        return Math.max(lo, Math.min(hi, v));
    }
}
