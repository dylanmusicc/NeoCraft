"""game-host.py LOADER CONTENTS VERSION: make the app the game runs from.

macOS finds a process's app by its main executable, and gives Game Mode only to an app whose
Info.plist says it is a game and whose CFBundleExecutable is that program. So the game starts from
a copy of Wine's loader that is the main executable of an app of its own. The loader's embedded
Info.plist (the __TEXT,__info_plist section) must name the same app, or macOS takes the process for
Wine: this rewrites that section in the copy and writes the app's Info.plist beside it.

LOADER is Wine's x86_64 loader, CONTENTS the app's Contents folder. Standard library only; run with
python3 -I.
"""
import pathlib
import plistlib
import struct
import sys

IDENTIFIER = "dev.siliconbedrock.game"
NAME = "Minecraft Bedrock Edition"
GAME = {
    "CFBundleIdentifier": IDENTIFIER,
    "CFBundleName": NAME,
    "CFBundleIconFile": "AppIcon",
    "GCSupportsGameMode": True,
    "LSSupportsGameMode": True,
    "LSApplicationCategoryType": "public.app-category.games",
    "NSHighResolutionCapable": True,
}
MACH_O_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19


def info_plist_section(data):
    """The file offset and size of the __TEXT,__info_plist section."""
    if struct.unpack_from("<I", data, 0)[0] != MACH_O_64:
        sys.exit("the loader is not a thin 64-bit Mach-O")
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        if command == LC_SEGMENT_64:
            section = offset + 72
            for _ in range(struct.unpack_from("<I", data, offset + 64)[0]):
                name = bytes(data[section:section + 16]).split(b"\0")[0]
                segment = bytes(data[section + 16:section + 32]).split(b"\0")[0]
                if segment == b"__TEXT" and name == b"__info_plist":
                    length = struct.unpack_from("<Q", data, section + 40)[0]
                    return struct.unpack_from("<I", data, section + 48)[0], length
                section += 80
        offset += size
    sys.exit("the loader has no __info_plist section")


def main():
    loader, contents, version = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
    data = bytearray(loader.read_bytes())
    start, length = info_plist_section(data)
    embedded = plistlib.loads(bytes(data[start:start + length]).rstrip(b"\0"))
    # The section can't grow: what the running process doesn't read goes, to make room.
    for key in ("CFBundleAllowMixedLocalizations", "CFBundleSignature", "CFBundleDevelopmentRegion",
                "CFBundleShortVersionString"):
        embedded.pop(key, None)
    embedded.update(GAME)
    new = plistlib.dumps(embedded, fmt=plistlib.FMT_XML)
    if len(new) >= length:
        sys.exit("the embedded Info.plist needs {} bytes and has room for {}".format(len(new), length))
    data[start:start + length] = new + b" " * (length - len(new) - 1) + b"\n"
    executable = contents / "MacOS" / "wine"
    executable.write_bytes(bytes(data))
    executable.chmod(0o755)

    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump({
            **GAME,
            "CFBundleDisplayName": NAME,
            "CFBundleExecutable": "wine",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            # Wine brings itself to the foreground when it shows a window. Until then, nothing
            # bounces in the Dock, and its helper processes stay out of it.
            "LSUIElement": True,
            "NSPrincipalClass": embedded.get("NSPrincipalClass", "WineApplication"),
            "NSMicrophoneUsageDescription": "Voice chat in the game.",
        }, f)


if __name__ == "__main__":
    main()
