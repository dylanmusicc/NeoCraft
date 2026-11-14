package com.neocraft.host;

import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * NeoCraft Host — the in-game server panel.
 *
 * <p>Shows the worlds of the running instance (host any of them as a
 * dedicated server) and every hosted server NeoCraft knows about with
 * live status, start/stop and copy-address actions. All data comes from
 * the NeoCraft bridge; when NeoCraft isn't running (or is too old to
 * have the bridge) the panel shows an offline state with an
 * "Open NeoCraft" button.</p>
 */
public class NeoCraftHostScreen extends Screen {

    private static final int MAX_PW = 480;
    private static final int MAX_PH = 340;
    private static final int HEADER_H = 52;
    private static final int ROW_H = 22;
    private static final int ACCENT = 0xFF0A84FF;

    private static final int TYPE_HEADER = 0;
    private static final int TYPE_SERVER = 1;
    private static final int TYPE_WORLD = 2;

    private record Row(int type, JsonObject data, String label) { }

    private final List<Row> rows = new ArrayList<>();
    private double scroll;
    private long lastBridgeVersion = -1;
    private boolean lastBridgeAvailable;
    private int panelX, panelY, pw, ph;

    public NeoCraftHostScreen() {
        super(Component.literal("NeoCraft Host"));
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------

    @Override
    protected void init() {
        // Adaptive panel: never wider/taller than the window minus a
        // margin, never narrower than a usable minimum.
        pw = Math.min(MAX_PW, Math.max(280, width - 16));
        ph = Math.min(MAX_PH, Math.max(220, height - 16));
        panelX = (width - pw) / 2;
        panelY = (height - ph) / 2;
        rebuildRows();
        placeWidgets();
    }

    /** Rebuilds the row model and the widget set for it. Called on init
     *  and whenever the bridge publishes a new state (once per second). */
    private void rebuildRows() {
        // Track the version even on the offline early-return — the
        // bridge only bumps it on fresh state.json parses, so leaving
        // it stale made extractBackground rebuild every frame.
        lastBridgeVersion = Bridge.version();
        rows.clear();
        if (!Bridge.isAvailable()) return;

        List<JsonObject> servers = Bridge.servers();
        rows.add(new Row(TYPE_HEADER, null, "HOSTED SERVERS"));
        if (servers.isEmpty()) {
            rows.add(new Row(TYPE_HEADER, null, "  none yet — host a world below"));
        }
        for (JsonObject server : servers) {
            rows.add(new Row(TYPE_SERVER, server, null));
        }

        List<JsonObject> worlds = Bridge.worlds();
        rows.add(new Row(TYPE_HEADER, null, "WORLDS — HOST AS SERVER"));
        if (worlds.isEmpty()) {
            rows.add(new Row(TYPE_HEADER, null, "  no worlds found in this instance"));
        }
        for (JsonObject world : worlds) {
            rows.add(new Row(TYPE_WORLD, world, null));
        }
    }

    private void placeWidgets() {
        this.clearWidgets();
        int listTop = panelY + HEADER_H;
        int listBottom = panelY + ph - 8;
        int visible = Math.max(0, (listBottom - listTop) / ROW_H);
        int start = (int) Math.floor(scroll);

        for (int i = start; i < Math.min(rows.size(), start + visible); i++) {
            Row row = rows.get(i);
            int ry = listTop + (i - start) * ROW_H;
            int right = panelX + pw - 10;
            switch (row.type()) {
                case TYPE_SERVER -> {
                    boolean running = row.data().has("running")
                            && row.data().get("running").getAsBoolean();
                    boolean settingUp = row.data().has("settingUp")
                            && row.data().get("settingUp").getAsBoolean();
                    String action = running ? "Stop" : (settingUp ? "…" : "Start");
                    final JsonObject server = row.data();
                    addRenderableWidget(Button.builder(Component.literal(action), b -> {
                        if (running) {
                            Bridge.sendQuiet("stop", Bridge.serverParams(server));
                        } else {
                            Bridge.sendQuiet("start", Bridge.serverParams(server));
                        }
                        Bridge.poll();
                        rebuildRows();
                        placeWidgets();
                    }).bounds(right - 52, ry + 2, 52, 18).build());
                    addRenderableWidget(Button.builder(Component.literal("IP"), b -> {
                        copyAddress(server);
                    }).bounds(right - 110, ry + 2, 52, 18).build());
                }
                case TYPE_WORLD -> {
                    String key = Bridge.worldKey(row.data());
                    // "Dir" opens saves/<levelName> — always available,
                    // hosted or not.
                    final JsonObject world = row.data();
                    addRenderableWidget(Button.builder(Component.literal("Dir"), b -> openWorldFolder(world))
                            .bounds(right - 110, ry + 2, 52, 18).build());
                    if (Bridge.worldAlreadyHosted(key)) break;
                    addRenderableWidget(Button.builder(
                                    Component.literal("Host"), b -> hostWorld(world))
                            .bounds(right - 52, ry + 2, 52, 18)
                            .build());
                }
                default -> { }
            }
        }

        // Offline-state actions live outside the scroll area — centered
        // as a pair so they stay inside the panel at any width.
        if (!Bridge.isAvailable()) {
            int by = panelY + ph - 34;
            int pairX = panelX + Math.max(10, (pw - 240) / 2);
            addRenderableWidget(Button.builder(Component.literal("Open NeoCraft"), b -> openApp())
                    .bounds(pairX, by, 150, 20).build());
            addRenderableWidget(Button.builder(Component.literal("Retry"), b -> {
                Bridge.poll();
                rebuildRows();
                placeWidgets();
            }).bounds(pairX + 160, by, 80, 20).build());
        }
    }

    private void hostWorld(JsonObject world) {
        JsonObject params = new JsonObject();
        params.addProperty("worldName", Bridge.worldKey(world));
        Bridge.send("host", params).whenComplete((response, error) ->
                Minecraft.getInstance().execute(() -> {
                    if (error != null) {
                        toast("Host failed: " + Bridge.lastError());
                    } else if (response != null && response.has("ok")
                            && response.get("ok").getAsBoolean()) {
                        toast("Setting up server — watch NeoCraft for progress");
                    } else {
                        toast("Host failed: " + Bridge.lastError());
                    }
                    Bridge.poll();
                    rebuildRows();
                    placeWidgets();
                }));
    }

    private void copyAddress(JsonObject server) {
        String address = server.has("address") ? server.get("address").getAsString() : "";
        if (address.isEmpty()) return;
        Minecraft.getInstance().keyboardHandler.setClipboard(address);
        toast("Copied " + address);
    }

    /** Opens saves/<levelName> in Finder — only when the folder really
     *  exists so stale bridge entries can't create empty directories. */
    private void openWorldFolder(JsonObject world) {
        String name = world.has("levelName") ? world.get("levelName").getAsString()
                : (world.has("name") ? world.get("name").getAsString() : "");
        if (name.isEmpty()) {
            toast("World has no folder name");
            return;
        }
        java.io.File dir = new java.io.File("saves", name);
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
    // Rendering — rows are drawn here; only real widgets (buttons) are
    // handled by the widget tree.
    // ------------------------------------------------------------------

    @Override
    public void extractBackground(GuiGraphicsExtractor g, int mouseX, int mouseY, float partialTick) {
        // Pick up bridge changes published since the last frame. The
        // availability flag matters too: version() freezes when the
        // bridge goes offline, so without it the offline panel (Retry /
        // Open NeoCraft) would never appear.
        boolean available = Bridge.isAvailable();
        if (Bridge.version() != lastBridgeVersion || available != lastBridgeAvailable) {
            lastBridgeAvailable = available;
            rebuildRows();
            placeWidgets();
        }
        super.extractBackground(g, mouseX, mouseY, partialTick);

        g.fill(0, 0, width, height, 0xC0101218);
        panel(g, panelX, panelY, pw, ph, 0xFF161C26);
        g.fill(panelX, panelY, panelX + pw, panelY + 1, 0x553A6FD8);
        g.fill(panelX, panelY + ph - 1, panelX + pw, panelY + ph, 0x223A6FD8);

        // Header
        g.text(this.font, "NEOCRAFT HOST", panelX + 14, panelY + 10, 0xFFFFFFFF);
        String sub = Bridge.isAvailable()
                ? "Bridge online · " + Bridge.instanceName()
                : "Bridge offline — start NeoCraft to manage hosted servers in-game";
        sub += "  ·  " + Minecraft.getInstance().getFps() + " FPS";
        g.text(this.font, clip(sub, pw - 28), panelX + 14, panelY + 24, 0xFF8E8E93);
        if (Bridge.isAvailable() && !Bridge.lastError().isEmpty()) {
            g.text(this.font, clip(Bridge.lastError(), pw - 28),
                    panelX + 14, panelY + 36, 0xFFFF7A7A);
        }

        if (!Bridge.isAvailable()) {
            String hint = "The NeoCraft bridge lives in config/neocraft_bridge/ and is "
                    + "written while NeoCraft runs this instance. Older NeoCraft "
                    + "versions don't have it — update the launcher.";
            drawWrapped(g, hint, panelX + 20, panelY + HEADER_H + 20, pw - 40, 0xFF8E8E93);
            return;
        }

        // Rows
        int listTop = panelY + HEADER_H;
        int listBottom = panelY + ph - 8;
        int visible = Math.max(0, (listBottom - listTop) / ROW_H);
        int start = (int) Math.floor(scroll);
        for (int i = start; i < Math.min(rows.size(), start + visible); i++) {
            Row row = rows.get(i);
            int ry = listTop + (i - start) * ROW_H;
            if (row.type() == TYPE_HEADER) {
                g.text(this.font, row.label(), panelX + 14, ry + 7, 0xFF5E9BFF);
                continue;
            }
            if (ry + ROW_H > listBottom) break;
            String text;
            int color = 0xFFCCCCCC;
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
                    state = "stopped"; color = 0xFF8E8E93;
                }
                if (s.has("playersSeen") && s.get("playersSeen").getAsInt() > 0) {
                    state += " · " + s.get("playersSeen").getAsInt() + "p";
                }
                text = name + "  ·  " + address + "  ·  " + state;
            } else {
                JsonObject w = row.data();
                String name = w.has("levelName") ? w.get("levelName").getAsString()
                        : (w.has("name") ? w.get("name").getAsString() : "?");
                boolean hosted = Bridge.worldAlreadyHosted(Bridge.worldKey(w));
                text = name + (hosted ? "  (already hosted)" : "");
            }
            g.text(this.font, clip(text, pw - 140), panelX + 14, ry + 7, color);
        }

        // Scrollbar hint
        if (rows.size() * ROW_H > (listBottom - listTop)) {
            int trackH = listBottom - listTop;
            int thumbH = Math.max(16, trackH * trackH / (rows.size() * ROW_H));
            int thumbY = listTop + (int) ((trackH - thumbH) * (scroll / Math.max(1, rows.size() - visible)));
            g.fill(panelX + pw - 5, thumbY, panelX + pw - 3, thumbY + thumbH, 0x554A6FD8);
        }
    }

    private void panel(GuiGraphicsExtractor g, int x, int y, int w, int h, int color) {
        g.fill(x, y, x + w, y + h, color);
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

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        double maxScroll = Math.max(0, rows.size() - (ph - HEADER_H - 8) / ROW_H);
        scroll = Math.max(0, Math.min(maxScroll, scroll - scrollY));
        return true;
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void onClose() {
        this.minecraft.gui.setScreen(null);
    }
}
