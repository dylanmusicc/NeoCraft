package com.neocraft.ui;

import com.google.gson.JsonObject;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.PlainTextButton;
import net.minecraft.client.gui.screens.ConnectScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.advancements.AdvancementsScreen;
import net.minecraft.client.gui.screens.options.OptionsScreen;
import net.minecraft.client.gui.screens.options.VideoSettingsScreen;
import net.minecraft.client.Screenshot;
import net.minecraft.client.multiplayer.ServerData;
import net.minecraft.client.multiplayer.resolver.ServerAddress;
import net.minecraft.network.chat.Component;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

/**
 * The NeoCraft in-game menu — opened with <b>N</b>, the "NeoCraft" button
 * on the title/pause screens, or from Neo Studio-driven flows.
 *
 * <p>Styled after the launcher: launcher-synced accent/glow colors,
 * rounded panels, a sidebar tab rail and NeoCraft wordmark. Four tabs:</p>
 * <ul>
 *   <li><b>Servers</b> — hosted worlds via the NeoCraft bridge (host,
 *   start/stop/restart, copy address, join) even when the beta host mod
 *   is off.</li>
 *   <li><b>Design</b> — the {@code neocraft_ui.json} theme editor
 *   (same document Neo Studio writes).</li>
 *   <li><b>HUD</b> — companion-mod status and keybind reference.</li>
 *   <li><b>Tools</b> — quick actions for the game instance.</li>
 * </ul>
 *
 * <p>Chrome (backdrop, panel, sidebar, list rows, scrollbar) is drawn
 * manually, but <b>every interactive element is a real vanilla widget</b>
 * ({@link Button}/{@link PlainTextButton}) added via
 * {@link #addRenderableWidget}. Widgets own their hit-testing, hover
 * state and label clipping, so clicks can never drift from what is
 * drawn — the previous hand-rolled hit-region approach is gone.</p>
 */
public class NeoCraftMenuScreen extends Screen {

    private enum Tab { SERVERS, DESIGN, HUD, TOOLS }

    private static final int PANEL_W = 720;
    private static final int PANEL_H = 440;
    private static final int SIDEBAR_W = 136;
    private static final int ROW_H = 22;
    private static final int ACCENT_FALLBACK = 0xFF5B8CFF;

    private static final int TYPE_HEADER = 1;
    private static final int TYPE_SERVER = 2;
    private static final int TYPE_WORLD = 3;

    private record Row(int type, JsonObject data, String label) { }

    private Tab tab = Tab.SERVERS;
    private final List<Row> rows = new ArrayList<>();
    private double scroll;
    private long lastBridgeVersion = -1;
    private boolean lastBridgeAvailable;
    private int panelX, panelY, panelW, panelH;
    private int contentX, contentY, contentW, contentH;
    private int mouseX, mouseY;
    /** Screen to return to on close — the title/pause screen that opened
     *  the menu, or {@code null} when opened via the N keybind in-game. */
    private final Screen parent;

    public NeoCraftMenuScreen() {
        this(null);
    }

    public NeoCraftMenuScreen(Screen parent) {
        super(Component.literal("NeoCraft"));
        this.parent = parent;
    }

    // ------------------------------------------------------------------
    // Palette helpers — launcher-synced accent + glow
    // ------------------------------------------------------------------

    private int accent() { return UiConfig.chromeAccentColor(ACCENT_FALLBACK); }
    private int glow() { return UiConfig.chromeGlowColor(accent()); }
    private int rgb(int argb) { return argb & 0x00FFFFFF; }
    private int withAlpha(int argb, int alpha) { return (alpha << 24) | rgb(argb); }

    private int panelBg() { return 0xF210141D; }
    private int panelBorder() { return withAlpha(accent(), 0x55); }
    private int sidebarBg() { return 0x99101824; }
    private int rowHover() { return 0x22FFFFFF; }
    private int textPrimary() { return 0xFFF2F5FA; }
    private int textSecondary() { return 0xFF9AA7B8; }
    private int textFaint() { return 0xFF6B7A90; }

    // ------------------------------------------------------------------
    // Layout / widgets
    // ------------------------------------------------------------------

    @Override
    protected void init() {
        panelW = Math.min(PANEL_W, Math.max(360, width - 48));
        panelH = Math.min(PANEL_H, Math.max(280, height - 48));
        panelX = (width - panelW) / 2;
        panelY = (height - panelH) / 2;
        contentX = panelX + SIDEBAR_W;
        contentY = panelY;
        contentW = panelW - SIDEBAR_W;
        contentH = panelH;
        scroll = 0;
        rebuildRows();
        rebuildMenuWidgets();
    }

    private void switchTab(Tab next) {
        if (tab == next) return;
        tab = next;
        scroll = 0;
        rebuildRows();
        rebuildMenuWidgets();
    }

