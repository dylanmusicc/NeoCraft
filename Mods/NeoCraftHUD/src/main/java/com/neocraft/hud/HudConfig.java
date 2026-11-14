package com.neocraft.hud;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonPrimitive;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Live config store for the NeoCraft HUD.
 *
 * <p>Reads and writes {@code config/neocraft_hud.json} — a document also
 * produced by the NeoCraft launcher / Studio. Parsing is deliberately
 * tolerant: every field has a fallback, missing {@code profiles}/{@code ui}/
 * {@code options} blocks are fine, and legacy v2 documents (a flat top-level
 * {@code widgets} array, {@code colorHex} instead of {@code accentColor})
 * are upgraded transparently into a single "default" profile.</p>
 *
 * <p>Saves are atomic (temp file + move) and debounced so the in-game editor
 * can mark the config dirty on every drag frame without thrashing disk. A
 * daemon thread polls {@code lastModified} once per second and hot-reloads
 * when the file changes on disk (e.g. edited by the launcher).</p>
 */
public final class HudConfig {

    public static final String FORMAT = "neocraft-hud";
    public static final int VERSION = 3;

    /** Widget kinds understood by the renderer, in picker order. */
    public static final List<String> KINDS = List.of(
            "fpsPill", "coordsCompass", "netherCoords", "armorDurability",
            "potionEffects", "keystrokes", "pingTPS", "clocks", "dayLight",
            "speedometer", "statusPills", "minimap", "lightLevel");

    private static final Gson GSON = new GsonBuilder()
            .setPrettyPrinting().disableHtmlEscaping().create();
    private static final Path CONFIG_PATH = Path.of("config", "neocraft_hud.json");
    private static final Path TMP_PATH = CONFIG_PATH.resolveSibling("neocraft_hud.json.tmp");
    private static final long SAVE_DEBOUNCE_MS = 300L;

    private static volatile HudState state = defaultState();
    private static volatile long lastModified = 0L;
    private static final AtomicBoolean watcherRunning = new AtomicBoolean(false);
    private static final Object SAVE_LOCK = new Object();
    private static ScheduledExecutorService saver;
    private static ScheduledFuture<?> pendingSave;

    private HudConfig() { }

    // ------------------------------------------------------------------
    // Model
    // ------------------------------------------------------------------

    public static final class HudState {
        public String format = FORMAT;
        public int version = VERSION;
        public String updatedAt = "";
        public String activeProfile = "default";
        public List<HudProfile> profiles = new ArrayList<>();
        public HudUiSettings ui = new HudUiSettings();
    }

    public static final class HudProfile {
        public String id = "default";
        public String name = "Default Apple";
        public List<HudWidget> widgets = new ArrayList<>();
    }

    public static final class HudWidget {
        public String id = UUID.randomUUID().toString();
        public String kind = "fpsPill";
        /** Normalized center anchor, 0.0–1.0 of the viewport. */
        public double x = 0.5;
        public double y = 0.05;
        public double scale = 1.0;
        public boolean visible = true;
        public String containerStyle = "neocraft";
        public String fontStyle = "apple";
        public String textStyle = "regular";
        public String colorMode = "static";
        public String textColor = "#FFFFFF";
        public String accentColor = "#0A84FF";
        public String borderColor = "#FFFFFF";
        public double backgroundOpacity = 0.45;
        public Map<String, Object> options = new LinkedHashMap<>();

        public boolean optBool(String key, boolean def) {
            Object v = options.get(key);
            if (v instanceof Boolean b) return b;
            if (v instanceof String s) return Boolean.parseBoolean(s);
            if (v instanceof Number n) return n.doubleValue() != 0;
            return def;
        }

        public String optString(String key, String def) {
            Object v = options.get(key);
            if (v == null) return def;
            String s = String.valueOf(v);
            return s.isEmpty() ? def : s;
        }

