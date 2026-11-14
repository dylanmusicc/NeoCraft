package com.neocraft.hud;

import com.mojang.blaze3d.platform.InputConstants;
import com.neocraft.hud.HudConfig.CrosshairUi;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElement;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.fabricmc.fabric.api.client.rendering.v1.hud.VanillaHudElements;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.DeltaTracker;
import net.minecraft.resources.Identifier;

/**
 * NeoCraft HUD — client entrypoint.
 *
 * <ul>
 *   <li>Loads {@code config/neocraft_hud.json} and hot-reloads it on change.</li>
 *   <li><b>Right Shift</b> opens the NeoCraft Studio editor screen.</li>
 *   <li><b>F8</b> toggles the whole HUD overlay on/off.</li>
 *   <li>Registers HUD elements: glass backdrops are attached immediately
 *   before the vanilla CHAT / HOTBAR / SCOREBOARD layers so they render
 *   <em>under</em> the vanilla text, the main pass draws widgets and hotbar
 *   accents before {@code MISC_OVERLAYS}, and the vanilla crosshair element
 *   is replaced with the NeoCraft one.</li>
 * </ul>
 */
public final class NeoCraftHUDClient implements ClientModInitializer {

    /** Master switch for every NeoCraft HUD element (widgets + skins). */
    public static boolean hudEnabled = true;

    private static final Identifier ID_WIDGETS = id("widgets");
    private static final Identifier ID_CHAT_BG = id("chat-backdrop");
    private static final Identifier ID_HOTBAR_BG = id("hotbar-backdrop");
    private static final Identifier ID_SCORE_BG = id("scoreboard-backdrop");

    private static KeyMapping editorKey;
    private static KeyMapping toggleKey;

    private static Identifier id(String path) {
        return Identifier.fromNamespaceAndPath("neocraft-hud", path);
    }

    @Override
    public void onInitializeClient() {
        HudConfig.ensureExists();
        HudConfig.load();
        HudConfig.startWatcher();
        UiSync.startWatcher();

        KeyMapping.Category category = KeyMapping.Category.register(
                Identifier.fromNamespaceAndPath("neocraft-hud", "main"));

        editorKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.neocraft-hud.editor",
                InputConstants.KEY_RSHIFT,
                category
        ));
        toggleKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.neocraft-hud.toggle",
                InputConstants.KEY_F8,
                category
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            HudRenderer.tick(client);
            while (toggleKey.consumeClick()) {
                hudEnabled = !hudEnabled;
            }
            // Only steal Right Shift when no screen is open, so the editor
            // (and other GUIs) keep the key to themselves. In 26.3 the
            // current screen lives on Gui, not Minecraft.
            if (client.gui.screen() == null && editorKey.consumeClick()) {
                client.gui.setScreen(new NeoCraftHudConfigScreen());
            }
        });

        // Backdrops under the vanilla layers they skin.
        HudElementRegistry.attachElementBefore(
                VanillaHudElements.CHAT, ID_CHAT_BG,
                (HudElement) HudRenderer::renderChatBackdrop);
        HudElementRegistry.attachElementBefore(
                VanillaHudElements.HOTBAR, ID_HOTBAR_BG,
                (HudElement) HudRenderer::renderHotbarBackdrop);
        HudElementRegistry.attachElementBefore(
                VanillaHudElements.SCOREBOARD, ID_SCORE_BG,
                (HudElement) HudRenderer::renderScoreboardBackdrop);

        // Main pass: widgets + hotbar foreground accents.
        HudElementRegistry.attachElementBefore(
                VanillaHudElements.MISC_OVERLAYS, ID_WIDGETS,
                (HudElement) (graphics, deltaTracker) -> {
                    if (hudEnabled) HudRenderer.render(graphics, deltaTracker);
                });

        // Replace the vanilla crosshair with the NeoCraft one. When the
        // custom crosshair is disabled we delegate back to the original
        // element so vanilla behavior is preserved exactly.
        HudElementRegistry.replaceElement(VanillaHudElements.CROSSHAIR, original ->
                (HudElement) (GuiGraphicsExtractor graphics, DeltaTracker delta) -> {
                    if (!hudEnabled) {
                        original.extractRenderState(graphics, delta);
                        return;
                    }
                    CrosshairUi c = HudConfig.ui().crosshair;
                    if (c != null && c.enabled) {
                        HudRenderer.renderCrosshairElement(graphics, delta);
                    } else {
                        original.extractRenderState(graphics, delta);
                    }
                });
    }
}