    /** (Re)builds the row model for the Servers tab. */
    private void rebuildRows() {
        // Track the version even on early returns — otherwise a tab
        // switch or an offline bridge leaves lastBridgeVersion stale and
        // extractBackground rebuilds every frame.
        lastBridgeVersion = NeoCraftBridge.version();
        rows.clear();
        if (tab != Tab.SERVERS || !NeoCraftBridge.isAvailable()) return;

        List<JsonObject> servers = NeoCraftBridge.servers();
        rows.add(new Row(TYPE_HEADER, null, "HOSTED SERVERS"));
        if (servers.isEmpty()) {
            rows.add(new Row(TYPE_HEADER, null, "  none yet — host a world below"));
        }
        for (JsonObject server : servers) {
            rows.add(new Row(TYPE_SERVER, server, null));
        }

        List<JsonObject> worlds = NeoCraftBridge.worlds();
        rows.add(new Row(TYPE_HEADER, null, "WORLDS — HOST AS SERVER"));
        if (worlds.isEmpty()) {
            rows.add(new Row(TYPE_HEADER, null, "  no worlds found in this instance"));
        }
        for (JsonObject world : worlds) {
            rows.add(new Row(TYPE_WORLD, world, null));
        }
    }

    /** Removes every widget and re-adds the set for the current tab.
     *  Called on init, tab switch, scroll and bridge state changes —
     *  never per-frame. */
    private void rebuildMenuWidgets() {
        clearWidgets();

        // Sidebar tabs — text-only buttons over the custom-drawn rail;
        // the selected pill is painted in renderPanel().
        int tabY = panelY + 64;
        for (Tab t : Tab.values()) {
            final Tab target = t;
            PlainTextButton tabBtn = new PlainTextButton(
                    panelX + 14, tabY, SIDEBAR_W - 28, 20,
                    Component.literal(tabLabel(t)), b -> switchTab(target), this.font);
            addRenderableWidget(tabBtn);
            tabY += 28;
        }

        int cx = contentX + 18;
        int cw = contentW - 36;
        int top = panelY + 44;

        switch (tab) {
            case SERVERS -> buildServerWidgets(cx, cw, top);
            case DESIGN -> buildDesignWidgets(cx, cw, top);
            case HUD -> buildHudWidgets(cx, cw, top);
            case TOOLS -> buildToolsWidgets(cx, cw, top);
        }

        // Footer: Open NeoCraft (offline only) + Done — right aligned.
        int fy = panelY + panelH - 36;
        int doneW = 76;
        int doneX = panelX + panelW - 10 - doneW;
        if (!NeoCraftBridge.isAvailable()) {
            int appW = 104;
            addRenderableWidget(Button.builder(Component.literal("Open NeoCraft"), b -> openApp())
                    .bounds(doneX - 8 - appW, fy, appW, 20).build());
        }
        addRenderableWidget(Button.builder(Component.literal("Done"), b -> onClose())
                .bounds(doneX, fy, doneW, 20).build());
    }

    private static String tabLabel(Tab t) {
        return switch (t) {
            case SERVERS -> "Servers";
            case DESIGN -> "Design";
            case HUD -> "HUD";
            case TOOLS -> "Tools";
        };
    }

    // -- Servers tab ----------------------------------------------------

    /** True while the bridge answered with an error worth showing under
     *  the subtitle — the list shifts down so the message never
     *  overlaps the first row. */
    private boolean showBridgeError() {
        return NeoCraftBridge.isAvailable() && !NeoCraftBridge.lastError().isEmpty();
    }

    private int serversListTop() {
        return panelY + 44 + (showBridgeError() ? 56 : 26);
    }

    private int serversListBottom() {
        return panelY + panelH - 46;
    }

    private int serversVisibleRows() {
        return Math.max(0, (serversListBottom() - serversListTop()) / ROW_H);
    }

    /** A positioned button inside a server/world list row. Produced by
     *  {@link #rowButtons} and consumed by both widget creation and the
     *  text clipping math, so clicks can never drift from what is
     *  drawn. */
    private record RowButton(int x, int w, int y, String label,
                             Runnable action, Supplier<Boolean> enabled) { }

    private static final int ROW_BTN_H = 18;
    private static final int ROW_BTN_GAP = 4;
    private static final int ROW_RIGHT_MARGIN = 6;