        public double optNum(String key, double def) {
            Object v = options.get(key);
            if (v instanceof Number n) return n.doubleValue();
            if (v instanceof String s) {
                try { return Double.parseDouble(s); } catch (NumberFormatException ignored) { }
            }
            return def;
        }
    }

    public static class HudUiSettings {
        public CrosshairUi crosshair = new CrosshairUi();
        public HotbarUi hotbar = new HotbarUi();
        public ScoreboardUi scoreboard = new ScoreboardUi();
        public ChatUi chat = new ChatUi();
        public TitleUi titleScreen = new TitleUi();
    }

    public static class CrosshairUi {
        public boolean enabled = true;
        public String shape = "cross";
        public int size = 8;
        public int thickness = 2;
        public int gap = 2;
        public String colorMode = "static";
        public String color = "#FFFFFF";
        public boolean showCooldown = true;
    }

    public static class HotbarUi {
        public boolean glassBackground = true;
        public String accentColor = "#0A84FF";
        public String xpAccentColor = "#7CFC00";
        public boolean showNumbers = true;
        public boolean animateSelection = true;
    }

    public static class ScoreboardUi {
        public boolean enabled = true;
        public double scale = 1.0;
        public boolean glassBox = true;
        public boolean hideNumbers = false;
    }

    public static class ChatUi {
        public boolean enabled = true;
        public boolean roundedBox = true;
        public boolean compactTimestamps = true;
        public double opacity = 0.6;
    }

    public static class TitleUi {
        public boolean enabled = true;
        public String tintColor = "#0A84FF";
        public double opacity = 0.15;
    }

    // ------------------------------------------------------------------
    // Accessors
    // ------------------------------------------------------------------

    public static HudState state() { return state; }

    public static HudUiSettings ui() { return state.ui; }

    public static List<HudProfile> profiles() { return state.profiles; }

    public static HudProfile activeProfile() {
        String id = state.activeProfile;
        for (HudProfile p : state.profiles) {
            if (p.id.equals(id)) return p;
        }
        return state.profiles.isEmpty() ? null : state.profiles.get(0);
    }

    public static HudProfile profileById(String id) {
        for (HudProfile p : state.profiles) if (p.id.equals(id)) return p;
        return null;
    }

    // ------------------------------------------------------------------
    // Defaults & widget factories
    // ------------------------------------------------------------------

    public static HudState defaultState() {
        HudState s = new HudState();
        HudProfile p = new HudProfile();
        p.widgets.add(createWidget("fpsPill", 0.5, 0.04));
        p.widgets.add(createWidget("coordsCompass", 0.5, 0.13));
        p.widgets.add(createWidget("keystrokes", 0.12, 0.72));
        p.widgets.add(createWidget("clocks", 0.88, 0.06));
        s.profiles.add(p);
        return s;
    }

    public static HudWidget createWidget(String kind) {
        double[] d = defaultAnchor(kind);
        return createWidget(kind, d[0], d[1]);
    }

    public static HudWidget createWidget(String kind, double x, double y) {
        HudWidget w = new HudWidget();
        w.kind = kind;
        w.x = clamp01(x);
        w.y = clamp01(y);
        w.options = defaultOptions(kind);
        return w;
    }

    private static double[] defaultAnchor(String kind) {
        return switch (kind) {
            case "coordsCompass" -> new double[]{0.5, 0.115};
            case "netherCoords" -> new double[]{0.5, 0.19};
            case "armorDurability" -> new double[]{0.5, 0.27};
            case "potionEffects" -> new double[]{0.9, 0.3};
            case "keystrokes" -> new double[]{0.13, 0.72};
            case "pingTPS" -> new double[]{0.5, 0.34};
            case "clocks" -> new double[]{0.88, 0.06};
            case "dayLight" -> new double[]{0.72, 0.06};
            case "speedometer" -> new double[]{0.5, 0.92};
            case "statusPills" -> new double[]{0.5, 0.55};
            case "minimap" -> new double[]{0.86, 0.2};
            case "lightLevel" -> new double[]{0.5, 0.40};
            default -> new double[]{0.5, 0.05}; // fpsPill
        };
    }

