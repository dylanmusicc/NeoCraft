# Notices

NeoCraft Bedrock bundles third-party components. Their licenses ship inside
the app under `Contents/Resources/Engine/Licenses/` and alongside each
component where required.

- **macrock-engine** — Wine-based x86_64 runtime with D3DMetal support,
  built from pinned upstream commits with local patches (see
  `engine/packaging`, `engine/docs/patches.md`). License: GPLv2 (Wine) and
  respective component licenses.
- **xgameruntime** — Xbox gaming runtime layer used by the engine.
- **xodus / xodus-service** — account and service helper; licenses in
  `Vendor/engine/Licenses/xodus-service/`.
- **D3DMetal (GPTK)** — Apple's Game Porting Toolkit D3DMetal libraries in
  `third_party/gptk-4.0b3`, used to translate D3D12 to Metal.
- **llvm-mingw** — MinGW-w64 toolchain used to build Windows-side
  components.

Minecraft is a trademark of Mojang Synergies AB. NeoCraft Bedrock is not
affiliated with Mojang, Microsoft, or Xbox.
