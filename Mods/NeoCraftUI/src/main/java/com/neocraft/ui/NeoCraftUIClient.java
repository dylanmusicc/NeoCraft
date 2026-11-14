package com.neocraft.ui;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.KeyMapping;
import net.minecraft.resources.Identifier;

/**
 * NeoCraft UI — client entrypoint. Loads {@code config/neocraft_ui.json},
 * keeps it hot-reloaded while Neo Studio edits it, polls the NeoCraft
 * bridge for the in-game menu, and registers the <b>N</b> keybind that
 * opens {@link NeoCraftMenuScreen}.
 */
public final class NeoCraftUIClient implements ClientModInitializer {

    private static KeyMapping menuKey;
    private static int tickCounter;

    @Override
    public void onInitializeClient() {
        UiConfig.ensureExists();
        UiConfig.load();
        UiConfig.startWatcher();

        KeyMapping.Category category = KeyMapping.Category.register(
                Identifier.fromNamespaceAndPath("neocraft-ui", "main"));

        menuKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.neocraft-ui.menu",
                InputConstants.KEY_N,
                category
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            if (++tickCounter % 20 == 0) {
                NeoCraftBridge.poll();
            }
            while (menuKey.consumeClick()) {
                // Only steal N when no screen is open — chat, inventories
                // and the pause menu keep the key to themselves.
                if (client.gui.screen() == null) {
                    client.gui.setScreen(new NeoCraftMenuScreen());
                }
            }
        });
    }
}