    /** Default per-kind {@code options} map (order = display order). */
    public static Map<String, Object> defaultOptions(String kind) {
        Map<String, Object> m = new LinkedHashMap<>();
        switch (kind) {
            case "fpsPill" -> {
                m.put("showFPS", true); m.put("showFrameTime", true);
                m.put("showMinAvg", true); m.put("showMemory", false);
                m.put("showChunks", false); m.put("layout", "compact");
            }
            case "coordsCompass" -> {
                m.put("showFacing", true); m.put("showBiome", true);
                m.put("showNether", false); m.put("layout", "single");
            }
            case "netherCoords" -> {
                m.put("showOverworld", true); m.put("showNether", true);
            }
            case "armorDurability" -> {
                m.put("layout", "horizontal"); m.put("valueMode", "percent");
                m.put("lowWarn", true);
            }
            case "potionEffects" -> {
                m.put("maxEffects", 5.0); m.put("showDuration", true);
            }
            case "keystrokes" -> {
                m.put("showCPS", true); m.put("showMouse", true);
                m.put("showSprint", true); m.put("showShift", true);
                m.put("animationSpeed", 1.0); m.put("pressedColor", "#0A84FF");
            }
            case "minimap" -> {
                m.put("shape", "circle"); m.put("zoom", 1.0);
                m.put("showPlayers", true); m.put("showMobs", false);
                m.put("deathWaypoint", true); m.put("northLock", false);
            }
            case "pingTPS" -> m.put("showTPS", true);
            case "clocks" -> {
                m.put("showMacClock", true); m.put("showDayCounter", true);
            }
            case "dayLight" -> m.put("showLight", true);
            case "speedometer" -> m.put("unit", "bps");
            case "statusPills" -> {
                m.put("showSprint", true); m.put("showSneak", true);
            }
            case "lightLevel" -> {
                m.put("showSky", true); m.put("showBlock", true);
            }
            default -> { }
        }
        return m;
    }

    // ------------------------------------------------------------------
    // Parsing (tolerant — every accessor has a fallback)
    // ------------------------------------------------------------------

    public static HudState parse(String json) {
        HudState s = new HudState();
        try {
            JsonObject root = JsonParser.parseString(json).getAsJsonObject();
            s.format = str(root, "format", FORMAT);
            s.version = (int) num(root, "version", VERSION);
            s.updatedAt = str(root, "updatedAt", "");
            s.activeProfile = str(root, "activeProfile", "default");

            JsonObject uiEl = obj(root, "ui");
            if (uiEl != null) parseUi(uiEl, s.ui);

            JsonElement profilesEl = root.get("profiles");
            if (profilesEl != null && profilesEl.isJsonArray()) {
                for (JsonElement el : profilesEl.getAsJsonArray()) {
                    HudProfile p = parseProfile(el);
                    if (p != null) s.profiles.add(p);
                }
            }
            if (s.profiles.isEmpty()) {
                // Legacy v2 layout: flat top-level "widgets" array.
                JsonElement widgetsEl = root.get("widgets");
                if (widgetsEl != null && widgetsEl.isJsonArray()) {
                    HudProfile p = new HudProfile();
                    p.id = "default";
                    p.name = "Default Apple";
                    for (JsonElement el : widgetsEl.getAsJsonArray()) {
                        HudWidget w = parseWidget(el, true);
                        if (w != null) p.widgets.add(w);
                    }
                    if (!p.widgets.isEmpty()) s.profiles.add(p);
                }
            }
            if (s.profiles.isEmpty()) {
                s.profiles = defaultState().profiles;
            }
            boolean found = false;
            for (HudProfile p : s.profiles) if (p.id.equals(s.activeProfile)) found = true;
            if (!found) s.activeProfile = s.profiles.get(0).id;
        } catch (Exception e) {
            // Completely malformed document — keep defaults.
            return defaultState();
        }
        return s;
    }

