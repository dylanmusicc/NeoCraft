package com.neocraft.hud.mixin;

import com.neocraft.hud.HudConfig;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.screens.TitleScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Draws the configured accent tint over the main menu. The injection is
 * defensive (require = 0): if the 26.3 {@code extractRenderState} signature
 * differs from the expected one the tint simply does not apply instead of
 * crashing.
 */
@Mixin(TitleScreen.class)
public abstract class TitleScreenMixin {

    @Inject(method = "extractRenderState", at = @At("TAIL"), require = 0)
    private void neocraft$tintTitleScreen(GuiGraphicsExtractor graphics,
                                        int mouseX, int mouseY, float partialTick,
                                        CallbackInfo ci) {
        HudConfig.TitleUi tint = HudConfig.ui().titleScreen;
        if (tint == null || !tint.enabled) return;
        int rgb = HudConfig.parseColor(tint.tintColor, 0xFF0A84FF) & 0x00FFFFFF;
        int alpha = (int) (Math.max(0, Math.min(1, tint.opacity)) * 255) << 24;
        graphics.fill(0, 0, graphics.guiWidth(), graphics.guiHeight(), alpha | rgb);
    }
}
