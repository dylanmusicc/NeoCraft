package com.neocraft.host;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.KeyMapping;
import net.minecraft.resources.Identifier;

/**
 * NeoCraft Host — client entrypoint.
 *
 * <ul>
 *   <li>Polls the NeoCraft bridge {@code state.json} once per second.</li>
 *   <li><b>K</b> opens the hosted-server panel while playing. The
 *   pause-menu entry point lives in {@code neocraft-ui}'s unified
 *   NeoCraft menu — this mod intentionally adds no pause buttons.</li>
 * </ul>
 */
public final class NeoCraftHostClient implements ClientModInitializer {

    private static KeyMapping panelKey;
    private static int tickCounter;

    @Override
    public void onInitializeClient() {
        KeyMapping.Category category = KeyMapping.Category.register(
                Identifier.fromNamespaceAndPath("neocraft-host", "main"));

        panelKey = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.neocraft-host.panel",
                InputConstants.KEY_K,
                category
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            if (++tickCounter % 20 == 0) {
                Bridge.poll();
            }
            while (panelKey.consumeClick()) {
                // Only steal K when no screen is open — chat, inventories
                // and the pause menu keep the key to themselves.
                if (client.gui.screen() == null) {
                    client.gui.setScreen(new NeoCraftHostScreen());
                }
            }
        });
    }
}