    /**
     * Right-aligned button cluster for one list row. Button widths are
     * measured from their labels and the whole cluster is laid out from
     * the row's right edge inward — the text area is whatever remains,
     * so buttons can never overlap the label at any panel width.
     *
     * <p>Specs are authored left→right; positioning walks right→left.</p>
     */
    private List<RowButton> rowButtons(Row row, int ry, int right, int cw) {
        record Spec(String label, Runnable action,
                    Supplier<Boolean> enabled) { }
        List<Spec> specs = new ArrayList<>();

        switch (row.type()) {
            case TYPE_SERVER -> {
                JsonObject server = row.data();
                boolean running = server.has("running") && server.get("running").getAsBoolean();
                boolean settingUp = server.has("settingUp") && server.get("settingUp").getAsBoolean();
                final String startLabel = running ? "Stop" : (settingUp ? "…" : "Start");
                // Left→right visual order: Join · ↻ · IP · Start/Stop.
                specs.add(new Spec("Join", () -> joinServer(server), () -> running));
                // Narrow rows drop the secondary actions so the cluster
                // never pushes into the sidebar divider.
                if (cw >= 240) {
                    specs.add(new Spec("↻",
                            () -> NeoCraftBridge.sendQuiet("restart", NeoCraftBridge.serverParams(server)),
                            () -> running));
                }
                specs.add(new Spec("IP", () -> copyAddress(server), () -> true));
                specs.add(new Spec(startLabel, () -> {
                    NeoCraftBridge.sendQuiet(running ? "stop" : "start",
                            NeoCraftBridge.serverParams(server));
                    NeoCraftBridge.poll();
                }, () -> !settingUp || running));
            }
            case TYPE_WORLD -> {
                JsonObject world = row.data();
                specs.add(new Spec("Dir", () -> openWorldFolder(world), () -> true));
                if (!NeoCraftBridge.worldAlreadyHosted(NeoCraftBridge.worldKey(world))) {
                    specs.add(new Spec("Host", () -> hostWorld(world), () -> true));
                }
            }
            default -> { }
        }

        int n = specs.size();
        int[] widths = new int[n];
        int total = ROW_RIGHT_MARGIN;
        for (int i = 0; i < n; i++) {
            widths[i] = Math.max(30, this.font.width(specs.get(i).label()) + 12);
            total += widths[i] + (i > 0 ? ROW_BTN_GAP : 0);
        }
        // If the cluster would leave less than ~60 px for the label,
        // shrink the buttons proportionally instead of overlapping.
        if (total > cw - 60) {
            float f = (cw - 60f) / total;
            for (int i = 0; i < n; i++) widths[i] = Math.max(24, (int) (widths[i] * f));
        }

        List<RowButton> out = new ArrayList<>(n);
        int x = right - ROW_RIGHT_MARGIN;
        for (int i = n - 1; i >= 0; i--) {
            Spec s = specs.get(i);
            x -= widths[i];
            out.add(0, new RowButton(x, widths[i], ry + 1, s.label(),
                    s.action(), s.enabled()));
            x -= ROW_BTN_GAP;
        }
        return out;
    }

    /** X coordinate where a row's text must end so it never touches the
     *  button cluster (or the row's right padding when there are none). */
    private int rowTextRight(Row row, int ry, int right, int cw) {
        List<RowButton> btns = rowButtons(row, ry, right, cw);
        return btns.isEmpty() ? right - 8 : btns.get(0).x - 8;
    }

    private void buildServerWidgets(int cx, int cw, int top) {
        if (!NeoCraftBridge.isAvailable()) {
            addRenderableWidget(Button.builder(Component.literal("Retry"), b -> retryBridge())
                    .bounds(cx, top + 96, 70, 20).build());
            return;
        }
        int listTop = serversListTop();
        int listBottom = serversListBottom();
        int visible = serversVisibleRows();
        int start = (int) Math.floor(scroll);
        int right = cx + cw;
        for (int i = start; i < Math.min(rows.size(), start + visible); i++) {
            Row row = rows.get(i);
            int ry = listTop + (i - start) * ROW_H;
            if (ry + ROW_H > listBottom) break;
            for (RowButton b : rowButtons(row, ry, right, cw)) {
                Button btn = Button.builder(Component.literal(b.label()), bb -> b.action().run())
                        .bounds(b.x, b.y, b.w, ROW_BTN_H + 2)
                        .build();
                btn.active = b.enabled().get();
                addRenderableWidget(btn);
            }
        }
    }

    // -- Design tab -----------------------------------------------------

    private void buildDesignWidgets(int cx, int cw, int top) {
        int y = top + 34;
        int pitch = panelH < 360 ? 24 : 28;

        addRenderableWidget(designToggle(cx, cw, y, "NeoCraft UI",
                () -> UiConfig.state().enabled,
                v -> UiConfig.update(u -> u.enabled = v)));
        y += pitch;
        addRenderableWidget(designToggle(cx, cw, y, "Full redesign",
                () -> UiConfig.state().fullRedesign,
                v -> UiConfig.update(u -> u.fullRedesign = v)));
        y += pitch + 8;

        // Accent — cycles through the launcher presets.
        addRenderableWidget(Button.builder(
                        Component.literal("Accent: " + UiConfig.state().accentColor + "  ›"),
                        b -> {
                            UiConfig.update(u -> {
                                int idx = indexOfPreset(u.accentColor);
                                String next = UiConfig.ACCENT_PRESETS[(idx + 1) % UiConfig.ACCENT_PRESETS.length];
                                u.accentColor = next;
                                u.tintColor = next;
                            });
                            rebuildMenuWidgets();
                        })
                .bounds(cx, y, cw, 20).build());
        y += pitch;

        // Tint opacity — label shows the value, − / + step it.
        int tintW = Math.max(80, cw - 72);
        Button tintLabel = Button.builder(
                        Component.literal("Tint opacity: " + Math.round(UiConfig.state().tintOpacity * 100) + "%"),
                        b -> { })
                .bounds(cx, y, tintW, 20).build();
        tintLabel.active = false;
        addRenderableWidget(tintLabel);
        Button tintMinus = Button.builder(Component.literal("−"), b -> {
                    UiConfig.update(u -> u.tintOpacity = clamp(u.tintOpacity - 0.02));
                    rebuildMenuWidgets();
                }).bounds(cx + tintW + 4, y, 32, 20).build();
        tintMinus.active = UiConfig.state().tintOpacity > 0.01;
        Button tintPlus = Button.builder(Component.literal("+"), b -> {
                    UiConfig.update(u -> u.tintOpacity = clamp(u.tintOpacity + 0.02));
                    rebuildMenuWidgets();
                }).bounds(cx + tintW + 40, y, 32, 20).build();
        tintPlus.active = UiConfig.state().tintOpacity < 0.59;
        addRenderableWidget(tintMinus);
        addRenderableWidget(tintPlus);
        y += pitch + 8;

        // Per-screen toggles live in the detailed editor — keep the menu
        // slim so nothing can overflow on small panels.
        addRenderableWidget(Button.builder(Component.literal("Detailed editor…"), b ->
                        Minecraft.getInstance().gui.setScreen(new NeoCraftUIConfigScreen()))
                .bounds(cx, y, 150, 20).build());
    }

