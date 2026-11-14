package com.neocraft.hud;

import com.neocraft.hud.HudConfig.ChatUi;
import com.neocraft.hud.HudConfig.CrosshairUi;
import com.neocraft.hud.HudConfig.HotbarUi;
import com.neocraft.hud.HudConfig.HudProfile;
import com.neocraft.hud.HudConfig.HudUiSettings;
import com.neocraft.hud.HudConfig.HudWidget;
import com.neocraft.hud.HudConfig.ScoreboardUi;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.BlockPos;
import net.minecraft.locale.Language;
import net.minecraft.tags.FluidTags;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.LightLayer;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.scores.DisplaySlot;
import net.minecraft.world.scores.Objective;
import org.joml.Matrix3x2fStack;

import java.awt.Color;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Renders the NeoCraft HUD: every visible widget of the active profile plus
 * the glass skins for the vanilla hotbar / scoreboard / chat regions.
 *
 * <p>Widget anchors are normalized center coordinates (0–1 of the viewport),
 * matching the Studio editor. Everything is drawn through
 * {@link GuiGraphicsExtractor} inside a translated/scaled
 * {@link Matrix3x2fStack} pose so {@code widget.scale} applies uniformly.</p>
 *
 * <p>Three entry points exist so Fabric can place backdrops <em>under</em> the
 * matching vanilla layers (chat / hotbar / scoreboard) while the main pass
 * draws widgets and foreground accents before {@code MISC_OVERLAYS}.</p>
 */
public final class HudRenderer {

    private HudRenderer() { }

    // ------------------------------------------------------------------
    // Runtime state (CPS counter, death waypoint, FPS ring, hotbar anim)
    // ------------------------------------------------------------------

    private static final int FPS_RING = 120;
    private static final int[] fpsSamples = new int[FPS_RING];
    private static int fpsIdx, fpsCount;

    private static int cpsCount, lastCps;
    private static long cpsWindowStart;
    private static final Map<net.minecraft.client.KeyMapping, Boolean> keyPrev = new IdentityHashMap<>();

    private static BlockPos deathPos;
    private static boolean wasDead;

    private static float hotbarSelAnim = -1f;

    private static final Minimap minimap = new Minimap();

    /** Called once per client tick from {@link NeoCraftHUDClient}. */
    public static void tick(Minecraft mc) {
        LocalPlayer p = mc.player;
        if (p != null) {
            boolean dead = p.deathTime > 0;
            if (dead && !wasDead) deathPos = p.blockPosition();
            wasDead = dead;
        } else {
            wasDead = false;
        }

        long now = System.currentTimeMillis();
        if (now - cpsWindowStart >= 1000L) {
            lastCps = cpsCount;
            cpsCount = 0;
            cpsWindowStart = now;
        }
        trackKey(mc.options.keyUp);
        trackKey(mc.options.keyDown);
        trackKey(mc.options.keyLeft);
        trackKey(mc.options.keyRight);
        trackKey(mc.options.keyJump);
        trackKey(mc.options.keyShift);
        trackKey(mc.options.keySprint);
        trackKey(mc.options.keyAttack);
        trackKey(mc.options.keyUse);
    }

    private static void trackKey(net.minecraft.client.KeyMapping k) {
        if (k == null) return;
        boolean down = k.isDown();
        Boolean prev = keyPrev.get(k);
        if (down && !Boolean.TRUE.equals(prev)) cpsCount++;
        keyPrev.put(k, down);
    }

    public static int cps() { return lastCps; }

    public static BlockPos deathWaypoint() { return deathPos; }

    // ------------------------------------------------------------------
    // Fabric HUD element entry points
    // ------------------------------------------------------------------

