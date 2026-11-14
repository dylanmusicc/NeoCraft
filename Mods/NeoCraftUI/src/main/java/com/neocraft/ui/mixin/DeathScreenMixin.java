package com.neocraft.ui.mixin;

import com.neocraft.ui.UiTheme;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.screens.DeathScreen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Themes the death screen backdrop. */
@Mixin(DeathScreen.class)
public abstract class DeathScreenMixin {

    @Inject(method = "extractRenderState", at = @At("HEAD"), require = 0)
    private void neocraftUi$themeDeath(GuiGraphicsExtractor graphics,
                                     int mouseX, int mouseY, float partialTick,
                                     CallbackInfo ci) {
        UiTheme.renderBackdrop(graphics, graphics.guiWidth(), graphics.guiHeight(), "death");
    }
}