    private static HudProfile parseProfile(JsonElement el) {
        if (el == null || !el.isJsonObject()) return null;
        JsonObject o = el.getAsJsonObject();
        HudProfile p = new HudProfile();
        p.id = str(o, "id", "profile-" + UUID.randomUUID());
        p.name = str(o, "name", p.id);
        JsonElement ws = o.get("widgets");
        if (ws != null && ws.isJsonArray()) {
            for (JsonElement wel : ws.getAsJsonArray()) {
                HudWidget w = parseWidget(wel, false);
                if (w != null) p.widgets.add(w);
            }
        }
        return p;
    }

    private static HudWidget parseWidget(JsonElement el, boolean legacy) {
        if (el == null || !el.isJsonObject()) return null;
        JsonObject o = el.getAsJsonObject();
        HudWidget w = new HudWidget();
        w.id = str(o, "id", UUID.randomUUID().toString());
        String kind = str(o, "kind", "");
        if (kind.isEmpty()) return null;
        w.kind = kind;
        double[] d = defaultAnchor(kind);
        w.x = clamp01(num(o, "x", d[0]));
        w.y = clamp01(num(o, "y", d[1]));
        w.scale = clamp(num(o, "scale", 1.0), 0.25, 4.0);
        w.visible = bool(o, "visible", true);
        w.containerStyle = str(o, "containerStyle", "neocraft");
        w.fontStyle = str(o, "fontStyle", "apple");
        w.textStyle = str(o, "textStyle", "regular");
        w.colorMode = str(o, "colorMode", "static");
        w.textColor = str(o, "textColor", "#FFFFFF");
        // Legacy v2: "colorHex" feeds accentColor when accentColor absent.
        w.accentColor = str(o, "accentColor", str(o, "colorHex", "#0A84FF"));
        w.borderColor = str(o, "borderColor", "#FFFFFF");
        w.backgroundOpacity = clamp(num(o, "backgroundOpacity", 0.45), 0.0, 1.0);
        JsonElement opts = o.get("options");
        if (opts != null && opts.isJsonObject()) {
            w.options = new LinkedHashMap<>();
            for (Map.Entry<String, JsonElement> e : opts.getAsJsonObject().entrySet()) {
                JsonElement v = e.getValue();
                if (v == null || v.isJsonNull()) continue;
                if (v.isJsonPrimitive()) {
                    JsonPrimitive prim = v.getAsJsonPrimitive();
                    if (prim.isBoolean()) w.options.put(e.getKey(), prim.getAsBoolean());
                    else if (prim.isNumber()) w.options.put(e.getKey(), prim.getAsDouble());
                    else w.options.put(e.getKey(), prim.getAsString());
                } else {
                    w.options.put(e.getKey(), v.toString());
                }
            }
        }
        // Fill in any option defaults the document omitted.
        for (Map.Entry<String, Object> e : defaultOptions(kind).entrySet()) {
            w.options.putIfAbsent(e.getKey(), e.getValue());
        }
        return w;
    }