    /** Main pass — widgets + hotbar foreground accents (before MISC_OVERLAYS). */
    public static void render(GuiGraphicsExtractor g, DeltaTracker delta) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.gui.hud.isHidden()) return;
        int vw = g.guiWidth();
        int vh = g.guiHeight();
        HudUiSettings ui = HudConfig.ui();

        if (ui.hotbar != null) renderHotbarOverlay(g, mc, vw, vh, ui.hotbar);

        HudProfile profile = HudConfig.activeProfile();
        if (profile != null && mc.player != null && mc.level != null) {
            fpsSamples[fpsIdx % FPS_RING] = mc.getFps();
            fpsIdx++;
            fpsCount = Math.min(fpsCount + 1, FPS_RING);
            for (HudWidget w : profile.widgets) {
                if (w.visible && w.kind != null) renderWidget(g, mc, w, vw, vh);
            }
        }
    }

    /** Backdrop pass drawn immediately before the vanilla CHAT layer. */
    public static void renderChatBackdrop(GuiGraphicsExtractor g, DeltaTracker delta) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.gui.hud.isHidden() || mc.player == null) return;
        ChatUi ui = HudConfig.ui().chat;
        if (ui == null || !ui.enabled) return;
        renderChatVeil(g, mc, g.guiWidth(), g.guiHeight(), ui);
    }

    /** Backdrop pass drawn immediately before the vanilla HOTBAR layer. */
    public static void renderHotbarBackdrop(GuiGraphicsExtractor g, DeltaTracker delta) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.gui.hud.isHidden() || mc.player == null) return;
        HotbarUi ui = HudConfig.ui().hotbar;
        if (ui == null || !ui.glassBackground) return;
        renderHotbarGlass(g, mc, g.guiWidth(), g.guiHeight(), ui);
    }

    /** Backdrop pass drawn immediately before the vanilla SCOREBOARD layer. */
    public static void renderScoreboardBackdrop(GuiGraphicsExtractor g, DeltaTracker delta) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.gui.hud.isHidden() || mc.level == null) return;
        ScoreboardUi ui = HudConfig.ui().scoreboard;
        if (ui == null || !ui.enabled || !ui.glassBox) return;
        renderScoreboardVeil(g, mc, g.guiWidth(), g.guiHeight(), ui);
    }

    /**
     * Custom crosshair entry point — installed via
     * {@code HudElementRegistry.replaceElement(VanillaHudElements.CROSSHAIR, ...)}
     * so it fully replaces the vanilla crosshair when enabled.
     */
    public static void renderCrosshairElement(GuiGraphicsExtractor g, DeltaTracker delta) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.gui.hud.isHidden()) return;
        CrosshairUi ui = HudConfig.ui().crosshair;
        if (ui == null || !ui.enabled) return;
        renderCrosshair(g, mc, g.guiWidth(), g.guiHeight(), ui);
    }

    /** Renders a single widget's content centered on the current pose origin. */
    public static void renderWidgetPreview(GuiGraphicsExtractor g, Minecraft mc,
                                           HudWidget w, int vw, int vh) {
        drawWidgetLocal(g, mc, w);
    }

    /**
     * Measures a widget's unscaled content size. Used both for centering
     * during render and for hit-testing inside the editor. Safe without a
     * world (returns placeholder-sized boxes).
     */
    public static int[] measureWidget(Minecraft mc, HudWidget w) {
        Font font = mc != null ? mc.font : Minecraft.getInstance().font;
        return switch (w.kind) {
            case "keystrokes" -> new int[]{114, 126};
            case "minimap" -> new int[]{124, 124};
            case "statusPills" -> measureStatusPills(font, mc, w);
            default -> measureTextWidget(font, mc, w);
        };
    }

    // ------------------------------------------------------------------
    // Widget dispatch
    // ------------------------------------------------------------------

    private static void renderWidget(GuiGraphicsExtractor g, Minecraft mc,
                                     HudWidget w, int vw, int vh) {
        int cx = (int) Math.round(w.x * vw);
        int cy = (int) Math.round(w.y * vh);
        float s = (float) Math.max(0.25, Math.min(4.0, w.scale));
        Matrix3x2fStack pose = g.pose();
        pose.pushMatrix();
        pose.translate(cx, cy);
        pose.scale(s, s);
        try {
            drawWidgetLocal(g, mc, w);
        } finally {
            pose.popMatrix();
        }
    }

    /** Draws the widget content centered on (0,0) of the current pose. */
    private static void drawWidgetLocal(GuiGraphicsExtractor g, Minecraft mc, HudWidget w) {
        switch (w.kind) {
            case "fpsPill" -> drawTextWidget(g, mc, w, buildFpsLines(mc, w));
            case "coordsCompass" -> drawTextWidget(g, mc, w, buildCoordsLines(mc, w));
            case "netherCoords" -> drawTextWidget(g, mc, w, buildNetherLines(mc, w));
            case "armorDurability" -> drawTextWidget(g, mc, w, buildArmorLines(mc, w));
            case "potionEffects" -> drawTextWidget(g, mc, w, buildPotionLines(mc, w));
            case "keystrokes" -> drawKeystrokes(g, mc, w);
            case "pingTPS" -> drawTextWidget(g, mc, w, buildPingLines(mc, w));
            case "clocks" -> drawTextWidget(g, mc, w, buildClockLines(mc, w));
            case "dayLight" -> drawTextWidget(g, mc, w, buildDayLightLines(mc, w));
            case "speedometer" -> drawTextWidget(g, mc, w, buildSpeedLines(mc, w));
            case "statusPills" -> drawStatusPills(g, mc, w);
            case "minimap" -> minimap.draw(g, mc, w);
            case "lightLevel" -> drawTextWidget(g, mc, w, buildLightLines(mc, w));
            default -> { }
        }
    }

    // ------------------------------------------------------------------
    // Content builders — every builder is null-safe (editor preview).
    // ------------------------------------------------------------------

    private static List<String> buildFpsLines(Minecraft mc, HudWidget w) {
        boolean detailed = "detailed".equals(w.optString("layout", "compact"));
        List<String> parts = new ArrayList<>();
        int fps = mc.getFps();
        if (w.optBool("showFPS", true)) parts.add(fps + " FPS");
        if (w.optBool("showFrameTime", true)) {
            parts.add(String.format(Locale.ROOT, "%.1f ms", 1000.0 / Math.max(1, fps)));
        }
        if (w.optBool("showMinAvg", true)) {
            int min = Integer.MAX_VALUE, sum = 0, n = 0;
            for (int i = 0; i < fpsCount; i++) {
                int v = fpsSamples[i];
                if (v > 0) { min = Math.min(min, v); sum += v; n++; }
            }
            if (min != Integer.MAX_VALUE) {
                parts.add("min " + min + " · avg " + (sum / n));
            }
        }
        if (w.optBool("showMemory", false)) {
            Runtime rt = Runtime.getRuntime();
            long used = (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024);
            parts.add(used + " MB");
        }
        if (w.optBool("showChunks", false) && mc.level != null) {
            parts.add(mc.level.getChunkSource().getLoadedChunksCount() + " chunks");
        }
        if (parts.isEmpty()) return List.of("--");
        if (detailed) return parts;
        return List.of(String.join("  ·  ", parts));
    }

    private static List<String> buildCoordsLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        LocalPlayer p = mc.player;
        if (p == null) return List.of("coordsCompass");
        BlockPos pos = p.blockPosition();
        boolean stacked = "stacked".equals(w.optString("layout", "single"));
        String coords = pos.getX() + " " + pos.getY() + " " + pos.getZ();
        if (stacked) {
            out.add("XYZ  " + coords);
        } else {
            out.add(coords);
        }
        if (w.optBool("showFacing", true)) {
            String facing = facingName(p.getYRot());
            if (stacked) out.add("Facing  " + facing);
            else appendLast(out, "  ·  " + facing);
        }
        if (w.optBool("showBiome", true) && mc.level != null) {
            String biome = biomeName(mc.level, pos);
            if (stacked) out.add("Biome  " + biome);
            else appendLast(out, "  ·  " + biome);
        }
        if (w.optBool("showNether", false)) {
            String n = "N " + (pos.getX() / 8) + " " + (pos.getY() / 8) + " " + (pos.getZ() / 8);
            if (stacked) out.add(n);
            else appendLast(out, "  ·  " + n);
        }
        return out;
    }

    private static List<String> buildNetherLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        LocalPlayer p = mc.player;
        if (p == null) return List.of("netherCoords");
        BlockPos pos = p.blockPosition();
        if (w.optBool("showOverworld", true)) out.add("OW  " + pos.getX() + " " + pos.getY() + " " + pos.getZ());
        if (w.optBool("showNether", true)) {
            out.add("N   " + (pos.getX() / 8) + " " + (pos.getY() / 8) + " " + (pos.getZ() / 8));
        }
        if (out.isEmpty()) out.add("--");
        return out;
    }

    private static List<String> buildArmorLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        LocalPlayer p = mc.player;
        if (p == null) return List.of("armorDurability");
        boolean horizontal = "horizontal".equals(w.optString("layout", "horizontal"));
        boolean percent = "percent".equals(w.optString("valueMode", "percent"));
        boolean lowWarn = w.optBool("lowWarn", true);
        boolean warnPhase = lowWarn && ((System.currentTimeMillis() / 350L) & 1) == 0;
        String[] names = {"Helmet", "Chest", "Legs", "Boots"};
        EquipmentSlot[] slots = {EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS, EquipmentSlot.FEET};
        if (horizontal) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 4; i++) {
                ItemStack st = p.getItemBySlot(slots[i]);
                if (sb.length() > 0) sb.append("   ");
                sb.append(shortSlot(names[i])).append(' ');
                if (st.isEmpty() || !st.isDamageableItem()) sb.append("—");
                else {
                    int remaining = st.getMaxDamage() - st.getDamageValue();
                    int pct = st.getMaxDamage() == 0 ? 100 : remaining * 100 / st.getMaxDamage();
                    if (warnPhase && pct < 25) sb.append('!');
                    sb.append(percent ? pct + "%" : remaining + "/" + st.getMaxDamage());
                }
            }
            out.add(sb.toString());
        } else {
            for (int i = 0; i < 4; i++) {
                ItemStack st = p.getItemBySlot(slots[i]);
                String val;
                if (st.isEmpty() || !st.isDamageableItem()) val = "—";
                else {
                    int remaining = st.getMaxDamage() - st.getDamageValue();
                    int pct = st.getMaxDamage() == 0 ? 100 : remaining * 100 / st.getMaxDamage();
                    val = percent ? pct + "%" : remaining + "/" + st.getMaxDamage();
                    if (warnPhase && pct < 25) val = "!" + val;
                }
                out.add(names[i] + "  " + val);
            }
        }
        return out;
    }

    private static List<String> buildPotionLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        LocalPlayer p = mc.player;
        if (p == null) return List.of("potionEffects");
        int max = (int) w.optNum("maxEffects", 5);
        boolean dur = w.optBool("showDuration", true);
        int i = 0;
        for (MobEffectInstance inst : p.getActiveEffects()) {
            if (i++ >= max) break;
            String name = Language.getInstance()
                    .getOrDefault(inst.getEffect().value().getDescriptionId());
            if (dur) {
                int secs = inst.getDuration() / 20;
                out.add(name + "  " + (secs / 60) + ":" + String.format(Locale.ROOT, "%02d", secs % 60));
            } else {
                out.add(name);
            }
        }
        if (out.isEmpty()) out.add("No effects");
        return out;
    }

    private static List<String> buildPingLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        var conn = mc.getConnection();
        String ping = "-- ms";
        if (conn != null && mc.player != null) {
            var info = conn.getPlayerInfo(mc.player.getUUID());
            if (info != null) ping = info.getLatency() + " ms";
        }
        out.add(ping);
        if (w.optBool("showTPS", true)) {
            // The client cannot observe server TPS directly; show an honest
            // placeholder rather than a fabricated number.
            out.add("TPS --");
        }
        return out;
    }

    private static List<String> buildClockLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        if (mc.level != null && w.optBool("showDayCounter", true)) {
            out.add("Day " + (mc.level.getOverworldClockTime() / 24000));
        }
        if (w.optBool("showMacClock", true)) {
            out.add(java.time.LocalTime.now().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm")));
        }
        if (mc.level != null && !w.optBool("showDayCounter", true)) {
            long t = mc.level.getOverworldClockTime() % 24000;
            int h = (int) ((t / 1000 + 6) % 24);
            int m = (int) ((t % 1000) * 60 / 1000);
            out.add(String.format(Locale.ROOT, "MC %d:%02d", h, m));
        }
        if (out.isEmpty()) out.add("--");
        return out;
    }

    private static List<String> buildDayLightLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        if (mc.level == null || mc.player == null) return List.of("dayLight");
        long day = mc.level.getOverworldClockTime() / 24000;
        long t = mc.level.getOverworldClockTime() % 24000;
        int h = (int) ((t / 1000 + 6) % 24);
        int m = (int) ((t % 1000) * 60 / 1000);
        out.add(String.format(Locale.ROOT, "Day %d  %d:%02d", day, h, m));
        if (w.optBool("showLight", true)) {
            int light = mc.level.getMaxLocalRawBrightness(mc.player.blockPosition());
            out.add("Light " + light);
        }
        return out;
    }

    private static List<String> buildSpeedLines(Minecraft mc, HudWidget w) {
        LocalPlayer p = mc.player;
        if (p == null) return List.of("speedometer");
        double dx = p.getX() - p.xo, dy = p.getY() - p.yo, dz = p.getZ() - p.zo;
        double bps = Math.sqrt(dx * dx + dy * dy + dz * dz) * 20.0;
        if ("kmh".equals(w.optString("unit", "bps"))) {
            return List.of(String.format(Locale.ROOT, "%.1f km/h", bps * 3.6));
        }
        return List.of(String.format(Locale.ROOT, "%.1f B/s", bps));
    }

    /** Block + sky light at the player's feet — the classic "can I see
     *  without torches" readout for caves and night builds. */
    private static List<String> buildLightLines(Minecraft mc, HudWidget w) {
        List<String> out = new ArrayList<>();
        if (mc.level == null || mc.player == null) return List.of("lightLevel");
        BlockPos pos = mc.player.blockPosition();
        if (w.optBool("showBlock", true)) {
            out.add("Block  " + mc.level.getBrightness(LightLayer.BLOCK, pos));
        }
        if (w.optBool("showSky", true)) {
            out.add("Sky    " + mc.level.getBrightness(LightLayer.SKY, pos));
        }
        if (out.isEmpty()) out.add("--");
        return out;
    }

    private static int[] measureStatusPills(Font font, Minecraft mc, HudWidget w) {
        LocalPlayer p = mc != null ? mc.player : null;
        int wpx = 0;
        if (p != null && w.optBool("showSprint", true) && p.isSprinting()) {
            wpx += font.width("SPRINT") + 16;
        }
        if (p != null && w.optBool("showSneak", true) && p.isCrouching()) {
            wpx += font.width("SNEAK") + 16;
        }
        if (wpx == 0) wpx = font.width("SPRINT") + 16;
        return new int[]{wpx, 18};
    }

    private static int[] measureTextWidget(Font font, Minecraft mc, HudWidget w) {
        List<String> lines = mc != null ? buildLinesSafe(mc, w) : List.of(w.kind);
        int maxW = 0;
        for (String s : lines) maxW = Math.max(maxW, font.width(applyTextStyle(w, s)));
        int h = lines.size() * font.lineHeight + 10;
        return new int[]{maxW + 18, Math.max(h, 18)};
    }

    private static List<String> buildLinesSafe(Minecraft mc, HudWidget w) {
        return switch (w.kind) {
            case "fpsPill" -> buildFpsLines(mc, w);
            case "coordsCompass" -> buildCoordsLines(mc, w);
            case "netherCoords" -> buildNetherLines(mc, w);
            case "armorDurability" -> buildArmorLines(mc, w);
            case "potionEffects" -> buildPotionLines(mc, w);
            case "pingTPS" -> buildPingLines(mc, w);
            case "clocks" -> buildClockLines(mc, w);
            case "dayLight" -> buildDayLightLines(mc, w);
            case "speedometer" -> buildSpeedLines(mc, w);
            case "lightLevel" -> buildLightLines(mc, w);
            default -> List.of(w.kind);
        };
    }

    // ------------------------------------------------------------------
    // Text widget rendering
    // ------------------------------------------------------------------

    private static void drawTextWidget(GuiGraphicsExtractor g, Minecraft mc,
                                       HudWidget w, List<String> lines) {
        Font font = mc.font;
        int maxW = 0;
        List<String> styled = new ArrayList<>(lines.size());
        for (String s : lines) {
            String t = applyTextStyle(w, s);
            styled.add(t);
            maxW = Math.max(maxW, font.width(t));
        }
        int padX = 9, padY = 5;
        int bw = maxW + padX * 2;
        int bh = lines.size() * font.lineHeight + padY * 2;
        int x0 = -bw / 2, y0 = -bh / 2;
        int accent = resolveAccent(w, mc);
        drawContainer(g, x0, y0, bw, bh, w, accent);
        int color = resolveText(w, mc);
        boolean shadow = "apple".equals(w.fontStyle)
                || "minecraft".equals(w.containerStyle);
        boolean bold = "bold".equals(w.textStyle);
        for (int i = 0; i < styled.size(); i++) {
            int tx = x0 + padX;
            int ty = y0 + padY + i * font.lineHeight;
            g.text(font, styled.get(i), tx, ty, color, shadow);
            if (bold) g.text(font, styled.get(i), tx + 1, ty, color, shadow);
        }
    }

    private static String applyTextStyle(HudWidget w, String s) {
        if ("uppercase".equals(w.textStyle)) return s.toUpperCase(Locale.ROOT);
        return s;
    }

    // ------------------------------------------------------------------
    // Container styles
    // ------------------------------------------------------------------

    private static void drawContainer(GuiGraphicsExtractor g, int x, int y, int w, int h,
                                      HudWidget widget, int accent) {
        String style = widget.containerStyle == null ? "applePill" : widget.containerStyle;
        int bg = argb(widget.backgroundOpacity, 10, 12, 16);
        switch (style) {
            case "minimalText" -> { return; }
            case "minecraft" -> {
                // Classic MC panel: soft drop shadow, dark translucent fill,
                // gui.png bevel — light top/left, dark bottom/right — plus a
                // faint accent strip under the top edge tying into the widget.
                g.fill(x - 1, y - 1, x + w + 1, y + h + 1, argb(0.30, 0, 0, 0));
                g.fill(x, y, x + w, y + h, argb(widget.backgroundOpacity, 22, 22, 26));
                g.fill(x, y, x + w, y + 1, 0xFF7A7A82);       // top highlight
                g.fill(x, y, x + 1, y + h, 0xFF7A7A82);       // left highlight
                g.fill(x, y + h - 1, x + w, y + h, 0xFF050507); // bottom shadow
                g.fill(x + w - 1, y, x + w, y + h, 0xFF050507); // right shadow
                g.fill(x + 1, y + 1, x + w - 1, y + 2, withAlpha(accent, 0.30));
                g.fill(x + 1, y + 1, x + w - 1, y + h - 1, argb(0.10, 0, 0, 0));
                return;
            }
            case "sharpVoxel" -> {
                g.fill(x, y, x + w, y + h, bg);
                int border = HudConfig.parseColor(widget.borderColor, 0xFFFFFFFF);
                g.fill(x, y, x + w, y + 2, border);
                g.fill(x, y + h - 2, x + w, y + h, border);
                g.fill(x, y, x + 2, y + h, border);
                g.fill(x + w - 2, y, x + w, y + h, border);
                return;
            }
            case "neocraft" -> {
                // NeoCraft glass: a dark rounded panel with a subtle
                // launcher-accent rim and a brighter top hairline —
                // readable like the vanilla HUD, styled like NeoCraft.
                int r = UiSync.cornerRadius() + 2;
                roundedFill(g, x - 1, y - 1, w + 2, h + 2, r, withAlpha(accent, 0.30));
                roundedFill(g, x, y, w, h, Math.max(2, r - 1), bg);
                roundedFill(g, x + 2, y, Math.max(0, w - 4), 1, 1, withAlpha(accent, 0.55));
                roundedFill(g, x, y + h - 1, w, 1, 1, argb(0.25, 0, 0, 0));
                return;
            }
            case "liquidGlass" -> {
                roundedFill(g, x - 1, y - 1, w + 2, h + 2, h / 2 + 1, argb(0.35, 255, 255, 255));
                roundedFill(g, x, y, w, h, h / 2, bg);
                roundedFill(g, x + 2, y + 1, w - 4, Math.max(1, h / 2 - 1), h / 4,
                        argb(0.14, 255, 255, 255));
                roundedFill(g, x, y, w, 1, 1, argb(0.5, 255, 255, 255));
                return;
            }
            case "neonOutline" -> {
                roundedFill(g, x - 2, y - 2, w + 4, h + 4, h / 2 + 2,
                        withAlpha(accent, 0.16));
                roundedFill(g, x - 1, y - 1, w + 2, h + 2, h / 2 + 1,
                        withAlpha(accent, 0.35));
                roundedFill(g, x, y, w, h, h / 2, argb(widget.backgroundOpacity * 0.6, 10, 12, 16));
                roundedFill(g, x, y, w, 1, 1, withAlpha(accent, 0.9));
                roundedFill(g, x, y + h - 1, w, 1, 1, withAlpha(accent, 0.55));
                roundedFill(g, x, y, 1, h, 1, withAlpha(accent, 0.55));
                roundedFill(g, x + w - 1, y, 1, h, 1, withAlpha(accent, 0.55));
                return;
            }
            default -> { // applePill
                roundedFill(g, x - 1, y - 1, w + 2, h + 2, h / 2 + 1, argb(0.28, 255, 255, 255));
                roundedFill(g, x, y, w, h, h / 2, bg);
                roundedFill(g, x, y, w, 1, 1, argb(0.35, 255, 255, 255));
            }
        }
    }

    /**
     * Rounded-rect fill built from scanline fills. Radius is clamped to half
     * the smaller dimension, so {@code r = h/2} produces a true pill.
     */
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

    // ------------------------------------------------------------------
    // Color resolution
    // ------------------------------------------------------------------

    /** Factory-default accent values — widgets/hotbar still carrying one
     *  of these follow the launcher accent from {@code neocraft_ui.json}. */
    private static boolean isFactoryAccent(String hex) {
        if (hex == null) return true;
        String h = hex.trim();
        if (h.startsWith("#")) h = h.substring(1);
        return h.isEmpty()
                || h.equalsIgnoreCase("0A84FF")
                || h.equalsIgnoreCase("5B8CFF");
    }

    private static int resolveText(HudWidget w, Minecraft mc) {
        return resolveColor(w, mc, false);
    }

    private static int resolveAccent(HudWidget w, Minecraft mc) {
        return resolveColor(w, mc, true);
    }

    private static int resolveColor(HudWidget w, Minecraft mc, boolean accent) {
        String mode = w.colorMode == null ? "static" : w.colorMode;
        switch (mode) {
            case "chroma" -> {
                float hue = (System.currentTimeMillis() / 1000f * 0.22f) % 1f;
                return 0xFF000000 | (Color.HSBtoRGB(hue, 0.85f, 1f) & 0xFFFFFF);
            }
            case "biome" -> {
                if (mc.level != null && mc.player != null) {
                    return biomeColor(mc.level, mc.player.blockPosition());
                }
                return 0xFF7CFC00;
            }
            case "reactive" -> {
                return reactiveColor(mc);
            }
            default -> {
                String hex = accent ? w.accentColor : w.textColor;
                // Widgets still carrying a factory-default accent follow
                // the launcher accent synced through neocraft_ui.json;
                // custom per-widget colors are left untouched.
                if (accent && isFactoryAccent(hex)) {
                    return UiSync.accentColor(0xFF0A84FF);
                }
                int fallback = accent ? 0xFF0A84FF : 0xFFFFFFFF;
                return HudConfig.parseColor(hex, fallback);
            }
        }
    }

    private static int reactiveColor(Minecraft mc) {
        int fps = mc.getFps();
        float health = mc.player != null ? mc.player.getHealth() : 20f;
        if (fps < 30 || health <= 4f) return 0xFFFF3B30;
        if (fps < 60 || health < 10f) return 0xFFFF9500;
        return 0xFF34C759;
    }

    private static int biomeColor(ClientLevel level, BlockPos pos) {
        String path = level.getBiome(pos).unwrapKey()
                .map(k -> k.identifier().getPath()).orElse("");
        float hue;
        if (path.contains("nether")) hue = 0.78f;
        else if (path.contains("end")) hue = 0.70f;
        else if (path.contains("ocean") || path.contains("river") || path.contains("deep")) hue = 0.55f;
        else if (path.contains("desert") || path.contains("badlands") || path.contains("mesa")) hue = 0.12f;
        else if (path.contains("snow") || path.contains("ice") || path.contains("frozen")) hue = 0.55f;
        else if (path.contains("mushroom")) hue = 0.95f;
        else if (path.contains("swamp") || path.contains("mangrove")) hue = 0.32f;
        else if (path.contains("jungle")) hue = 0.28f;
        else if (path.contains("taiga") || path.contains("old_growth")) hue = 0.40f;
        else if (path.contains("mountain") || path.contains("peak") || path.contains("stony")) hue = 0.08f;
        else hue = 0.30f;
        return 0xFF000000 | (Color.HSBtoRGB(hue, 0.75f, 1f) & 0xFFFFFF);
    }

    // ------------------------------------------------------------------
    // Keystrokes widget
    // ------------------------------------------------------------------

    private static void drawKeystrokes(GuiGraphicsExtractor g, Minecraft mc,
                                       HudWidget w) {
        Font font = mc.font;
        final int K = 22, GAP = 4, P = K + GAP;
        final int clusterW = 3 * K + 2 * GAP; // 74
        final int pad = 7;
        final int left = -(K + GAP) - pad;
        final int right = pad + clusterW;
        final int gridH = 3 * P + K;
        int showCps = w.optBool("showCPS", true) ? font.lineHeight + 3 : 0;
        int bw = right - left;
        int bh = pad + gridH + pad + showCps;
        int x0 = -bw / 2, y0 = -bh / 2;
        int accent = resolveAccent(w, mc);
        int bg = argb(w.backgroundOpacity, 10, 12, 16);
        drawContainer(g, x0, y0, bw, bh, w, accent);

        double anim = Math.max(0.1, Math.min(2.0, w.optNum("animationSpeed", 1.0)));
        long t = System.currentTimeMillis();
        int pressed = HudConfig.parseColor(w.optString("pressedColor", "#0A84FF"), 0xFF0A84FF);

        record Key(int x, int y, int w, int h, String label, boolean down) { }
        List<Key> keys = new ArrayList<>();
        boolean showMouse = w.optBool("showMouse", true);
        boolean showShift = w.optBool("showShift", true);
        boolean showSprint = w.optBool("showSprint", true);
        int mx = left + pad;
        if (showMouse) {
            keys.add(new Key(mx, pad + P, K, K, "LMB", mc.mouseHandler.isLeftPressed()));
            keys.add(new Key(mx, pad + 2 * P, K, K, "RMB", mc.mouseHandler.isRightPressed()));
        }
        keys.add(new Key(pad + P, pad, K, K, "W", mc.options.keyUp.isDown()));
        keys.add(new Key(pad, pad + P, K, K, "A", mc.options.keyLeft.isDown()));
        keys.add(new Key(pad + P, pad + P, K, K, "S", mc.options.keyDown.isDown()));
        keys.add(new Key(pad + 2 * P, pad + P, K, K, "D", mc.options.keyRight.isDown()));
        keys.add(new Key(pad, pad + 2 * P, clusterW, K, "SPACE", mc.options.keyJump.isDown()));
        if (showShift) {
            keys.add(new Key(pad, pad + 3 * P, 35, K, "SHIFT", mc.options.keyShift.isDown()));
        }
        if (showSprint) {
            keys.add(new Key(pad + 39, pad + 3 * P, 35, K, "SPRINT", mc.options.keySprint.isDown()));
        }

        boolean mcKeys = "minecraft".equals(w.containerStyle);
        for (Key k : keys) {
            int kx = x0 + k.x(), ky = y0 + k.y();
            if (mcKeys) {
                // MC gui.png button: raised bevel unpressed, sunken when held.
                if (k.down()) {
                    g.fill(kx, ky, kx + k.w(), ky + k.h(), withAlpha(pressed, 0.9));
                    g.fill(kx, ky, kx + k.w(), ky + 1, 0xFF3A3A44);
                    g.fill(kx, ky + k.h() - 1, kx + k.w(), ky + k.h(), 0xFFB9B9C4);
                    g.fill(kx, ky, kx + 1, ky + k.h(), 0xFF3A3A44);
                    g.fill(kx + k.w() - 1, ky, kx + k.w(), ky + k.h(), 0xFFB9B9C4);
                } else {
                    g.fill(kx, ky, kx + k.w(), ky + k.h(), argb(0.85, 30, 30, 36));
                    g.fill(kx, ky, kx + k.w(), ky + 1, 0xFF9C9CA8);
                    g.fill(kx, ky + k.h() - 1, kx + k.w(), ky + k.h(), 0xFF141417);
                    g.fill(kx, ky, kx + 1, ky + k.h(), 0xFF9C9CA8);
                    g.fill(kx + k.w() - 1, ky, kx + k.w(), ky + k.h(), 0xFF141417);
                }
            } else {
                int fill;
                if (k.down()) {
                    float pulse = 0.75f + 0.25f * (float) Math.sin(t * 0.006 * anim);
                    fill = withAlpha(pressed, 0.35 + 0.45 * pulse);
                } else {
                    fill = bg;
                }
                g.fill(kx, ky, kx + k.w(), ky + k.h(), fill);
                g.fill(kx, ky, kx + k.w(), ky + 1, argb(0.3, 255, 255, 255));
                g.fill(kx, ky + k.h() - 1, kx + k.w(), ky + k.h(), argb(0.3, 255, 255, 255));
            }
            String label = k.label();
            int tx = kx + (k.w() - font.width(label)) / 2;
            int ty = ky + (k.h() - font.lineHeight) / 2 + 1;
            g.text(font, label, tx, ty, k.down() ? 0xFFFFFFFF : 0xFFDDDDDD, mcKeys);
        }

        if (w.optBool("showCPS", true)) {
            String cps = cps() + " CPS";
            int tx = x0 + (bw - font.width(cps)) / 2;
            int ty = y0 + bh - pad - font.lineHeight + 1;
            g.text(font, cps, tx, ty, resolveText(w, mc), false);
        }
    }

    // ------------------------------------------------------------------
    // Status pills widget
    // ------------------------------------------------------------------

    private static void drawStatusPills(GuiGraphicsExtractor g, Minecraft mc, HudWidget w) {
        LocalPlayer p = mc.player;
        if (p == null) return;
        Font font = mc.font;
        int total = measureStatusPills(font, mc, w)[0];
        int x = -total / 2;
        int y = -9;
        boolean mcStyle = "minecraft".equals(w.containerStyle);
        if (w.optBool("showSprint", true) && p.isSprinting()) {
            x = drawMiniPill(g, font, x, y, "SPRINT", 0xFF34C759, mcStyle);
        }
        if (w.optBool("showSneak", true) && p.isCrouching()) {
            drawMiniPill(g, font, x, y, "SNEAK", 0xFF0A84FF, mcStyle);
        }
    }

    private static int drawMiniPill(GuiGraphicsExtractor g, Font font, int x, int y,
                                    String label, int color, boolean mcStyle) {
        int w = font.width(label) + 12;
        int h = 15;
        if (mcStyle) {
            // MC-style chip: dark fill, light top/left, dark bottom/right.
            g.fill(x, y, x + w, y + h, withAlpha(color, 0.30));
            g.fill(x, y, x + w, y + 1, 0xFF9C9CA8);
            g.fill(x, y, x + 1, y + h, 0xFF9C9CA8);
            g.fill(x, y + h - 1, x + w, y + h, 0xFF141417);
            g.fill(x + w - 1, y, x + w, y + h, 0xFF141417);
            g.text(font, label, x + 6, y + 3, 0xFFFFFFFF, true);
        } else {
            roundedFill(g, x, y, w, h, h / 2, withAlpha(color, 0.4));
            g.text(font, label, x + 6, y + 3, 0xFFFFFFFF, false);
        }
        return x + w + 6;
    }

    // ------------------------------------------------------------------
    // Vanilla skin overlays
    // ------------------------------------------------------------------

    /** Frosted glass panel behind the hotbar — drawn BEFORE the HOTBAR layer. */
    private static void renderHotbarGlass(GuiGraphicsExtractor g, Minecraft mc,
                                          int vw, int vh, HotbarUi ui) {
        int cx = vw / 2;
        int x0 = cx - 91, x1 = cx + 91;
        roundedFill(g, x0 - 8, vh - 37, (x1 - x0) + 16, vh - 1 - (vh - 37), 8,
                argb(0.30, 8, 10, 14));
        roundedFill(g, x0 - 8, vh - 37, (x1 - x0) + 16, 1, 1, argb(0.4, 255, 255, 255));
    }

    /** Selection highlight, item counts and XP accent — drawn over the hotbar. */
    private static void renderHotbarOverlay(GuiGraphicsExtractor g, Minecraft mc,
                                            int vw, int vh, HotbarUi ui) {
        if (mc.player == null) return;
        Font font = mc.font;
        int cx = vw / 2;
        int x0 = cx - 91, x1 = cx + 91;
        int yHot = vh - 22;
        int accent = isFactoryAccent(ui.accentColor)
                ? UiSync.accentColor(0xFF0A84FF)
                : HudConfig.parseColor(ui.accentColor, 0xFF0A84FF);
        int xpAccent = HudConfig.parseColor(ui.xpAccentColor, 0xFF7CFC00);

        Inventory inv = mc.player.getInventory();
        int sel = inv.getSelectedSlot();
        float target = x0 + sel * 20 + 1;
        if (hotbarSelAnim < 0) hotbarSelAnim = target;
        if (ui.animateSelection) {
            hotbarSelAnim += (target - hotbarSelAnim) * 0.35f;
        } else {
            hotbarSelAnim = target;
        }
        roundedFill(g, (int) hotbarSelAnim - 1, yHot + 1, 20, 19, 4,
                withAlpha(accent, 0.38));
        g.fill((int) hotbarSelAnim, yHot + 2, (int) hotbarSelAnim + 18, yHot + 3,
                withAlpha(accent, 0.7));

        if (ui.showNumbers) {
            for (int i = 0; i < 9; i++) {
                ItemStack stack = inv.getItem(i);
                if (stack.isEmpty()) continue;
                int count = stack.getCount();
                if (count <= 1 && !stack.isDamageableItem()) continue;
                String label = count > 1 ? String.valueOf(count)
                        : String.valueOf(stack.getMaxDamage() - stack.getDamageValue());
                int sx = x0 + i * 20 + 20;
                int sy = yHot + 20;
                int tw = font.width(label);
                g.text(font, label, sx - tw - 2, sy - font.lineHeight - 1,
                        count > 1 ? 0xFFFFFFFF : 0xFFFFAA00, true);
            }
        }

        float xp = mc.player.experienceProgress;
        int xpY = vh - 27;
        g.fill(x0, xpY, x1, xpY + 2, argb(0.35, 255, 255, 255));
        g.fill(x0, xpY, x0 + (int) ((x1 - x0) * xp), xpY + 2,
                withAlpha(xpAccent, 0.95));
        if (mc.player.experienceLevel > 0) {
            String lvl = String.valueOf(mc.player.experienceLevel);
            g.text(font, lvl, cx - font.width(lvl) / 2, xpY - font.lineHeight - 1, 0xFFFFFFFF, true);
        }
    }

    private static void renderScoreboardVeil(GuiGraphicsExtractor g, Minecraft mc,
                                             int vw, int vh, ScoreboardUi ui) {
        Objective obj = mc.level.getScoreboard().getDisplayObjective(DisplaySlot.SIDEBAR);
        if (obj == null) return;
        Font font = mc.font;
        String title = obj.getDisplayName().getString();
        int titleW = font.width(title);
        int entries = mc.level.getScoreboard().listPlayerScores(obj).size();
        int w = Math.max(titleW, 60) + 12;
        int h = 14 + Math.max(3, entries) * font.lineHeight + 6;
        double sc = ui.scale;
        int pw = (int) (w * sc), ph = (int) (h * sc);
        int px = vw - pw - 8;
        int py = 6;
        roundedFill(g, px - 2, py - 2, pw + 4, ph + 4, 6, argb(0.22, 255, 255, 255));
        roundedFill(g, px, py, pw, ph, 5, argb(0.45, 6, 8, 12));
    }

    private static void renderChatVeil(GuiGraphicsExtractor g, Minecraft mc,
                                       int vw, int vh, ChatUi ui) {
        int w = Math.min(330, vw / 2);
        int h = 120;
        int x = 4, y = vh - 40 - h - 8;
        int color = argb(ui.opacity * 0.30, 5, 7, 10);
        if (ui.roundedBox) {
            roundedFill(g, x, y, w, h, 7, color);
        } else {
            g.fill(x, y, x + w, y + h, color);
        }
    }

    // ------------------------------------------------------------------
    // Custom crosshair
    // ------------------------------------------------------------------

    private static void renderCrosshair(GuiGraphicsExtractor g, Minecraft mc,
                                        int vw, int vh, CrosshairUi ui) {
        int cx = vw / 2, cy = vh / 2;
        int size = Math.max(2, ui.size);
        int thick = Math.max(1, ui.thickness);
        int gap = Math.max(0, ui.gap);
        int color;
        if ("static".equals(ui.colorMode)) {
            color = HudConfig.parseColor(ui.color, 0xFFFFFFFF);
        } else {
            HudWidget pseudo = new HudWidget();
            pseudo.colorMode = ui.colorMode;
            pseudo.accentColor = ui.color;
            pseudo.textColor = ui.color;
            color = resolveColor(pseudo, mc, false);
        }
        if (ui.showCooldown && mc.player != null) {
            float cd = mc.player.getAttackStrengthScale(0f);
            int a = (int) (((color >>> 24) & 0xFF) * (0.45f + 0.55f * cd));
            color = (a << 24) | (color & 0x00FFFFFF);
        }
        g.fill(cx - gap - size, cy - thick / 2, cx - gap, cy + thick - thick / 2, color);
        g.fill(cx + gap, cy - thick / 2, cx + gap + size, cy + thick - thick / 2, color);
        g.fill(cx - thick / 2, cy - gap - size, cx + thick - thick / 2, cy - gap, color);
        g.fill(cx - thick / 2, cy + gap, cx + thick - thick / 2, cy + gap + size, color);
        if ("dot".equals(ui.shape)) {
            g.fill(cx - 1, cy - 1, cx + 1, cy + 1, color);
        }
    }

    // ------------------------------------------------------------------
    // Minimap
    // ------------------------------------------------------------------

    private static final class Minimap {
        private static final int RES = 44;
        private final int[] colors = new int[RES * RES];
        private int originX, originZ;
        private double cellBlocks;
        private double radiusBlocks;
        private long lastSample;
        private int sampleCX, sampleCZ;

        void draw(GuiGraphicsExtractor g, Minecraft mc, HudWidget w) {
            if (mc.level == null || mc.player == null) return;
            Font font = mc.font;
            int size = 124;
            int x0 = -size / 2, y0 = -size / 2;
            String shape = w.optString("shape", "circle");
            boolean circle = "circle".equals(shape);
            int border = HudConfig.parseColor(w.borderColor, 0xFFFFFFFF);
            int bg = argb(Math.max(w.backgroundOpacity, 0.55), 8, 14, 10);

            ensureSamples(mc, w);

            if (circle) {
                drawCircle(g, x0, y0, size, bg);
            } else {
                roundedFill(g, x0, y0, size, size, 10, bg);
            }

            double yaw = Math.toRadians(mc.player.getYRot());
            double fx = -Math.sin(yaw), fz = Math.cos(yaw);
            double rx = -fz, rz = fx;
            double px = mc.player.getX(), pz = mc.player.getZ();
            double cellPx = (double) size / RES;
            int half = size / 2;

            for (int j = 0; j < RES; j++) {
                for (int i = 0; i < RES; i++) {
                    double nx = (i + 0.5) / RES * 2.0 - 1.0;
                    double ny = (j + 0.5) / RES * 2.0 - 1.0;
                    if (!insideMask(nx, ny, circle)) continue;
                    double wx = (nx * rx - ny * fx) * radiusBlocks;
                    double wz = (nx * rz - ny * fz) * radiusBlocks;
                    double bx = px + wx, bz = pz + wz;
                    int sx = (int) Math.floor((bx - originX) / cellBlocks);
                    int sz = (int) Math.floor((bz - originZ) / cellBlocks);
                    if (sx < 0 || sx >= RES || sz < 0 || sz >= RES) continue;
                    int col = colors[sz * RES + sx];
                    if (col == 0) continue;
                    int cxp = x0 + (int) (i * cellPx);
                    int cyp = y0 + (int) (j * cellPx);
                    int cw = (int) Math.ceil(cellPx);
                    g.fill(cxp, cyp, cxp + cw, cyp + cw, col);
                }
            }

            if (w.optBool("showPlayers", true)) {
                for (var pl : mc.level.players()) {
                    if (pl == mc.player) continue;
                    drawEntityDot(g, mc.player, pl.getX(), pl.getZ(), x0, y0, half,
                            rx, rz, fx, fz, radiusBlocks, 0xFFFFFFFF);
                }
            }
            if (w.optBool("showMobs", false)) {
                AABB box = new AABB(mc.player.blockPosition()).inflate(radiusBlocks);
                int drawn = 0;
                for (LivingEntity e : mc.level.getEntitiesOfClass(LivingEntity.class, box)) {
                    if (drawn++ > 200) break;
                    if (e == mc.player || e instanceof Player) continue;
                    drawEntityDot(g, mc.player, e.getX(), e.getZ(), x0, y0, half,
                            rx, rz, fx, fz, radiusBlocks, 0xFFFF6666);
                }
            }

            if (w.optBool("deathWaypoint", true)) {
                BlockPos dp = deathWaypoint();
                if (dp != null) {
                    drawEntityDot(g, mc.player, dp.getX() + 0.5, dp.getZ() + 0.5,
                            x0, y0, half, rx, rz, fx, fz, radiusBlocks, 0xFFFF3B30);
                }
            }

            int ccx = x0 + size / 2, ccy = y0 + size / 2;
            g.fill(ccx - 1, ccy - 6, ccx + 2, ccy + 2, 0xFFFFFFFF);
            g.fill(ccx - 2, ccy - 1, ccx + 3, ccy + 2, 0xFF0A84FF);
            g.fill(ccx - 3, ccy, ccx + 4, ccy + 1, 0xFF0A84FF);

            double nx = 0, nz = -1;
            double pxn = nx * rx + nz * rz;
            double pynUp = nx * fx + nz * fz;
            if (!w.optBool("northLock", false)) {
                int nxp = x0 + size / 2 + (int) (pxn * (size / 2 - 10));
                int nyp = y0 + size / 2 - (int) (pynUp * (size / 2 - 10));
                g.text(font, "N", nxp - font.width("N") / 2, nyp - 4, 0xFFFFFFFF, true);
            } else {
                g.text(font, "N", x0 + size / 2 - font.width("N") / 2, y0 + 3, 0xFFFFFFFF, true);
            }

            if (circle) {
                drawCircleBorder(g, x0, y0, size, border);
            } else {
                g.fill(x0, y0, x0 + size, y0 + 1, border);
                g.fill(x0, y0 + size - 1, x0 + size, y0 + size, border);
                g.fill(x0, y0, x0 + 1, y0 + size, border);
                g.fill(x0 + size - 1, y0, x0 + size, y0 + size, border);
            }
        }

        private boolean insideMask(double nx, double ny, boolean circle) {
            if (circle) return nx * nx + ny * ny <= 1.0;
            double ax = Math.abs(nx), ay = Math.abs(ny);
            return ax <= 0.92 && ay <= 0.92;
        }

        private void drawCircle(GuiGraphicsExtractor g, int x, int y, int size, int color) {
            int r = size / 2, cx = x + r;
            for (int j = 0; j < size; j++) {
                double dy = j + 0.5 - r;
                double dx = Math.sqrt(Math.max(0, r * r - dy * dy));
                int half = (int) Math.round(r - dx);
                g.fill(cx - half, y + j, cx + half, y + j + 1, color);
            }
        }

        private void drawCircleBorder(GuiGraphicsExtractor g, int x, int y, int size, int color) {
            int r = size / 2, cx = x + r;
            for (int j = 0; j < size; j++) {
                double dy = j + 0.5 - r;
                double dx = Math.sqrt(Math.max(0, r * r - dy * dy));
                int half = (int) Math.round(r - dx);
                if (half <= 0) continue;
                int lx = cx - half;
                g.fill(lx, y + j, lx + 1, y + j + 1, color);
                g.fill(cx + half - 1, y + j, cx + half, y + j + 1, color);
            }
        }

        private void drawEntityDot(GuiGraphicsExtractor g, LocalPlayer self,
                                   double ex, double ez, int x0, int y0, int half,
                                   double rx, double rz, double fx, double fz,
                                   double radiusBlocks, int color) {
            double dx = ex - self.getX(), dz = ez - self.getZ();
            double sx = (dx * rx + dz * rz) / radiusBlocks;
            double sy = -(dx * fx + dz * fz) / radiusBlocks;
            if (Math.abs(sx) > 0.95 || Math.abs(sy) > 0.95) return;
            int px = x0 + half + (int) (sx * half) - 1;
            int py = y0 + half + (int) (sy * half) - 1;
            g.fill(px, py, px + 3, py + 3, color);
        }

        private void ensureSamples(Minecraft mc, HudWidget w) {
            long now = System.currentTimeMillis();
            LocalPlayer p = mc.player;
            BlockPos bp = p.blockPosition();
            double zoom = Math.max(0.25, w.optNum("zoom", 1.0));
            radiusBlocks = Math.max(10, Math.min(90, 26 / zoom));
            cellBlocks = (radiusBlocks * 2) / RES;
            boolean recenter = bp.getX() != sampleCX || bp.getZ() != sampleCZ
                    || now - lastSample > 400L;
            if (!recenter) return;
            lastSample = now;
            sampleCX = bp.getX();
            sampleCZ = bp.getZ();
            originX = bp.getX() - (int) radiusBlocks;
            originZ = bp.getZ() - (int) radiusBlocks;
            ClientLevel level = mc.level;
            for (int j = 0; j < RES; j++) {
                for (int i = 0; i < RES; i++) {
                    int wx = originX + (int) (i * cellBlocks);
                    int wz = originZ + (int) (j * cellBlocks);
                    colors[j * RES + i] = sampleColor(level, wx, wz);
                }
            }
        }

        private int sampleColor(ClientLevel level, int x, int z) {
            int h = level.getHeight(Heightmap.Types.WORLD_SURFACE, x, z);
            int y = Math.min(h - 1, level.getMaxY() - 1);
            y = Math.max(y, level.getMinY());
            BlockPos pos = new BlockPos(x, y, z);
            var st = level.getBlockState(pos);
            if (st.isAir()) {
                for (int dy = 1; dy <= 6; dy++) {
                    BlockPos below = pos.below(dy);
                    if (below.getY() < level.getMinY()) break;
                    st = level.getBlockState(below);
                    if (!st.isAir()) break;
                }
            }
            var fluid = st.getFluidState();
            if (fluid.is(FluidTags.WATER)) return 0xFF2E5FA3;
            if (fluid.is(FluidTags.LAVA)) return 0xFFCF4A1B;
            int rgb = st.getMapColor(level, pos).col;
            int r = ((rgb >> 16) & 0xFF) * 3 / 4;
            int gg = ((rgb >> 8) & 0xFF) * 3 / 4;
            int b = (rgb & 0xFF) * 3 / 4;
            return 0xFF000000 | (r << 16) | (gg << 8) | b;
        }
    }

    // ------------------------------------------------------------------
    // Small helpers
    // ------------------------------------------------------------------

    private static void appendLast(List<String> out, String suffix) {
        if (out.isEmpty()) { out.add(suffix.trim()); return; }
        out.set(out.size() - 1, out.get(out.size() - 1) + suffix);
    }

    private static String shortSlot(String name) {
        return switch (name) {
            case "Helmet" -> "Hel";
            case "Chest" -> "Ch";
            case "Legs" -> "Leg";
            default -> "Boot";
        };
    }

    private static String facingName(float yaw) {
        float y = ((yaw % 360) + 360) % 360;
        String[] names = {"S", "SW", "W", "NW", "N", "NE", "E", "SE"};
        int idx = (int) Math.round(y / 45.0) % 8;
        return names[idx];
    }

    private static String biomeName(ClientLevel level, BlockPos pos) {
        String path = level.getBiome(pos).unwrapKey()
                .map(k -> k.identifier().getPath()).orElse("unknown");
        String[] parts = path.split("_");
        StringBuilder sb = new StringBuilder();
        for (String part : parts) {
            if (part.isEmpty()) continue;
            if (sb.length() > 0) sb.append(' ');
            sb.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1));
        }
        return sb.length() == 0 ? "Unknown" : sb.toString();
    }

    /** Re-applies the alpha channel of an existing 0xAARRGGBB color. */
    private static int withAlpha(int color, double alpha) {
        int a = (int) (Math.max(0, Math.min(1, alpha)) * 255);
        return (a << 24) | (color & 0x00FFFFFF);
    }

    private static int argb(double alpha, int r, int g, int b) {
        int a = (int) (Math.max(0, Math.min(1, alpha)) * 255);
        return (a << 24) | (r << 16) | (g << 8) | b;
    }
}