    private Button designToggle(int cx, int cw, int y, String label,
                                Supplier<Boolean> getter,
                                java.util.function.Consumer<Boolean> setter) {
        Button btn = Button.builder(
                        Component.literal(label + ": " + (getter.get() ? "ON" : "off")),
                        b -> {
                            setter.accept(!getter.get());
                            rebuildMenuWidgets();
                        })
                .bounds(cx, y, cw, 20).build();
        return btn;
    }

    private static int indexOfPreset(String color) {
        for (int i = 0; i < UiConfig.ACCENT_PRESETS.length; i++) {
            if (UiConfig.ACCENT_PRESETS[i].equalsIgnoreCase(color)) return i;
        }
        return 0;
    }

    // -- HUD tab --------------------------------------------------------

    private void buildHudWidgets(int cx, int cw, int top) {
        if (!hudModLoaded()) return;
        // Bottom-anchored so the actions stay clear of the footer on
        // short panels; on tall panels they sit right under the text.
        int y = Math.max(top + 176, panelY + panelH - 34 - 20 - 6 - 26 - 20 - 8);
        int pairW = Math.max(60, (cw - 8) / 2);
        addRenderableWidget(Button.builder(Component.literal("Open HUD editor"), b -> openHudEditor())
                .bounds(cx, y, pairW, 20).build());
        addRenderableWidget(Button.builder(Component.literal("Reload HUD config"), b -> reloadHudConfig())
                .bounds(cx + pairW + 8, y, pairW, 20).build());
        addRenderableWidget(Button.builder(Component.literal("Toggle HUD"), b -> toggleHud())
                .bounds(cx, y + 26, pairW, 20).build());
    }

    // -- Tools tab ------------------------------------------------------

    private void buildToolsWidgets(int cx, int cw, int top) {
        int y = top + 34;
        // Two-column grid — falls back to a single column on narrow
        // content areas so labels never get squeezed.
        record Tool(String label, Runnable action) { }
        List<Tool> tools = new ArrayList<>();
        for (int i = 0; i < toolPaths.length; i++) {
            final int idx = i;
            tools.add(new Tool(toolLabels[i], () -> openPath(toolPaths[idx])));
        }
        tools.add(new Tool("Open resourcepacks", () -> openPath("resourcepacks")));
        tools.add(new Tool("Open options", this::openOptions));
        tools.add(new Tool("Open video settings", this::openVideoSettings));
        tools.add(new Tool("Open advancements", this::openAdvancements));
        tools.add(new Tool("Take screenshot", this::takeScreenshot));
        tools.add(new Tool("Open NeoCraft", this::openApp));

        int cols = cw >= 300 ? 2 : 1;
        int gap = 8;
        int w = cols == 2 ? (cw - gap) / 2 : Math.min(280, cw);
        int pitch = 26;
        int h = 20;
        for (int i = 0; i < tools.size(); i++) {
            Tool t = tools.get(i);
            int col = i % cols;
            int row = i / cols;
            addRenderableWidget(Button.builder(Component.literal(t.label()), b -> t.action().run())
                    .bounds(cx + col * (w + gap), y + row * pitch, w, h).build());
        }
    }

    private static final String[] toolLabels = {
            "Open game folder", "Open saves folder",
            "Open screenshots", "Open config folder",
            "Open mods folder", "Open logs folder"
    };

    private static final String[] toolPaths = {
            ".", "saves", "screenshots", "config", "mods", "logs"
    };

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------

    private void hostWorld(JsonObject world) {
        JsonObject params = new JsonObject();
        params.addProperty("worldName", NeoCraftBridge.worldKey(world));
        NeoCraftBridge.send("host", params).whenComplete((response, error) ->
                Minecraft.getInstance().execute(() -> {
                    toast(error != null || response == null || !response.has("ok")
                            || !response.get("ok").getAsBoolean()
                            ? "Host failed: " + NeoCraftBridge.lastError()
                            : "Setting up server — watch NeoCraft for progress");
                    NeoCraftBridge.poll();
                }));
    }

    private void copyAddress(JsonObject server) {
        String address = server.has("address") ? server.get("address").getAsString() : "";
        if (address.isEmpty()) return;
        Minecraft.getInstance().keyboardHandler.setClipboard(address);
        toast("Copied " + address);
    }

    /** Direct-joins a hosted server through the vanilla connect flow —
     *  the NeoCraft menu stays the parent screen, so disconnecting
     *  returns here. */
    private void joinServer(JsonObject server) {
        String name = server.has("name") ? server.get("name").getAsString() : "NeoCraft Server";
        String address = server.has("address") ? server.get("address").getAsString() : "";
        if (address.isEmpty()) {
            toast("Server has no address yet");
            return;
        }
        Minecraft mc = Minecraft.getInstance();
        ConnectScreen.startConnecting(
                this, mc,
                ServerAddress.parseString(address),
                new ServerData(name, address, ServerData.Type.OTHER),
                false, null);
    }