    private static void parseUi(JsonObject o, HudUiSettings u) {
        JsonObject c = obj(o, "crosshair");
        if (c != null) {
            u.crosshair.enabled = bool(c, "enabled", true);
            u.crosshair.shape = str(c, "shape", "cross");
            u.crosshair.size = (int) num(c, "size", 8);
            u.crosshair.thickness = (int) num(c, "thickness", 2);
            u.crosshair.gap = (int) num(c, "gap", 2);
            u.crosshair.colorMode = str(c, "colorMode", "static");
            u.crosshair.color = str(c, "color", "#FFFFFF");
            u.crosshair.showCooldown = bool(c, "showCooldown", true);
        }
        JsonObject h = obj(o, "hotbar");
        if (h != null) {
            u.hotbar.glassBackground = bool(h, "glassBackground", true);
            u.hotbar.accentColor = str(h, "accentColor", "#0A84FF");
            u.hotbar.xpAccentColor = str(h, "xpAccentColor", "#7CFC00");
            u.hotbar.showNumbers = bool(h, "showNumbers", true);
            u.hotbar.animateSelection = bool(h, "animateSelection", true);
        }
        JsonObject s = obj(o, "scoreboard");
        if (s != null) {
            u.scoreboard.enabled = bool(s, "enabled", true);
            u.scoreboard.scale = clamp(num(s, "scale", 1.0), 0.5, 2.0);
            u.scoreboard.glassBox = bool(s, "glassBox", true);
            u.scoreboard.hideNumbers = bool(s, "hideNumbers", false);
        }
        JsonObject ch = obj(o, "chat");
        if (ch != null) {
            u.chat.enabled = bool(ch, "enabled", true);
            u.chat.roundedBox = bool(ch, "roundedBox", true);
            u.chat.compactTimestamps = bool(ch, "compactTimestamps", true);
            u.chat.opacity = clamp(num(ch, "opacity", 0.6), 0.0, 1.0);
        }
        JsonObject t = obj(o, "titleScreen");
        if (t != null) {
            u.titleScreen.enabled = bool(t, "enabled", true);
            u.titleScreen.tintColor = str(t, "tintColor", "#0A84FF");
            u.titleScreen.opacity = clamp(num(t, "opacity", 0.15), 0.0, 1.0);
        }
    }

    // ------------------------------------------------------------------
    // Serialization
    // ------------------------------------------------------------------

    public static String toJson(HudState s) {
        JsonObject root = new JsonObject();
        root.addProperty("format", s.format == null ? FORMAT : s.format);
        root.addProperty("version", s.version <= 0 ? VERSION : s.version);
        root.addProperty("updatedAt", s.updatedAt == null || s.updatedAt.isEmpty()
                ? Instant.now().toString() : s.updatedAt);
        root.addProperty("activeProfile", s.activeProfile);

        JsonArray profiles = new JsonArray();
        for (HudProfile p : s.profiles) profiles.add(profileToJson(p));
        root.add("profiles", profiles);
        root.add("ui", uiToJson(s.ui));
        return GSON.toJson(root);
    }

    private static JsonObject profileToJson(HudProfile p) {
        JsonObject o = new JsonObject();
        o.addProperty("id", p.id);
        o.addProperty("name", p.name);
        JsonArray ws = new JsonArray();
        for (HudWidget w : p.widgets) ws.add(widgetToJson(w));
        o.add("widgets", ws);
        return o;
    }

    private static JsonObject widgetToJson(HudWidget w) {
        JsonObject o = new JsonObject();
        o.addProperty("id", w.id);
        o.addProperty("kind", w.kind);
        o.addProperty("x", round4(w.x));
        o.addProperty("y", round4(w.y));
        o.addProperty("scale", round4(w.scale));
        o.addProperty("visible", w.visible);
        o.addProperty("containerStyle", w.containerStyle);
        o.addProperty("fontStyle", w.fontStyle);
        o.addProperty("textStyle", w.textStyle);
        o.addProperty("colorMode", w.colorMode);
        o.addProperty("textColor", w.textColor);
        o.addProperty("accentColor", w.accentColor);
        o.addProperty("borderColor", w.borderColor);
        o.addProperty("backgroundOpacity", round4(w.backgroundOpacity));
        if (w.options != null && !w.options.isEmpty()) {
            JsonObject opts = new JsonObject();
            for (Map.Entry<String, Object> e : w.options.entrySet()) {
                Object v = e.getValue();
                if (v instanceof Boolean b) opts.addProperty(e.getKey(), b);
                else if (v instanceof Number n) opts.addProperty(e.getKey(), n);
                else opts.addProperty(e.getKey(), String.valueOf(v));
            }
            o.add("options", opts);
        }
        return o;
    }

