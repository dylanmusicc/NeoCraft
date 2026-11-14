package com.neocraft.ui;

import net.minecraft.client.gui.GuiGraphicsExtractor;

/**
 * Shared backdrop renderer for the NeoCraft UI theme.
 *
 * <p>Injected at the HEAD of each screen's {@code extractRenderState} so
 * the theme paints over the vanilla background (panorama, dirt, gradient)
 * but <em>under</em> the screen's widgets — buttons and labels stay fully
 * readable in both modes.</p>
 *
 * <ul>
 *   <li><b>Theme mode</b>: a flat accent-tinted overlay at
 *   {@code tintOpacity}.</li>
 *   <li><b>Full redesign</b>: a vertical accent→near-black gradient plus
 *   a small "NEOCRAFT" wordmark and accent rule at the top of the
 *   screen.</li>
 * </ul>
 */
public final class UiTheme {

    private UiTheme() { }

    /** Paints the configured backdrop for {@code screenId}. No-op when
     *  the mod or that screen is disabled. */
    public static void renderBackdrop(GuiGraphicsExtractor g, int width, int height, String screenId) {
        if (!UiConfig.screenEnabled(screenId)) return;
        UiConfig.UiState s = UiConfig.state();

        if (s.fullRedesign) {
            renderGradient(g, width, height, s);
            renderWordmark(g, width, s);
        } else {
            int rgb = UiConfig.parseColor(s.tintColor, 0xFF5B8CFF) & 0x00FFFFFF;
            int alpha = (int) (Math.max(0, Math.min(1, s.tintOpacity)) * 255) << 24;
            g.fill(0, 0, width, height, alpha | rgb);
        }
    }

    // ------------------------------------------------------------------

    /** Vertical gradient: accent (slightly transparent) at the top fading
     *  to a deep blue-black at the bottom. Painted in horizontal strips —
     *  cheap enough for a once-per-frame screen background. */
    private static void renderGradient(GuiGraphicsExtractor g, int w, int h, UiConfig.UiState s) {
        int top = UiConfig.parseColor(s.accentColor, 0xFF5B8CFF);
        int bottom = 0xF0080D16;
        int strips = Math.max(8, h / 4);
        for (int i = 0; i < strips; i++) {
            int y0 = (int) ((long) i * h / strips);
            int y1 = (int) ((long) (i + 1) * h / strips);
            float t = (float) i / (strips - 1);
            g.fill(0, y0, w, y1, lerpColor(top, bottom, t));
        }
        // Extra accent bloom at the very top for the NeoCraft feel.
        int bloom = UiConfig.parseColor(s.accentColor, 0xFF5B8CFF);
        int bloomAlpha = 0x40;
        int bloomRgb = bloom & 0x00FFFFFF;
        int bloomH = Math.min(h / 3, 120);
        for (int i = 0; i < bloomH; i += 2) {
            float f = 1f - (float) i / bloomH;
            int a = (int) (bloomAlpha * f * f);
            g.fill(0, i, w, i + 2, (a << 24) | bloomRgb);
        }
    }

    /** Small NeoCraft wordmark + accent rule, drawn at the top center.
     *  Kept subtle so it doesn't fight the Mojang logo / screen titles. */
    private static void renderWordmark(GuiGraphicsExtractor g, int width, UiConfig.UiState s) {
        net.minecraft.client.Minecraft mc = net.minecraft.client.Minecraft.getInstance();
        String text = "N E O C R A F T";
        int tw = mc.font.width(text);
        int x = (width - tw) / 2;
        int y = 8;
        int accent = UiConfig.parseColor(s.accentColor, 0xFF5B8CFF);
        // Soft shadow pass then accent pass.
        g.text(mc.font, text, x + 1, y + 1, 0x66000000);
        g.text(mc.font, text, x, y, accent);
        int ruleW = 64;
        int rx = (width - ruleW) / 2;
        int ry = y + 12;
        int rgb = accent & 0x00FFFFFF;
        g.fill(rx, ry, rx + ruleW, ry + 1, 0xCC000000 | rgb);
    }

    private static int lerpColor(int a, int b, float t) {
        int ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF, aa = (a >> 24) & 0xFF;
        int br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF, ba = (b >> 24) & 0xFF;
        int r = (int) (ar + (br - ar) * t);
        int gg = (int) (ag + (bg - ag) * t);
        int bl = (int) (ab + (bb - ab) * t);
        int al = (int) (aa + (ba - aa) * t);
        return (al << 24) | (r << 16) | (gg << 8) | bl;
    }
}