    /** Opens a folder inside the instance's game directory (the process
     *  working directory) in Finder. */
    private void openPath(String relative) {
        try {
            File dir = new File(relative);
            // "mods"/"logs" may not exist yet on a fresh instance —
            // create them so Finder always has something to show.
            if (!dir.isDirectory()) dir.mkdirs();
            new ProcessBuilder("open", dir.getAbsolutePath()).start();
        } catch (Exception e) {
            toast("Couldn't open " + relative + ": " + e.getMessage());
        }
    }

    /** Opens a world's save folder (saves/<levelName>) in Finder — only
     *  when it actually exists, so stale bridge entries can't create
     *  empty directories. */
    private void openWorldFolder(JsonObject world) {
        String name = world.has("levelName") ? world.get("levelName").getAsString()
                : (world.has("name") ? world.get("name").getAsString() : "");
        if (name.isEmpty()) {
            toast("World has no folder name");
            return;
        }
        File dir = new File("saves", name);
        if (!dir.isDirectory()) {
            toast("No save folder for " + name);
            return;
        }
        try {
            new ProcessBuilder("open", dir.getAbsolutePath()).start();
        } catch (Exception e) {
            toast("Couldn't open world folder: " + e.getMessage());
        }
    }

    // -- Vanilla screen shortcuts (Tools tab) --------------------------

    private void openOptions() {
        Minecraft mc = Minecraft.getInstance();
        mc.gui.setScreen(new OptionsScreen(this, mc.options));
    }

    private void openVideoSettings() {
        Minecraft mc = Minecraft.getInstance();
        mc.gui.setScreen(new VideoSettingsScreen(this, mc, mc.options));
    }

    private void openAdvancements() {
        Minecraft mc = Minecraft.getInstance();
        var conn = mc.getConnection();
        if (conn == null || conn.getAdvancements() == null) {
            toast("Advancements need an active world or server");
            return;
        }
        mc.gui.setScreen(new AdvancementsScreen(conn.getAdvancements(), this));
    }

    private void takeScreenshot() {
        Screenshot.grab(Minecraft.getInstance(), false);
    }

    // -- HUD companion-mod helpers (reflection keeps neocraft-ui
    //    independent of the beta neocraft-hud jar) --------------------

    private static boolean hudModLoaded() {
        return FabricLoader.getInstance().isModLoaded("neocraft-hud");
    }

    private void openHudEditor() {
        try {
            Object screen = Class.forName("com.neocraft.hud.NeoCraftHudConfigScreen")
                    .getDeclaredConstructor().newInstance();
            Minecraft.getInstance().gui.setScreen((Screen) screen);
        } catch (Throwable t) {
            toast("HUD editor unavailable");
        }
    }

    private void reloadHudConfig() {
        try {
            Class.forName("com.neocraft.hud.HudConfig").getMethod("load").invoke(null);
            toast("HUD config reloaded");
        } catch (Throwable t) {
            toast("HUD reload failed");
        }
    }

    private boolean hudEnabled() {
        try {
            return (boolean) Class.forName("com.neocraft.hud.NeoCraftHUDClient")
                    .getField("hudEnabled").get(null);
        } catch (Throwable t) {
            return true;
        }
    }

    private void toggleHud() {
        try {
            var field = Class.forName("com.neocraft.hud.NeoCraftHUDClient")
                    .getField("hudEnabled");
            field.setBoolean(null, !hudEnabled());
            toast("HUD " + (hudEnabled() ? "on" : "off"));
        } catch (Throwable t) {
            toast("HUD toggle unavailable");
        }
    }

    private void retryBridge() {
        NeoCraftBridge.poll();
        rebuildRows();
        rebuildMenuWidgets();
    }

    private void openApp() {
        try {
            new ProcessBuilder("open", "-b", "com.neocraft.launcher").start();
        } catch (Exception e) {
            toast("Couldn't open NeoCraft: " + e.getMessage());
        }
    }

    private void toast(String message) {
        try {
            Minecraft.getInstance().gui.chatListener()
                    .handleSystemMessage(Component.literal("[NeoCraft] " + message), false);
        } catch (Throwable ignored) { }
    }

    // ------------------------------------------------------------------
    // Rendering — passive chrome only, no hit-testing here
    // ------------------------------------------------------------------

    @Override
    public void extractBackground(GuiGraphicsExtractor g, int mouseX, int mouseY, float partialTick) {
        // Pick up bridge changes published since the last frame. The
        // availability flag is tracked separately: bridge.version() only
        // advances on fresh state.json parses, so an online→offline
        // transition would otherwise never trigger a rebuild and the
        // panel would keep showing stale rows forever.
        boolean available = NeoCraftBridge.isAvailable();
        if (NeoCraftBridge.version() != lastBridgeVersion || available != lastBridgeAvailable) {
            lastBridgeAvailable = available;
            rebuildRows();
            rebuildMenuWidgets();
        }
        this.mouseX = mouseX;
        this.mouseY = mouseY;
        super.extractBackground(g, mouseX, mouseY, partialTick);

        renderBackdrop(g);
        renderPanel(g, mouseX, mouseY);
        switch (tab) {
            case SERVERS -> renderServers(g, mouseX, mouseY);
            case DESIGN -> renderDesign(g);
            case HUD -> renderHud(g);
            case TOOLS -> renderTools(g);
        }
        renderFooter(g);
    }

