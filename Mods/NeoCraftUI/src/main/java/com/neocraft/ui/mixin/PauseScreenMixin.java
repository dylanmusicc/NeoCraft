package com.neocraft.ui.mixin;

import com.neocraft.ui.NeoCraftMenuScreen;
import com.neocraft.ui.UiTheme;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Themes the pause screen and adds a "NeoCraft" button that opens the
 * in-game NeoCraft menu (servers, design, HUD). Sits above the
 * NeoCraft Host button when the beta host mod is installed.
 */
@Mixin(PauseScreen.class)
public abstract class PauseScreenMixin extends Screen {

    protected PauseScreenMixin() {
        super(Component.empty());
    }

    @Inject(method = "extractRenderState", at = @At("HEAD"), require = 0)
    private void neocraftUi$themePause(GuiGraphicsExtractor graphics,
                                     int mouseX, int mouseY, float partialTick,
                                     CallbackInfo ci) {
        UiTheme.renderBackdrop(graphics, graphics.guiWidth(), graphics.guiHeight(), "pause");
    }

    @Inject(method = "init", at = @At("TAIL"))
    private void neocraftUi$addMenuButton(CallbackInfo ci) {
        Minecraft mc = Minecraft.getInstance();
        this.addRenderableWidget(
                Button.builder(
                                Component.translatable("neocraft-ui.menu.button"),
                                b -> mc.gui.setScreen(new NeoCraftMenuScreen(this)))
                        .bounds(this.width / 2 - 100, this.height - 46, 200, 20)
                        .build());
    }
}
