package com.neocraft.hud.mixin;

import com.neocraft.hud.NeoCraftHudConfigScreen;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Adds a "NeoCraft Studio" button to the pause menu that opens the HUD editor.
 * The button is appended at TAIL of {@code init()} so it sits below the
 * vanilla grid regardless of how many buttons other mods added.
 */
@Mixin(PauseScreen.class)
public abstract class PauseScreenMixin extends Screen {

    protected PauseScreenMixin() {
        super(Component.empty());
    }

    @Inject(method = "init", at = @At("TAIL"))
    private void neocraft$addStudioButton(CallbackInfo ci) {
        Minecraft mc = Minecraft.getInstance();
        this.addRenderableWidget(
                Button.builder(
                                Component.translatable("neocraft-hud.ui.studio_button"),
                                b -> mc.gui.setScreen(new NeoCraftHudConfigScreen()))
                        .bounds(this.width / 2 - 100, this.height - 24, 200, 20)
                        .build());
    }
}