    /** Dimmed game + launcher-style accent gradient and wordmark. */
    private void renderBackdrop(GuiGraphicsExtractor g) {
        g.fill(0, 0, width, height, 0xD8080B12);
        int top = withAlpha(accent(), 0x2E);
        int bottom = 0xF0080D16;
        int strips = Math.max(8, height / 6);
        for (int i = 0; i < strips; i++) {
            int y0 = (int) ((long) i * height / strips);
            int y1 = (int) ((long) (i + 1) * height / strips);
            float t = (float) i / (strips - 1);
            g.fill(0, y0, width, y1, lerp(top, bottom, t));
        }
        // Accent bloom at the top, like the launcher aurora.
        int bloomRgb = rgb(glow());
        int bloomH = Math.min(height / 4, 140);
        for (int i = 0; i < bloomH; i += 2) {
            float f = 1f - (float) i / bloomH;
            int a = (int) (0x38 * f * f);
            g.fill(0, i, width, i + 2, (a << 24) | bloomRgb);
        }
    }

    private void renderPanel(GuiGraphicsExtractor g, int mx, int my) {
        int r = UiConfig.cornerRadius();
        roundedFill(g, panelX, panelY, panelW, panelH, r, panelBg());
        // 1px accent-tinted border
        roundedBorder(g, panelX, panelY, panelW, panelH, r, panelBorder());

        // Sidebar
        g.fill(panelX + 1, panelY + r, panelX + SIDEBAR_W - 1, panelY + panelH - r, sidebarBg());
        g.fill(panelX + SIDEBAR_W - 1, panelY + r, panelX + SIDEBAR_W, panelY + panelH - r, panelBorder());

        // Sidebar wordmark
        String mark = "N E O C R A F T";
        int mw = this.font.width(mark);
        int mx0 = panelX + (SIDEBAR_W - mw) / 2;
        g.text(this.font, mark, mx0 + 1, panelY + 16 + 1, 0x66000000);
        g.text(this.font, mark, mx0, panelY + 16, accent());
        g.text(this.font, "in-game menu", panelX + (SIDEBAR_W - this.font.width("in-game menu")) / 2,
                panelY + 30, textFaint());

        // Tab pills — selection/hover only; clicks belong to the
        // PlainTextButton widgets sitting on top.
        int tabY = panelY + 64;
        for (Tab t : Tab.values()) {
            boolean selected = tab == t;
            boolean hover = !selected
                    && mx >= panelX + 14 && mx < panelX + 14 + SIDEBAR_W - 28
                    && my >= tabY && my < tabY + 20;
            if (selected) {
                roundedFill(g, panelX + 14, tabY, SIDEBAR_W - 28, 20, 6, withAlpha(accent(), 0x33));
                g.fill(panelX + 14, tabY + 3, panelX + 17, tabY + 17, accent());
            } else if (hover) {
                roundedFill(g, panelX + 14, tabY, SIDEBAR_W - 28, 20, 6, rowHover());
            }
            tabY += 28;
        }

        // Sidebar footer: bridge status
        String status = NeoCraftBridge.isAvailable()
                ? "bridge online" : "bridge offline";
        int sw = this.font.width(status);
        g.text(this.font, status,
                panelX + (SIDEBAR_W - sw) / 2, panelY + panelH - 22,
                NeoCraftBridge.isAvailable() ? 0xFF63E6A8 : textFaint());
    }

    // -- Servers tab ----------------------------------------------------