    private static JsonObject uiToJson(HudUiSettings u) {
        JsonObject root = new JsonObject();
        JsonObject c = new JsonObject();
        c.addProperty("enabled", u.crosshair.enabled);
        c.addProperty("shape", u.crosshair.shape);
        c.addProperty("size", u.crosshair.size);
        c.addProperty("thickness", u.crosshair.thickness);
        c.addProperty("gap", u.crosshair.gap);
        c.addProperty("colorMode", u.crosshair.colorMode);
        c.addProperty("color", u.crosshair.color);
        c.addProperty("showCooldown", u.crosshair.showCooldown);
        root.add("crosshair", c);

        JsonObject h = new JsonObject();
        h.addProperty("glassBackground", u.hotbar.glassBackground);
        h.addProperty("accentColor", u.hotbar.accentColor);
        h.addProperty("xpAccentColor", u.hotbar.xpAccentColor);
        h.addProperty("showNumbers", u.hotbar.showNumbers);
        h.addProperty("animateSelection", u.hotbar.animateSelection);
        root.add("hotbar", h);

        JsonObject s = new JsonObject();
        s.addProperty("enabled", u.scoreboard.enabled);
        s.addProperty("scale", round4(u.scoreboard.scale));
        s.addProperty("glassBox", u.scoreboard.glassBox);
        s.addProperty("hideNumbers", u.scoreboard.hideNumbers);
        root.add("scoreboard", s);

        JsonObject ch = new JsonObject();
        ch.addProperty("enabled", u.chat.enabled);
        ch.addProperty("roundedBox", u.chat.roundedBox);
        ch.addProperty("compactTimestamps", u.chat.compactTimestamps);
        ch.addProperty("opacity", round4(u.chat.opacity));
        root.add("chat", ch);

        JsonObject t = new JsonObject();
        t.addProperty("enabled", u.titleScreen.enabled);
        t.addProperty("tintColor", u.titleScreen.tintColor);
        t.addProperty("opacity", round4(u.titleScreen.opacity));
        root.add("titleScreen", t);
        return root;
    }

    // ------------------------------------------------------------------
    // Load / save / watch
    // ------------------------------------------------------------------

    /** Loads the config file; keeps current state on any failure. */
    public static void load() {
        try {
            if (!Files.exists(CONFIG_PATH)) return;
            String json;
            try (Reader r = Files.newBufferedReader(CONFIG_PATH, StandardCharsets.UTF_8)) {
                json = readAll(r);
            }
            state = parse(json);
            lastModified = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
        } catch (IOException ignored) { }
    }

    /** Writes the default document so the launcher/editor always has a file. */
    public static void ensureExists() {
        try {
            if (CONFIG_PATH.getParent() != null) Files.createDirectories(CONFIG_PATH.getParent());
            if (!Files.exists(CONFIG_PATH)) saveNow();
        } catch (IOException ignored) { }
    }

    /** Immediately and atomically writes the current state to disk. */
    public static void saveNow() {
        synchronized (SAVE_LOCK) {
            try {
                if (CONFIG_PATH.getParent() != null) Files.createDirectories(CONFIG_PATH.getParent());
                String json = toJson(state);
                try (Writer w = Files.newBufferedWriter(TMP_PATH, StandardCharsets.UTF_8)) {
                    w.write(json);
                }
                try {
                    Files.move(TMP_PATH, CONFIG_PATH, StandardCopyOption.ATOMIC_MOVE,
                            StandardCopyOption.REPLACE_EXISTING);
                } catch (IOException e) {
                    Files.move(TMP_PATH, CONFIG_PATH, StandardCopyOption.REPLACE_EXISTING);
                }
                lastModified = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
            } catch (IOException ignored) { }
        }
    }

