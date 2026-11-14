package com.neocraft.ui.mixin;

import com.neocraft.ui.UiTheme;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.options.OptionsScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Themes the options screen backdrop.
 *
 * <p>{@code OptionsScreen} does not declare its own
 * {@code extractRenderState} — it inherits {@link Screen}'s — so a mixin
 * targeting the options class directly would never fire. This mixin
 * hooks {@code Screen.extractRenderState} instead and gates on
 * {@code instanceof OptionsScreen}; every other screen pays one cheap
 * type check per frame.</p>
 */
@Mixin(Screen.class)
public abstract class OptionsScreenMixin {

    @Inject(method = "extractRenderState", at = @At("HEAD"), require = 0)
    private void neocraftUi$themeOptions(GuiGraphicsExtractor graphics,
                                       int mouseX, int mouseY, float partialTick,
                                       CallbackInfo ci) {
        if ((Object) this instanceof OptionsScreen) {
            UiTheme.renderBackdrop(graphics, graphics.guiWidth(), graphics.guiHeight(), "options");
        }
    }
}