    private void renderServers(GuiGraphicsExtractor g, int mx, int my) {
        int cx = contentX + 18;
        int cw = contentW - 36;
        int top = panelY + 44;

        // Tab title
        g.text(this.font, "Servers", cx, top, textPrimary());
        String sub = NeoCraftBridge.isAvailable()
                ? "Bridge online · " + NeoCraftBridge.instanceName()
                : "Bridge offline — start the game through NeoCraft to manage hosted servers in-game.";
        drawWrapped(g, clip(sub, cw), cx, top + 14, cw, textSecondary());
        if (showBridgeError()) {
            g.text(this.font, clip(NeoCraftBridge.lastError(), cw), cx, top + 40, 0xFFFF8A8A);
        }

        if (!NeoCraftBridge.isAvailable()) {
            g.text(this.font, "The NeoCraft bridge lives in config/neocraft_bridge/ and is",
                    cx, top + 66, textFaint());
            g.text(this.font, "written while NeoCraft runs this instance.",
                    cx, top + 78, textFaint());
            return;
        }

        int listTop = serversListTop();
        int listBottom = serversListBottom();
        int visible = serversVisibleRows();
        int start = (int) Math.floor(scroll);
        int right = cx + cw;
        for (int i = start; i < Math.min(rows.size(), start + visible); i++) {
            Row row = rows.get(i);
            int ry = listTop + (i - start) * ROW_H;
            if (row.type() == TYPE_HEADER) {
                g.text(this.font, row.label(), cx, ry + 7,
                        row.label().startsWith("  ") ? textFaint() : accent());
                continue;
            }
            if (ry + ROW_H > listBottom) break;
            String text;
            int color = 0xFFCBD5E1;
            if (row.type() == TYPE_SERVER) {
                JsonObject s = row.data();
                String name = s.has("name") ? s.get("name").getAsString() : "?";
                String address = s.has("address") ? s.get("address").getAsString() : "";
                String state;
                if (s.has("settingUp") && s.get("settingUp").getAsBoolean()) {
                    state = "setting up"; color = 0xFFFFC861;
                } else if (s.has("running") && s.get("running").getAsBoolean()) {
                    state = s.has("ready") && s.get("ready").getAsBoolean() ? "online" : "starting";
                    color = 0xFF63E6A8;
                } else {
                    state = "stopped"; color = textSecondary();
                }
                if (s.has("playersSeen") && s.get("playersSeen").getAsInt() > 0) {
                    state += " · " + s.get("playersSeen").getAsInt() + " players";
                }
                text = name + "  ·  " + address + "  ·  " + state;
            } else {
                JsonObject w = row.data();
                String name = w.has("levelName") ? w.get("levelName").getAsString()
                        : (w.has("name") ? w.get("name").getAsString() : "?");
                boolean hosted = NeoCraftBridge.worldAlreadyHosted(NeoCraftBridge.worldKey(w));
                text = name + (hosted ? "  (already hosted)" : "");
            }
            // subtle row hover — stops before the action buttons
            if (mx >= cx && mx < right - 60 && my >= ry && my < ry + ROW_H) {
                roundedFill(g, cx - 6, ry, cw + 6, ROW_H, 5, rowHover());
            }
            // Clip against the actual button cluster edge — the same
            // rowButtons() layout the widgets were built from.
            int textRight = rowTextRight(row, ry, right, cw);
            g.text(this.font, clip(text, Math.max(20, textRight - cx)), cx, ry + 7, color);
        }

        // Scrollbar hint
        if (rows.size() * ROW_H > (listBottom - listTop)) {
            int trackH = listBottom - listTop;
            int thumbH = Math.max(16, trackH * trackH / (rows.size() * ROW_H));
            int maxScroll = Math.max(1, rows.size() - visible);
            int thumbY = listTop + (int) ((trackH - thumbH) * (scroll / maxScroll));
            g.fill(panelX + panelW - 7, thumbY, panelX + panelW - 5, thumbY + thumbH, withAlpha(accent(), 0x66));
        }
    }

    // -- Design tab -----------------------------------------------------

    private void renderDesign(GuiGraphicsExtractor g) {
        int cx = contentX + 18;
        int cw = contentW - 36;
        int top = panelY + 44;

        g.text(this.font, "Design", cx, top, textPrimary());
        g.text(this.font, "Writes config/neocraft_ui.json — Neo Studio edits the same file.",
                cx, top + 14, textFaint());
        g.text(this.font, "Per-screen toggles are in the detailed editor.",
                cx, panelY + panelH - 52, textFaint());
    }

    // -- HUD tab --------------------------------------------------------

    private void renderHud(GuiGraphicsExtractor g) {
        int cx = contentX + 18;
        int cw = contentW - 36;
        int top = panelY + 44;

        g.text(this.font, "HUD", cx, top, textPrimary());
        g.text(this.font, "Companion mods detected by Fabric Loader:", cx, top + 14, textSecondary());

        String[] mods = {"neocraft-hud", "neocraft-host", "neocraft-ui"};
        int y = top + 32;
        for (String id : mods) {
            boolean loaded = FabricLoader.getInstance().isModLoaded(id);
            g.fill(cx + 2, y + 4, cx + 6, y + 8, loaded ? 0xFF63E6A8 : textFaint());
            g.text(this.font, id, cx + 14, y, loaded ? textPrimary() : textFaint());
            String state = loaded ? "loaded" : "not installed";
            g.text(this.font, state, cx + cw - this.font.width(state), y,
                    loaded ? 0xFF63E6A8 : textFaint());
            y += 16;
        }
        y += 10;
        g.text(this.font, "KEYBINDS", cx, y, accent());
        y += 14;
        String[][] keys = {
                {"N", "NeoCraft menu (this screen)"},
                {"K", "Host panel — beta mod"},
                {"Right Shift", "HUD editor — beta mod"},
                {"F8", "Toggle HUD — beta mod"},
        };
        for (String[] k : keys) {
            g.text(this.font, k[0], cx + 4, y, accent());
            g.text(this.font, clip(k[1], cw - 100), cx + 90, y, textSecondary());
            y += 14;
        }
        y += 10;
        g.text(this.font, "The HUD layout and host panel are beta features — enable", cx, y, textFaint());
        g.text(this.font, "\"In-Game NeoCraft Mods\" in NeoCraft → Settings → Beta Features.", cx, y + 12, textFaint());

        if (!hudModLoaded()) {
            g.text(this.font, "Install the beta mods in NeoCraft → Settings → Beta Features",
                    cx, panelY + panelH - 52, textFaint());
        }
    }

    // -- Tools tab ------------------------------------------------------

    private void renderTools(GuiGraphicsExtractor g) {
        int cx = contentX + 18;
        int cw = contentW - 36;
        int top = panelY + 44;

        g.text(this.font, "Tools", cx, top, textPrimary());
        g.text(this.font, "Quick actions for this instance — folders open in Finder.",
                cx, top + 14, textFaint());
    }

    // -- Footer ---------------------------------------------------------

