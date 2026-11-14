package com.neocraft.ui;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * Client for the NeoCraft bridge — the file-based IPC the launcher keeps
 * inside {@code config/neocraft_bridge/} while the game runs.
 *
 * <p>The mod polls {@code state.json} (worlds + hosted servers, rewritten
 * by NeoCraft every ~2 s) and sends actions by dropping
 * {@code commands/<id>.json} files; NeoCraft answers with
 * {@code responses/<id>.json}. Everything degrades gracefully: when the
 * bridge folder or a fresh state file is missing the panel shows an
 * "offline" state instead of failing.</p>
 */
public final class NeoCraftBridge {

    private static final Path DIR = Path.of("config", "neocraft_bridge");
    private static final Path STATE = DIR.resolve("state.json");
    private static final Path HANDSHAKE = DIR.resolve("bridge.json");
    private static final Path COMMANDS = DIR.resolve("commands");
    private static final Path RESPONSES = DIR.resolve("responses");

    /** state.json older than this counts as stale → bridge offline. */
    private static final long STALE_MS = 15_000;
    private static final long RESPONSE_TIMEOUT_MS = 20_000;

    private static final ExecutorService IO = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "neocraft-bridge-io");
        t.setDaemon(true);
        return t;
    });

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

    private static volatile JsonObject state;
    private static volatile boolean available;
    private static volatile String instanceName = "";
    private static volatile String lastError = "";
    /** Incremented every time a new state.json is adopted — lets the
     *  panel rebuild its widgets once per refresh instead of per frame. */
    private static volatile long version;

    private NeoCraftBridge() { }

    // ------------------------------------------------------------------
    // Polling
    // ------------------------------------------------------------------

    /** Called once per second from the client tick. Cheap: one stat +
     *  occasional small file read. */
    public static void poll() {
        try {
            if (!Files.isRegularFile(HANDSHAKE)) {
                available = false;
                state = null;
                return;
            }
            if (!Files.isRegularFile(STATE)) {
                available = false;
                return;
            }
            long age = System.currentTimeMillis()
                    - Files.getLastModifiedTime(STATE).toMillis();
            if (age > STALE_MS) {
                available = false;
                return;
            }
            String json = Files.readString(STATE, StandardCharsets.UTF_8);
            JsonObject parsed = JsonParser.parseString(json).getAsJsonObject();
            state = parsed;
            version++;
            JsonElement inst = parsed.get("instance");
            instanceName = inst != null && inst.isJsonObject()
                    ? inst.getAsJsonObject().has("name")
                        ? inst.getAsJsonObject().get("name").getAsString() : ""
                    : "";
            available = true;
            lastError = "";
        } catch (Exception e) {
            // Keep the last good state — a half-written state.json during
            // the launcher's atomic replace must not flicker the UI.
            available = false;
        }
    }

    public static boolean isAvailable() { return available; }
    public static JsonObject state() { return state; }
    public static long version() { return version; }
    public static String instanceName() { return instanceName; }
    public static String lastError() { return lastError; }

    // ------------------------------------------------------------------
    // Data accessors
    // ------------------------------------------------------------------

    public static List<JsonObject> servers() {
        List<JsonObject> out = new ArrayList<>();
        JsonObject s = state;
        if (s == null) return out;
        JsonElement arr = s.get("servers");
        if (arr != null && arr.isJsonArray()) {
            for (JsonElement e : arr.getAsJsonArray()) {
                if (e.isJsonObject()) out.add(e.getAsJsonObject());
            }
        }
        return out;
    }

    public static List<JsonObject> worlds() {
        List<JsonObject> out = new ArrayList<>();
        JsonObject s = state;
        if (s == null) return out;
        JsonElement arr = s.get("worlds");
        if (arr != null && arr.isJsonArray()) {
            for (JsonElement e : arr.getAsJsonArray()) {
                if (e.isJsonObject()) out.add(e.getAsJsonObject());
            }
        }
        return out;
    }

    /** Folder name of the world inside saves/ — the id `host` expects. */
    public static String worldKey(JsonObject world) {
        // The launcher writes `name` = folder name; `levelName` is the
        // display name from level.dat and may differ.
        return world.has("name") ? world.get("name").getAsString() : "";
    }

    public static boolean worldAlreadyHosted(String worldKey) {
        for (JsonObject server : servers()) {
            String src = server.has("sourceWorldName")
                    ? server.get("sourceWorldName").getAsString() : "";
            if (worldKey.equals(src)) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Commands
    // ------------------------------------------------------------------

    /**
     * Sends a bridge action and completes with NeoCraft's response.
     * Failures (offline bridge, timeout, error response) complete
     * exceptionally or with {@code ok:false} — callers surface
     * {@link #lastError()} / the response's {@code error} field.
     */
    public static CompletableFuture<JsonObject> send(String action, JsonObject params) {
        CompletableFuture<JsonObject> future = new CompletableFuture<>();
        IO.execute(() -> {
            String id = UUID.randomUUID().toString();
            try {
                Files.createDirectories(COMMANDS);
                Files.createDirectories(RESPONSES);
                JsonObject request = params == null ? new JsonObject() : params.deepCopy();
                request.addProperty("id", id);
                request.addProperty("action", action);
                Path tmp = COMMANDS.resolve(id + ".json.tmp");
                Path target = COMMANDS.resolve(id + ".json");
                try (Writer w = Files.newBufferedWriter(tmp, StandardCharsets.UTF_8)) {
                    GSON.toJson(request, w);
                }
                Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING);

                Path response = RESPONSES.resolve(id + ".json");
                long deadline = System.currentTimeMillis() + RESPONSE_TIMEOUT_MS;
                while (System.currentTimeMillis() < deadline) {
                    if (Files.isRegularFile(response)) {
                        try {
                            JsonObject parsed = JsonParser.parseString(
                                    Files.readString(response, StandardCharsets.UTF_8)).getAsJsonObject();
                            Files.deleteIfExists(response);
                            if (parsed.has("ok") && parsed.get("ok").getAsBoolean()) {
                                future.complete(parsed);
                            } else {
                                lastError = parsed.has("error")
                                        ? parsed.get("error").getAsString() : "request failed";
                                future.complete(parsed);
                            }
                            return;
                        } catch (Exception ignored) {
                            // half-written response — retry until deadline
                        }
                    }
                    try { Thread.sleep(120); } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
                lastError = "NeoCraft did not answer in time";
                future.completeExceptionally(new IOException(lastError));
            } catch (Exception e) {
                lastError = e.getMessage() == null ? e.toString() : e.getMessage();
                future.completeExceptionally(e);
            }
        });
        return future;
    }

    /** Fire-and-forget variant for start/stop/restart/command. */
    public static void sendQuiet(String action, JsonObject params) {
        send(action, params).exceptionally(e -> null);
    }

    public static JsonObject serverParams(JsonObject server) {
        JsonObject p = new JsonObject();
        if (server.has("id")) p.addProperty("serverId", server.get("id").getAsString());
        return p;
    }
}
