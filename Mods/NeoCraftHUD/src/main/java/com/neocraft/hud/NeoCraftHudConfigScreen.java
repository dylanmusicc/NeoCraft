package com.neocraft.hud;

import com.mojang.blaze3d.platform.InputConstants;
import com.neocraft.hud.HudConfig.HudProfile;
import com.neocraft.hud.HudConfig.HudWidget;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.EditBox;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.input.KeyEvent;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.network.chat.Component;
import org.joml.Matrix3x2fStack;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * NeoCraft Studio — the in-game HUD editor.
 *
 * <p>Layout: a left sidebar lists the widgets of the active profile (click to
 * select, click the "hide"/"show" zone to toggle visibility), the center is a
 * design canvas with a 10% grid and center cross where widgets can be dragged
 * (with snapping to center/edges), and a bottom panel exposes per-widget
 * style/color/option controls. A top bar manages profiles. The "Live" toggle
 * renders real widget content inside each frame; "Boxes" shows plain frames.
 * Every mutation is written back to {@code config/neocraft_hud.json} via
 * {@link HudConfig#requestSave()} (300 ms debounce); closing saves
 * immediately.</p>
 */
public class NeoCraftHudConfigScreen extends Screen {

    private static final int PANEL_W = 196;
    private static final int TOP_H = 46;
    private static final int CONTROLS_H = 208;
    private static final int ACCENT = 0xFF0A84FF;

    private HudWidget selected;
    private boolean livePreview = true;

    // Drag state
    private HudWidget dragWidget;
    private int dragMode; // 0 none, 1 move, 2 resize
    private double grabDX, grabDY, resizeStartScale, resizeStartY;
    private boolean snapX, snapY;
    private double snapGuideX, snapGuideY;

    private int widgetListTop;
    private int controlsTop;

    public NeoCraftHudConfigScreen() {
        super(Component.literal("NeoCraft Studio"));
    }

    // ------------------------------------------------------------------
    // Widget tree
    // ------------------------------------------------------------------

    @Override
    protected void init() {
        rebuild();
    }

    private void rebuild() {
        this.clearWidgets();
        HudProfile profile = HudConfig.activeProfile();
        if (profile == null) return;

        int y = 6;
        // ---- Profile bar ----
        addRenderableWidget(Button.builder(Component.literal("‹"), b -> cycleProfile(-1))
                .bounds(8, y, 22, 20).build());
        EditBox nameBox = new EditBox(this.font, 34, y, 120, 20, Component.literal("profile name"));
        nameBox.setMaxLength(48);
        nameBox.setValue(profile.name == null ? "" : profile.name);
        nameBox.setResponder(v -> {
            profile.name = v;
            HudConfig.requestSave();
        });
        nameBox.setBordered(false);
        nameBox.setTextColor(0xFFFFFFFF);
        addRenderableWidget(nameBox);
        addRenderableWidget(Button.builder(Component.literal("›"), b -> cycleProfile(1))
                .bounds(158, y, 22, 20).build());
        addRenderableWidget(Button.builder(Component.literal("New"), b -> newProfile())
                .bounds(width - 178, y, 40, 20).build());
        addRenderableWidget(Button.builder(Component.literal("Dup"), b -> duplicateProfile())
                .bounds(width - 134, y, 40, 20).build());
        addRenderableWidget(Button.builder(Component.literal("Del"), b -> deleteProfile())
                .bounds(width - 90, y, 40, 20).build());
        addRenderableWidget(Button.builder(Component.literal(livePreview ? "Live" : "Boxes"),
                        b -> { livePreview = !livePreview; rebuild(); })
                .bounds(width - 172, y + 24, 56, 18).build());
        addRenderableWidget(Button.builder(Component.literal("Save"), b -> HudConfig.saveNow())
                .bounds(width - 110, y + 24, 50, 18).build());
        addRenderableWidget(Button.builder(Component.literal("Add Widget"), b -> addWidget())
                .bounds(PANEL_W + 8, y + 24, 90, 18).build());

        widgetListTop = TOP_H + 18;
        controlsTop = height - CONTROLS_H;
        if (selected != null) buildControls();
    }

    private void buildControls() {
        int x = PANEL_W + 8;
        int w = width - PANEL_W - 16;
        int y = controlsTop + 8;
        int rowH = 20;

        String[] labels = {"Box", "Font", "Text", "Color"};
        String[] values = {selected.containerStyle, selected.fontStyle,
                selected.textStyle, selected.colorMode};
        for (int i = 0; i < 4; i++) {
            final int idx = i;
            addRenderableWidget(Button.builder(Component.literal(labels[i] + ": " + abbrev(values[i])), b -> {
                cycleStyle(idx);
                rebuild();
            }).bounds(x + i * (w / 4 + 2), y, w / 4 - 2, rowH - 4).build());
        }
        y += rowH;

        addColorBox(x, y, w / 3 - 2, "Text", selected.textColor, v -> selected.textColor = normHex(v));
        addColorBox(x + w / 3 + 1, y, w / 3 - 2, "Accent", selected.accentColor, v -> selected.accentColor = normHex(v));
        addColorBox(x + 2 * (w / 3 + 1), y, w / 3 - 2, "Border", selected.borderColor, v -> selected.borderColor = normHex(v));
        y += rowH;

        addStepper(x, y, "Op", selected.backgroundOpacity, 0.05, 0.0, 1.0,
                v -> selected.backgroundOpacity = v);
        addStepper(x + w / 3, y, "Scale", selected.scale, 0.05, 0.25, 4.0,
                v -> selected.scale = v);
        addStepper(x + 2 * (w / 3), y, "X", selected.x, 0.01, 0.0, 1.0,
                v -> selected.x = v);
        y += rowH;
        addStepper(x, y, "Y", selected.y, 0.01, 0.0, 1.0,
                v -> selected.y = v);
        addRenderableWidget(Button.builder(Component.literal("Center"), b -> {
            selected.x = 0.5;
            selected.y = 0.5;
            HudConfig.requestSave();
            rebuild();
        }).bounds(x + w / 3, y, 90, 18).build());
        y += rowH + 2;

        int colW = (w - 8) / 2;
        int col = 0;
        int rowY = y;
        for (Map.Entry<String, Object> e : selected.options.entrySet()) {
            int ox = x + col * (colW + 8);
            addOptionControl(ox, rowY, colW, e.getKey(), e.getValue());
            if (++col == 2) { col = 0; rowY += 18; }
        }
    }

    private interface DoubleSetter { void set(double v); }
    private interface StringSetter { void set(String v); }

    private void addColorBox(int x, int y, int w, String label, String value, StringSetter setter) {
        EditBox box = new EditBox(this.font, x, y, w, 16, Component.literal(label));
        box.setMaxLength(9);
        box.setValue(value == null ? "" : value.replace("#", ""));
        box.setBordered(true);
        box.setTextColor(0xFF0A84FF);
        box.setResponder(v -> {
            setter.set(v);
            HudConfig.requestSave();
        });
        addRenderableWidget(box);
    }

    private void addStepper(int x, int y, String label, double value, double step,
                            double lo, double hi, DoubleSetter setter) {
        int bw = 18;
        addRenderableWidget(Button.builder(Component.literal("−"), b -> {
            setter.set(clampD(value - step, lo, hi));
            HudConfig.requestSave();
            rebuild();
        }).bounds(x, y, bw, 18).build());
        addRenderableWidget(Button.builder(Component.literal("+"), b -> {
            setter.set(clampD(value + step, lo, hi));
            HudConfig.requestSave();
            rebuild();
        }).bounds(x + bw + 2, y, bw, 18).build());
    }

    private void addOptionControl(int x, int y, int w, String key, Object value) {
        String label = abbrev(key);
        if (value instanceof Boolean b) {
            addRenderableWidget(Button.builder(Component.literal(label + ": " + (b ? "ON" : "off")), btn -> {
                selected.options.put(key, !b);
                HudConfig.requestSave();
                rebuild();
            }).bounds(x, y, w, 16).build());
        } else if (value instanceof Number n) {
            double v = n.doubleValue();
            double step = v < 10 ? 0.1 : 1.0;
            int bw = 16;
            addRenderableWidget(Button.builder(Component.literal("−"), btn -> {
                selected.options.put(key, clampD(v - step, 0, 100));
                HudConfig.requestSave();
                rebuild();
            }).bounds(x, y, bw, 16).build());
            addRenderableWidget(Button.builder(Component.literal("+"), btn -> {
                selected.options.put(key, clampD(v + step, 0, 100));
                HudConfig.requestSave();
                rebuild();
            }).bounds(x + bw + 2, y, bw, 16).build());
        } else {
            String s = String.valueOf(value);
            List<String> candidates = candidatesFor(selected.kind, key);
            if (candidates != null) {
                addRenderableWidget(Button.builder(Component.literal(label + ": " + s + " ›"), btn -> {
                    int idx = candidates.indexOf(s);
                    String next = candidates.get(Math.floorMod(idx + 1, candidates.size()));
                    selected.options.put(key, next);
                    HudConfig.requestSave();
                    rebuild();
                }).bounds(x, y, w, 16).build());
            } else if (isColorKey(key)) {
                addColorBox(x, y, w, label, s, v -> {
                    selected.options.put(key, normHex(v));
                });
            } else {
                EditBox box = new EditBox(this.font, x, y, w, 16, Component.literal(key));
                box.setMaxLength(32);
                box.setValue(s);
                box.setBordered(true);
                box.setTextColor(0xFFCCCCCC);
                box.setResponder(v -> {
                    selected.options.put(key, v);
                    HudConfig.requestSave();
                });
                addRenderableWidget(box);
            }
        }
    }

    private static List<String> candidatesFor(String kind, String key) {
        if ("layout".equals(key)) {
            return switch (kind) {
                case "fpsPill" -> List.of("compact", "detailed");
                case "coordsCompass" -> List.of("single", "stacked");
                case "armorDurability" -> List.of("horizontal", "vertical");
                default -> List.of("compact", "detailed");
            };
        }
        if ("valueMode".equals(key)) return List.of("percent", "exact");
        if ("unit".equals(key)) return List.of("bps", "kmh");
        if ("shape".equals(key)) return List.of("circle", "rounded");
        return null;
    }

    private static boolean isColorKey(String key) {
        return key.toLowerCase(Locale.ROOT).contains("color");
    }

    private static String normHex(String v) {
        String h = v == null ? "" : v.trim();
        if (h.startsWith("#")) h = h.substring(1);
        if (h.length() == 6 || h.length() == 8) return "#" + h.toUpperCase(Locale.ROOT);
        return "#FFFFFF";
    }

    private void cycleStyle(int idx) {
        switch (idx) {
            case 0 -> selected.containerStyle = cycle(selected.containerStyle,
                    "minecraft", "applePill", "liquidGlass", "sharpVoxel", "minimalText", "neonOutline");
            case 1 -> selected.fontStyle = cycle(selected.fontStyle, "apple", "minecraft");
            case 2 -> selected.textStyle = cycle(selected.textStyle, "regular", "bold", "uppercase");
            case 3 -> selected.colorMode = cycle(selected.colorMode,
                    "static", "chroma", "biome", "reactive");
        }
        HudConfig.requestSave();
    }

    private static String cycle(String cur, String... options) {
        for (int i = 0; i < options.length; i++) {
            if (options[i].equals(cur)) return options[(i + 1) % options.length];
        }
        return options[0];
    }

    private static String abbrev(String s) {
        if (s == null) return "";
        if (s.length() <= 12) return s;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (i > 0 && Character.isUpperCase(c)) sb.append(' ');
            sb.append(c);
        }
        String spaced = sb.toString();
        return spaced.length() <= 14 ? spaced : spaced.substring(0, 13) + "…";
    }

    // ------------------------------------------------------------------
    // Profiles
    // ------------------------------------------------------------------

    private void cycleProfile(int dir) {
        List<HudProfile> profiles = HudConfig.profiles();
        if (profiles.isEmpty()) return;
        int idx = 0;
        for (int i = 0; i < profiles.size(); i++) {
            if (profiles.get(i) == HudConfig.activeProfile()) idx = i;
        }
        idx = (idx + dir + profiles.size()) % profiles.size();
        HudConfig.state().activeProfile = profiles.get(idx).id;
        selected = null;
        HudConfig.requestSave();
        rebuild();
    }

    private void newProfile() {
        HudProfile p = new HudProfile();
        p.id = "profile-" + Integer.toHexString((int) (Math.random() * 0xFFFFFF));
        p.name = "Profile " + (HudConfig.profiles().size() + 1);
        HudConfig.profiles().add(p);
        HudConfig.state().activeProfile = p.id;
        selected = null;
        HudConfig.requestSave();
        rebuild();
    }

    private void duplicateProfile() {
        HudProfile src = HudConfig.activeProfile();
        if (src == null) return;
        HudProfile p = new HudProfile();
        p.id = "profile-" + Integer.toHexString((int) (Math.random() * 0xFFFFFF));
        p.name = src.name + " copy";
        for (HudWidget w : src.widgets) {
            HudWidget c = HudConfig.createWidget(w.kind, w.x, w.y);
            c.id = java.util.UUID.randomUUID().toString();
            c.scale = w.scale;
            c.visible = w.visible;
            c.containerStyle = w.containerStyle;
            c.fontStyle = w.fontStyle;
            c.textStyle = w.textStyle;
            c.colorMode = w.colorMode;
            c.textColor = w.textColor;
            c.accentColor = w.accentColor;
            c.borderColor = w.borderColor;
            c.backgroundOpacity = w.backgroundOpacity;
            c.options = new LinkedHashMap<>(w.options);
            p.widgets.add(c);
        }
        HudConfig.profiles().add(p);
        HudConfig.state().activeProfile = p.id;
        selected = null;
        HudConfig.requestSave();
        rebuild();
    }

    private void deleteProfile() {
        List<HudProfile> profiles = HudConfig.profiles();
        HudProfile cur = HudConfig.activeProfile();
        if (cur == null || profiles.size() <= 1) return;
        profiles.remove(cur);
        HudConfig.state().activeProfile = profiles.get(0).id;
        selected = null;
        HudConfig.requestSave();
        rebuild();
    }

    private void addWidget() {
        HudProfile p = HudConfig.activeProfile();
        if (p == null) return;
        int idx = HudConfig.KINDS.indexOf(lastAddedKind);
        lastAddedKind = HudConfig.KINDS.get(Math.floorMod(idx + 1, HudConfig.KINDS.size()));
        HudWidget w = HudConfig.createWidget(lastAddedKind);
        p.widgets.add(w);
        selected = w;
        HudConfig.requestSave();
        rebuild();
    }

    private static String lastAddedKind = "fpsPill";

    // ------------------------------------------------------------------
    // Rendering — extractBackground runs before the widgets (buttons and
    // edit boxes) are drawn, so panels sit underneath them.
    // ------------------------------------------------------------------

    @Override
    public void extractBackground(GuiGraphicsExtractor g, int mouseX, int mouseY, float partialTick) {
        super.extractBackground(g, mouseX, mouseY, partialTick);
        drawChrome(g, mouseX, mouseY);
    }

    private void drawChrome(GuiGraphicsExtractor g, int mouseX, int mouseY) {
        Minecraft mc = Minecraft.getInstance();
        HudProfile profile = HudConfig.activeProfile();

        g.fill(0, 0, width, height, 0x9010141C);
        panel(g, 6, TOP_H, PANEL_W - 12, height - TOP_H - 12, 0x99101820);
        panel(g, PANEL_W + 2, TOP_H, width - PANEL_W - 8, height - TOP_H - 12, 0x99101820);
        panel(g, PANEL_W + 8, controlsTop, width - PANEL_W - 16, CONTROLS_H - 6, 0xCC0D1420);

        // ---- Widget list ----
        g.text(this.font, "WIDGETS — " + (profile == null ? 0 : profile.widgets.size()),
                14, widgetListTop, 0xFF8E8E93);
        if (profile != null) {
            int rowY = widgetListTop + 14;
            int i = 0;
            for (HudWidget w : profile.widgets) {
                if (rowY + 18 > controlsTop - 8) break;
                boolean sel = w == selected;
                int rowX = 10, rowW = PANEL_W - 20;
                int bg = sel ? 0x55228BFF : (mouseY >= rowY && mouseY < rowY + 18
                        && mouseX >= rowX && mouseX < rowX + rowW ? 0x332A2F3A : 0x22182022);
                g.fill(rowX, rowY, rowX + rowW, rowY + 18, bg);
                if (sel) g.fill(rowX, rowY, rowX + 2, rowY + 18, ACCENT);
                String label = (w.visible ? "● " : "○ ") + w.kind;
                g.text(this.font, abbrev(label), rowX + 8, rowY + 5,
                        w.visible ? (sel ? 0xFFFFFFFF : 0xFFCCCCCC) : 0xFF66666A);
                String eye = w.visible ? "hide" : "show";
                int ex = rowX + rowW - this.font.width(eye) - 6;
                g.text(this.font, eye, ex, rowY + 5, 0xFF5E9BFF);
                rowY += 20;
                i++;
            }
            if (profile.widgets.size() > i) {
                g.text(this.font, "… " + (profile.widgets.size() - i) + " more",
                        14, rowY + 2, 0xFF66666A);
            }
        }

        // ---- Canvas ----
        int cx0 = PANEL_W + 8, cy0 = TOP_H + 4;
        int cx1 = width - 8, cy1 = controlsTop - 6;
        drawGrid(g, cx0, cy0, cx1, cy1);

        if (profile != null) {
            for (HudWidget w : profile.widgets) {
                int[] b = widgetBounds(w);
                if (b == null) continue;
                boolean sel = w == selected;
                int border = sel ? ACCENT : 0x88FFFFFF;
                g.fill(b[0], b[1], b[2], b[1] + 1, border);
                g.fill(b[0], b[3] - 1, b[2], b[3], border);
                g.fill(b[0], b[1], b[0] + 1, b[3], border);
                g.fill(b[2] - 1, b[1], b[2], b[3], border);
                if (sel) {
                    g.fill(b[0] - 1, b[1] - 1, b[2] + 1, b[1], 0xCC0A84FF);
                    g.fill(b[0] - 1, b[3], b[2] + 1, b[3] + 1, 0xCC0A84FF);
                    g.fill(b[0] - 1, b[1], b[0], b[3], 0xCC0A84FF);
                    g.fill(b[2], b[1], b[2] + 1, b[3], 0xCC0A84FF);
                }
                if (livePreview) {
                    Matrix3x2fStack pose = g.pose();
                    pose.pushMatrix();
                    pose.translate((b[0] + b[2]) / 2f, (b[1] + b[3]) / 2f);
                    float sc = (float) Math.max(0.25, Math.min(4.0, w.scale));
                    pose.scale(sc, sc);
                    HudRenderer.renderWidgetPreview(g, mc, w, b[2] - b[0], b[3] - b[1]);
                    pose.popMatrix();
                }
                String tag = w.kind + "  " + String.format(Locale.ROOT,
                        "%.2f, %.2f  ×%.2f", w.x, w.y, w.scale);
                int tw = this.font.width(tag);
                int tx = Math.min(Math.max((b[0] + b[2]) / 2 - tw / 2, cx0), cx1 - tw);
                int ty = Math.max(b[1] - 11, cy0);
                g.fill(tx - 2, ty - 1, tx + tw + 2, ty + 9, 0xAA000000);
                g.text(this.font, tag, tx, ty, sel ? 0xFF0A84FF : 0xFFBBBBBB);
            }
        }

        if (snapX || snapY) {
            if (snapX) {
                int gx = (int) (snapGuideX * width);
                g.fill(gx, cy0, gx + 1, cy1, 0x660A84FF);
            }
            if (snapY) {
                int gy = (int) (snapGuideY * height);
                g.fill(cx0, gy, cx1, gy + 1, 0x660A84FF);
            }
        }

        if (selected != null) {
            drawControlLabels(g);
        }
    }

    private void drawControlLabels(GuiGraphicsExtractor g) {
        int x = PANEL_W + 8;
        int y = controlsTop + 8;
        g.text(this.font, selected.kind + " — " + selected.containerStyle
                + " / " + selected.colorMode, x, y - 12, 0xFF8E8E93);
        int rowY = y + 20;
        drawCaption(g, x + 4, rowY + 4, "TEXT");
        drawCaption(g, x + width / 3 + 5, rowY + 4, "ACCENT");
        drawCaption(g, x + 2 * (width / 3 + 1) + 4, rowY + 4, "BORDER");
        int sy = y + 40;
        drawCaption(g, x + 40, sy + 1, fmt(selected.backgroundOpacity));
        drawCaption(g, x + width / 3 + 40, sy + 1, "×" + fmt(selected.scale));
        drawCaption(g, x + 2 * (width / 3) + 40, sy + 1, fmt(selected.x));
        drawCaption(g, x + 40, sy + 21, fmt(selected.y));
    }

    private void drawCaption(GuiGraphicsExtractor g, int x, int y, String s) {
        g.text(this.font, s, x, y, 0xFF8E8E93);
    }

    private static String fmt(double v) {
        return String.format(Locale.ROOT, "%.2f", v);
    }

    private void panel(GuiGraphicsExtractor g, int x, int y, int w, int h, int color) {
        g.fill(x, y, x + w, y + h, color);
        g.fill(x, y, x + w, y + 1, 0x553A4350);
        g.fill(x, y + h - 1, x + w, y + h, 0x553A4350);
    }

    private void drawGrid(GuiGraphicsExtractor g, int x0, int y0, int x1, int y1) {
        for (int i = 1; i < 10; i++) {
            int gx = x0 + (x1 - x0) * i / 10;
            int gy = y0 + (y1 - y0) * i / 10;
            g.fill(gx, y0, gx + 1, y1, i == 5 ? 0x335A6BFF : 0x228E8E93);
            g.fill(x0, gy, x1, gy + 1, i == 5 ? 0x335A6BFF : 0x228E8E93);
        }
        int cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
        g.fill(cx - 5, cy, cx + 6, cy + 1, 0x6660A5FA);
        g.fill(cx, cy - 5, cx + 1, cy + 6, 0x6660A5FA);
    }

    /** Screen-space bounds of a widget frame (unscaled measure × scale). */
    private int[] widgetBounds(HudWidget w) {
        Minecraft mc = Minecraft.getInstance();
        int[] m = HudRenderer.measureWidget(mc, w);
        float s = (float) Math.max(0.25, Math.min(4.0, w.scale));
        int bw = (int) (m[0] * s), bh = (int) (m[1] * s);
        int cx = (int) (w.x * width), cy = (int) (w.y * height);
        return new int[]{cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2};
    }

    // ------------------------------------------------------------------
    // Input (26.3 event-record API)
    // ------------------------------------------------------------------

    @Override
    public boolean mouseClicked(MouseButtonEvent event, boolean doubleClick) {
        double mouseX = event.x(), mouseY = event.y();
        int button = event.buttonInfo().button();
        HudProfile profile = HudConfig.activeProfile();

        if (profile != null && mouseX < PANEL_W && mouseY >= widgetListTop + 14
                && mouseY < controlsTop - 8) {
            int row = (int) ((mouseY - (widgetListTop + 14)) / 20);
            if (row >= 0 && row < profile.widgets.size()) {
                HudWidget w = profile.widgets.get(row);
                int rowX = 10, rowW = PANEL_W - 20;
                boolean eyeZone = mouseX > rowX + rowW - 40;
                if (eyeZone) {
                    w.visible = !w.visible;
                } else {
                    selected = w;
                    rebuild();
                }
                HudConfig.requestSave();
                return true;
            }
        }

        if (profile != null && mouseX >= PANEL_W + 8 && mouseY >= TOP_H
                && mouseY < controlsTop - 6) {
            HudWidget hit = null;
            for (int i = profile.widgets.size() - 1; i >= 0; i--) {
                HudWidget w = profile.widgets.get(i);
                int[] b = widgetBounds(w);
                if (mouseX >= b[0] && mouseX <= b[2] && mouseY >= b[1] && mouseY <= b[3]) {
                    hit = w;
                    break;
                }
            }
            if (hit != null) {
                selected = hit;
                int[] b = widgetBounds(hit);
                boolean corner = mouseX > b[2] - 14 && mouseY > b[3] - 14;
                if (button == 1 || corner) {
                    dragMode = 2;
                    resizeStartScale = hit.scale;
                    resizeStartY = mouseY;
                } else {
                    dragMode = 1;
                    grabDX = hit.x * width - mouseX;
                    grabDY = hit.y * height - mouseY;
                }
                dragWidget = hit;
                snapX = snapY = false;
                rebuild();
                return true;
            } else if (button == 0) {
                selected = null;
                rebuild();
                return true;
            }
        }
        return super.mouseClicked(event, doubleClick);
    }

    @Override
    public boolean mouseDragged(MouseButtonEvent event, double dragX, double dragY) {
        if (dragWidget != null && dragMode != 0) {
            double mouseX = event.x(), mouseY = event.y();
            if (dragMode == 1) {
                double nx = clampD((mouseX + grabDX) / width, 0, 1);
                double ny = clampD((mouseY + grabDY) / height, 0, 1);
                snapX = snapY = false;
                nx = snap(nx, 0.5, 0.015, true);
                ny = snap(ny, 0.5, 0.015, false);
                if (Math.abs(nx) < 0.012) { nx = 0; snapX = true; snapGuideX = 0; }
                if (Math.abs(nx - 1) < 0.012) { nx = 1; snapX = true; snapGuideX = 1; }
                if (Math.abs(ny) < 0.012) { ny = 0; snapY = true; snapGuideY = 0; }
                if (Math.abs(ny - 1) < 0.012) { ny = 1; snapY = true; snapGuideY = 1; }
                dragWidget.x = nx;
                dragWidget.y = ny;
            } else {
                dragWidget.scale = clampD(resizeStartScale + (resizeStartY - mouseY) * 0.01, 0.25, 4.0);
            }
            HudConfig.requestSave();
            return true;
        }
        return super.mouseDragged(event, dragX, dragY);
    }

    private double snap(double v, double target, double tol, boolean isX) {
        if (Math.abs(v - target) < tol) {
            if (isX) { snapX = true; snapGuideX = target; }
            else { snapY = true; snapGuideY = target; }
            return target;
        }
        return v;
    }

    @Override
    public boolean mouseReleased(MouseButtonEvent event) {
        if (dragWidget != null) {
            dragWidget = null;
            dragMode = 0;
            snapX = snapY = false;
            HudConfig.requestSave();
            return true;
        }
        return super.mouseReleased(event);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY,
                                 double scrollX, double scrollY) {
        if (selected != null && mouseX >= PANEL_W + 8 && mouseY < controlsTop - 6) {
            selected.scale = clampD(selected.scale * (scrollY > 0 ? 1.06 : 0.94), 0.25, 4.0);
            HudConfig.requestSave();
            rebuild();
            return true;
        }
        return super.mouseScrolled(mouseX, mouseY, scrollX, scrollY);
    }

    @Override
    public boolean keyPressed(KeyEvent event) {
        if (super.keyPressed(event)) return true;
        if (selected != null) {
            HudProfile p = HudConfig.activeProfile();
            if (isKey(event, InputConstants.KEY_DELETE, InputConstants.KEYCODE_DELETE) && p != null) {
                p.widgets.remove(selected);
                selected = null;
                HudConfig.requestSave();
                rebuild();
                return true;
            }
            if (isKey(event, InputConstants.KEY_V, InputConstants.KEYCODE_V)) {
                selected.visible = !selected.visible;
                HudConfig.requestSave();
                rebuild();
                return true;
            }
        }
        return false;
    }

    /** Matches a key event against both the scancode and keycode families. */
    private static boolean isKey(KeyEvent event, int scanCode, int keyCode) {
        return event.key() == scanCode || event.key() == keyCode
                || event.keycode() == scanCode || event.keycode() == keyCode
                || event.input() == scanCode || event.input() == keyCode;
    }

    @Override
    public void onClose() {
        HudConfig.saveNow();
        super.onClose();
    }

    @Override
    public boolean isPauseScreen() {
        return true;
    }

    private static double clampD(double v, double lo, double hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}