    private void renderFooter(GuiGraphicsExtractor g) {
        int fy = panelY + panelH - 34;
        g.fill(panelX + 1, fy - 8, panelX + panelW - 1, fy - 7, panelBorder());

        // Bridge status (left) — clipped so it can never run under the
        // footer buttons on narrow panels.
        boolean online = NeoCraftBridge.isAvailable();
        g.fill(panelX + 20, fy + 7, panelX + 26, fy + 13, online ? 0xFF63E6A8 : textFaint());
        String status = online
                ? "NeoCraft bridge online" + (NeoCraftBridge.instanceName().isEmpty() ? "" : " · " + NeoCraftBridge.instanceName())
                : "NeoCraft bridge offline";
        int statusRight = panelX + panelW - 10 - 76 - (online ? 0 : 112) - 16;
        g.text(this.font, clip(status, Math.max(40, statusRight - panelX - 32)),
                panelX + 32, fy + 2, online ? textSecondary() : textFaint());
    }

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (tab != Tab.SERVERS) return super.mouseScrolled(mouseX, mouseY, scrollX, scrollY);
        // Same visible-row math as renderServers (shared helpers).
        int visible = Math.max(1, serversVisibleRows());
        double maxScroll = Math.max(0, rows.size() - visible);
        double next = Math.max(0, Math.min(maxScroll, scroll - scrollY));
        if (next != scroll) {
            scroll = next;
            // Row buttons are positioned per visible index — rebuild so
            // they stay aligned with the scrolled rows.
            rebuildMenuWidgets();
        }
        return true;
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void onClose() {
        UiConfig.saveNow();
        // Return to the screen that opened us (title/pause) — closing
        // to null would drop the player onto a screen-less game client.
        this.minecraft.gui.setScreen(parent);
    }

    // ------------------------------------------------------------------
    // Small drawing helpers (same scanline approach as the HUD mod)
    // ------------------------------------------------------------------

    private static void roundedFill(GuiGraphicsExtractor g, int x, int y, int w, int h,
                                    int r, int color) {
        if (w <= 0 || h <= 0) return;
        r = Math.max(0, Math.min(r, Math.min(w, h) / 2));
        if (r == 0) {
            g.fill(x, y, x + w, y + h, color);
            return;
        }
        g.fill(x + r, y, x + w - r, y + h, color);
        for (int i = 0; i < r; i++) {
            int dy = r - i;
            double dx = Math.sqrt(Math.max(0, r * r - dy * dy));
            int inset = (int) Math.round(r - dx);
            g.fill(x + inset, y + i, x + w - inset, y + i + 1, color);
            g.fill(x + inset, y + h - r + i, x + w - inset, y + h - r + i + 1, color);
        }
    }

    private static void roundedBorder(GuiGraphicsExtractor g, int x, int y, int w, int h,
                                      int r, int color) {
        // Top + bottom edges
        g.fill(x + r, y, x + w - r, y + 1, color);
        g.fill(x + r, y + h - 1, x + w - r, y + h, color);
        // Side edges
        g.fill(x, y + r, x + 1, y + h - r, color);
        g.fill(x + w - 1, y + r, x + w, y + h - r, color);
        // Corner pixels approximating the radius
        for (int i = 0; i < r; i++) {
            int dy = r - i;
            double dx = Math.sqrt(Math.max(0, r * r - dy * dy));
            int inset = (int) Math.round(r - dx);
            // top-left / top-right
            g.fill(x + inset, y + i, x + inset + 1, y + i + 1, color);
            g.fill(x + w - inset - 1, y + i, x + w - inset, y + i + 1, color);
            // bottom-left / bottom-right
            g.fill(x + inset, y + h - r + i, x + inset + 1, y + h - r + i + 1, color);
            g.fill(x + w - inset - 1, y + h - r + i, x + w - inset, y + h - r + i + 1, color);
        }
    }

    private static int lerp(int a, int b, float t) {
        int ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF, aa = (a >> 24) & 0xFF;
        int br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF, ba = (b >> 24) & 0xFF;
        int r = (int) (ar + (br - ar) * t);
        int gg = (int) (ag + (bg - ag) * t);
        int bl = (int) (ab + (bb - ab) * t);
        int al = (int) (aa + (ba - aa) * t);
        return (al << 24) | (r << 16) | (gg << 8) | bl;
    }

    private String clip(String text, int maxWidth) {
        if (this.font.width(text) <= maxWidth) return text;
        String out = text;
        while (!out.isEmpty() && this.font.width(out + "…") > maxWidth) {
            out = out.substring(0, out.length() - 1);
        }
        return out + "…";
    }

    private void drawWrapped(GuiGraphicsExtractor g, String text, int x, int y, int maxWidth, int color) {
        String[] words = text.split(" ");
        StringBuilder line = new StringBuilder();
        int yy = y;
        for (String word : words) {
            String candidate = line.isEmpty() ? word : line + " " + word;
            if (this.font.width(candidate) > maxWidth && !line.isEmpty()) {
                g.text(this.font, line.toString(), x, yy, color);
                yy += 10;
                line = new StringBuilder(word);
            } else {
                line = new StringBuilder(candidate);
            }
        }
        if (!line.isEmpty()) g.text(this.font, line.toString(), x, yy, color);
    }

    private static double clamp(double v) {
        return Math.max(0, Math.min(0.6, v));
    }
}