    /** Debounced save — call after every in-game edit. */
    public static void requestSave() {
        synchronized (SAVE_LOCK) {
            if (saver == null) {
                saver = Executors.newSingleThreadScheduledExecutor(r -> {
                    Thread t = new Thread(r, "neocraft-hud-config-saver");
                    t.setDaemon(true);
                    return t;
                });
            }
            if (pendingSave != null) pendingSave.cancel(false);
            pendingSave = saver.schedule(HudConfig::saveNow, SAVE_DEBOUNCE_MS, TimeUnit.MILLISECONDS);
        }
    }

    /** Polls lastModified once per second and hot-reloads external edits. */
    public static void startWatcher() {
        if (!watcherRunning.compareAndSet(false, true)) return;
        Thread t = new Thread(() -> {
            while (true) {
                try {
                    Thread.sleep(1000L);
                    if (!Files.exists(CONFIG_PATH)) continue;
                    long mod = Files.getLastModifiedTime(CONFIG_PATH).toMillis();
                    if (mod != lastModified) {
                        lastModified = mod;
                        load();
                    }
                } catch (InterruptedException e) {
                    return;
                } catch (IOException ignored) { }
            }
        }, "neocraft-hud-config-watcher");
        t.setDaemon(true);
        t.start();
    }

    // ------------------------------------------------------------------
// Small tolerant-accessor helpers
    // ------------------------------------------------------------------

    private static JsonObject obj(JsonObject o, String key) {
        JsonElement e = o.get(key);
        return e != null && e.isJsonObject() ? e.getAsJsonObject() : null;
    }

    private static String str(JsonObject o, String key, String def) {
        JsonElement e = o.get(key);
        if (e == null || e.isJsonNull() || !e.isJsonPrimitive()) return def;
        String s = e.getAsString();
        return s == null || s.isEmpty() ? def : s;
    }

    private static double num(JsonObject o, String key, double def) {
        JsonElement e = o.get(key);
        if (e == null || e.isJsonNull() || !e.isJsonPrimitive()) return def;
        try {
            if (e.getAsJsonPrimitive().isNumber()) return e.getAsDouble();
            return Double.parseDouble(e.getAsString());
        } catch (Exception ex) {
            return def;
        }
    }

    private static boolean bool(JsonObject o, String key, boolean def) {
        JsonElement e = o.get(key);
        if (e == null || e.isJsonNull() || !e.isJsonPrimitive()) return def;
        JsonPrimitive p = e.getAsJsonPrimitive();
        if (p.isBoolean()) return p.getAsBoolean();
        if (p.isNumber()) return p.getAsDouble() != 0;
        return Boolean.parseBoolean(p.getAsString());
    }

    private static double clamp01(double v) { return clamp(v, 0.0, 1.0); }

    private static double clamp(double v, double lo, double hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    private static double round4(double v) {
        return Math.round(v * 10000.0) / 10000.0;
    }

    private static String readAll(Reader r) throws IOException {
        StringBuilder sb = new StringBuilder(8192);
        char[] buf = new char[4096];
        int n;
        while ((n = r.read(buf)) != -1) sb.append(buf, 0, n);
        return sb.toString();
    }

    // ------------------------------------------------------------------
    // Color helpers (shared with the renderer)
    // ------------------------------------------------------------------

    /** Parses "#RRGGBB" / "#AARRGGBB" / "RRGGBB" into an ARGB int. */
    public static int parseColor(String hex, int fallback) {
        if (hex == null || hex.isEmpty()) return fallback;
        try {
            String h = hex.startsWith("#") ? hex.substring(1) : hex;
            long v = Long.parseLong(h, 16);
            if (h.length() == 6) return (int) (0xFF000000L | v);
            // 8 digits are interpreted as AARRGGBB.
            return (int) v;
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** Formats an ARGB int as "#RRGGBB". */
    public static String formatColor(int argb) {
        return String.format("#%06X", argb & 0xFFFFFF);
    }
}
