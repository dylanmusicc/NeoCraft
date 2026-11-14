/// options.txt values a profile's performance mode writes over the game's own settings at
/// every start, for the MacBook Neo's A18 Pro and its 8 GB of memory.
public enum GameTuning {
    /// Fancy instead of Vibrant Visuals, no MSAA — which also breaks Metal 4's interface —
    /// 16 chunks of render distance (`gfx_viewdistance` counts blocks: chunks × 16), the
    /// frame cap and the cheapest fog, reflections, shadows and bloom.
    public static let performance: [String: String] = [
        "graphics_mode": "1",
        "graphics_quality_preset_mode": "1",
        "gfx_msaa": "1",
        "gfx_viewdistance": "256",
        "gfx_max_framerate": "60",
        "volumetric_fog_quality": "0",
        "reflections_quality": "0",
        "shadow_quality": "0",
        "bloom_strength": "0",
        "bloom_custom_strength": "0",
        "gfx_bubble_particles": "0",
    ]
}
