package com.neocraft.ui.mixin;

import com.neocraft.ui.NeoCraftMenuScreen;
import com.neocraft.ui.UiTheme;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.network.chat.Component;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Themes the title screen and adds a small "NeoCraft" button (top-right)
 * that opens the in-game NeoCraft menu. Injection at HEAD of
 * {@code extractRenderState} paints the NeoCraft backdrop over the
 * panorama but under the widgets; {@code require = 0} keeps the mod safe
 * if the signature drifts.
 */
@Mixin(TitleScreen.class)
public abstract class TitleScreenMixin extends Screen {

    protected TitleScreenMixin() {
        super(Component.empty());
    }

    @Inject(method = "extractRenderState", at = @At("HEAD"), require = 0)
    private void neocraftUi$themeTitle(GuiGraphicsExtractor graphics,
                                     int mouseX, int mouseY, float partialTick,
                                     CallbackInfo ci) {
        UiTheme.renderBackdrop(graphics, graphics.guiWidth(), graphics.guiHeight(), "title");
    }

    @Inject(method = "init", at = @At("TAIL"))
    private void neocraftUi$addMenuButton(CallbackInfo ci) {
        Minecraft mc = Minecraft.getInstance();
        this.addRenderableWidget(
                Button.builder(
                                Component.translatable("neocraft-ui.menu.button"),
                                b -> mc.gui.setScreen(new NeoCraftMenuScreen(this)))
                        .bounds(this.width - 104, 8, 96, 16)
                        .build());
    }
}
