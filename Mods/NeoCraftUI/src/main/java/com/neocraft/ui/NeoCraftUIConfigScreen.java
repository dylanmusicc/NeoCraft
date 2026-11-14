package com.neocraft.ui;

import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;

/**
 * NeoCraft UI settings — the in-game counterpart of Neo Studio → In-Game
 * UI. Every change writes {@code config/neocraft_ui.json} (debounced) so
 * the launcher and other mods see the same document.
 */
public class NeoCraftUIConfigScreen extends Screen {

    private static final int ACCENT = 0xFF0A84FF;
    private static final int MAX_PANEL_W = 320;
    private static final int ROW_H = 22;
    private int pw, px;

    public NeoCraftUIConfigScreen() {
        super(Component.literal("NeoCraft UI"));
    }

    @Override
    protected void init() {
        UiConfig.UiState s = UiConfig.state();
        // Shrink the panel on narrow windows instead of letting it run
        // off-screen (fixed 320 px used to produce a negative x).
        pw = Math.min(MAX_PANEL_W, Math.max(200, width - 16));
        px = Math.max(8, (width - pw) / 2);
        int x = px;
        int y = 40;
        int rowW = pw;

        // All mutations go through UiConfig.update so they land on the
        // live state instance — the config watcher swaps UiState objects
        // on external edits and a captured reference would write into
        // the void.
        addRenderableWidget(toggle(x, y, rowW, "Enabled", s.enabled, v ->
                UiConfig.update(u -> u.enabled = v)));
        y += ROW_H + 6;

        addRenderableWidget(toggle(x, y, rowW, "Full NeoCraft redesign", s.fullRedesign, v ->
                UiConfig.update(u -> u.fullRedesign = v)));
        y += ROW_H + 10;

        // Accent preset cycler
        final int[] accentIdx = {indexOf(s.accentColor)};
        addRenderableWidget(Button.builder(
                        Component.literal("Accent: " + s.accentColor), b -> {
                            accentIdx[0] = (accentIdx[0] + 1) % UiConfig.ACCENT_PRESETS.length;
                            String picked = UiConfig.ACCENT_PRESETS[accentIdx[0]];
                            UiConfig.update(u -> {
                                u.accentColor = picked;
                                u.tintColor = picked;
                            });
                            rebuild();
                        })
                .bounds(x, y, rowW, 20).build());
        y += ROW_H;

        // Tint opacity stepper
        addRenderableWidget(Button.builder(Component.literal("Tint −"), b -> {
            UiConfig.update(u -> u.tintOpacity = clamp(u.tintOpacity - 0.02));
            rebuild();
        }).bounds(x, y, 90, 20).build());
        addRenderableWidget(Button.builder(Component.literal("Tint +"), b -> {
            UiConfig.update(u -> u.tintOpacity = clamp(u.tintOpacity + 0.02));
            rebuild();
        }).bounds(x + rowW - 90, y, 90, 20).build());
        y += ROW_H + 10;

        for (String id : UiConfig.SCREEN_IDS) {
            final String screen = id;
            addRenderableWidget(toggle(x, y, rowW, cap(id) + " screen",
                    s.screens.getOrDefault(id, true), v ->
                            UiConfig.update(u -> u.screens.put(screen, v))));
            y += ROW_H + 4;
        }

        addRenderableWidget(Button.builder(Component.literal("Done"), b -> onClose())
                .bounds(x + rowW / 2 - 50, y + 8, 100, 20).build());
    }

    private Button toggle(int x, int y, int w, String label, boolean value,
                          java.util.function.Consumer<Boolean> setter) {
        return Button.builder(
                        Component.literal(label + ": " + (value ? "ON" : "off")), b -> {
                            setter.accept(!value);
                            rebuild();
                        })
                .bounds(x, y, w, 20)
                .build();
    }

    private void rebuild() {
        this.clearWidgets();
        this.init();
    }

    @Override
    public void extractBackground(GuiGraphicsExtractor g, int mouseX, int mouseY, float partialTick) {
        super.extractBackground(g, mouseX, mouseY, partialTick);
        g.fill(0, 0, width, height, 0xC0101218);
        g.fill(px - 8, 26, px + pw + 8, height - 20, 0xEE161C26);
        g.text(this.font, "NEOCRAFT UI", px, 34, ACCENT);
        g.text(this.font, "Writes config/neocraft_ui.json — Neo Studio edits the same file.",
                px, height - 14, 0xFF8E8E93);
    }

    private static int indexOf(String color) {
        for (int i = 0; i < UiConfig.ACCENT_PRESETS.length; i++) {
            if (UiConfig.ACCENT_PRESETS[i].equalsIgnoreCase(color)) return i;
        }
        return 0;
    }

    private static String cap(String id) {
        return id.isEmpty() ? id : Character.toUpperCase(id.charAt(0)) + id.substring(1);
    }

    private static double clamp(double v) {
        return Math.max(0, Math.min(0.6, v));
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    @Override
    public void onClose() {
        UiConfig.saveNow();
        this.minecraft.gui.setScreen(null);
    }
}
