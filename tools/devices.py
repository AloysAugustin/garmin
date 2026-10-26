#!/usr/bin/env python3
"""Find the Connect IQ watches that have every API this app needs, and wire
them into the build.

Reads the downloaded device files (~/.Garmin/ConnectIQ/Devices/<id>/:
compiler.json and <id>.api.debug.xml, which lists that device's exact API
surface). Download them all first (~380 MB, no fonts) with
`connect-iq-sdk-manager device download --download-all`.

Usage: tools/devices.py [list|ids|json|update]
  list    (default) supported/unsupported table, with what is missing
  ids     supported device ids
  json    per-device details (resolution, icon size, shape, bits/pixel)
  update  rewrite the <iq:products> in manifest.xml, the generated block in
          monkey.jungle (icon folder + colour/mono annotation per device) and
          the launcher icons in resources-icons/, and the supported-watch
          table in README.md
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEV_DIR = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")

# Classes (dataEntry labels) and functions (parent, name) the app calls.
REQUIRED_CLASSES = [
    "Toybox_BluetoothLowEnergy_BleDelegate",
    "Toybox_Cryptography_KeyPair",
    "Toybox_Cryptography_KeyAgreement",
    "Toybox_Cryptography_Hash",
    "Toybox_Cryptography_HashBasedMessageAuthenticationCode",
    "Toybox_Cryptography_Cipher",  # AES-ECB under TeslaGcm
    "Toybox_WatchUi_Menu2",
]
REQUIRED_FUNCTIONS = [
    ("BluetoothLowEnergy", "registerProfile"),
    ("BluetoothLowEnergy", "setScanState"),
    ("BluetoothLowEnergy", "pairDevice"),
    ("BluetoothLowEnergy", "unpairDevice"),
    ("Cryptography", "createPublicKey"),
    ("Cryptography", "randomBytes"),
]
MIN_API = (3, 1, 0)  # manifest minApiLevel


def version(s):
    return tuple(int(x) for x in s.split("."))


def check(dev):
    d = os.path.join(DEV_DIR, dev)
    with open(os.path.join(d, "compiler.json")) as f:
        c = json.load(f)
    info = {
        "id": dev,
        "name": c.get("displayName", dev),
        "family": c.get("deviceFamily", ""),
        "shape": c.get("deviceFamily", "").split("-")[0],
        "resolution": "%dx%d" % (c["resolution"]["width"], c["resolution"]["height"]),
        "icon": "%dx%d" % (c["launcherIcon"]["width"], c["launcherIcon"]["height"]),
        "bpp": c.get("bitsPerPixel"),
        # Newest firmware's API level: users on old firmware can update.
        "api": max((p["connectIQVersion"] for p in c["partNumbers"]), key=version),
        "group": c.get("webDocDeviceGroup", ""),
        "watchApp": any(t["type"] == "watchApp" for t in c.get("appTypes", [])),
    }
    missing = []
    if info["group"] != "Watches/Wearables":
        missing.append("not a watch (%s)" % info["group"])
    if not info["watchApp"]:
        missing.append("watch-app type")
    if version(info["api"]) < MIN_API:
        missing.append("API %s < %s" % (info["api"], ".".join(map(str, MIN_API))))
    api = os.path.join(d, dev + ".api.debug.xml")
    if not os.path.exists(api):
        missing.append("no api.debug.xml")
    else:
        with open(api, encoding="utf-8") as f:
            text = f.read()
        labels = set(re.findall(r'<dataEntry label="([^"]+)"', text))
        funcs = set(re.findall(r'<functionEntry [^>]*name="([^"]+)" parent="([^"]+)"', text))
        for cls in REQUIRED_CLASSES:
            if cls not in labels:
                missing.append(cls.replace("Toybox_", "").replace("_", "."))
        for parent, name in REQUIRED_FUNCTIONS:
            if (name, parent) not in funcs:
                missing.append(parent + "." + name)
    info["missing"] = missing
    return info


def icon_dir(r):
    return "resources-icons/%s%s" % (r["icon"], "-mono" if r["bpp"] == 1 else "")


def draw_icon(size, mono):
    """A generic key in a disc (deliberately not a Tesla logo)."""
    from PIL import Image, ImageDraw
    ss = 8 if not mono else 1          # supersample colour icons
    n = size * ss
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    disc = (255, 255, 255, 255) if mono else (200, 30, 40, 255)
    key = (0, 0, 0, 255) if mono else (255, 255, 255, 255)
    d.ellipse([0, 0, n - 1, n - 1], fill=disc)
    u = n / 32.0                       # design grid: 32 x 32
    # bow (ring), shaft and two teeth, key pointing right
    d.ellipse([5 * u, 10 * u, 17 * u, 22 * u], fill=key)
    d.ellipse([8.5 * u, 13.5 * u, 13.5 * u, 18.5 * u], fill=disc)
    d.rectangle([16 * u, 14.5 * u, 27 * u, 17.5 * u], fill=key)
    d.rectangle([21 * u, 17.5 * u, 23 * u, 21 * u], fill=key)
    d.rectangle([24.5 * u, 17.5 * u, 26.5 * u, 20 * u], fill=key)
    if ss > 1:
        img = img.resize((size, size), Image.LANCZOS)
    return img


def update(rows):
    ok = [r for r in rows if not r["missing"]]
    # manifest.xml products
    path = os.path.join(ROOT, "manifest.xml")
    with open(path) as f:
        m = f.read()
    products = "".join('            <iq:product id="%s"/>\n' % r["id"] for r in ok)
    m = re.sub(r"(<iq:products>\n).*?(        </iq:products>)",
               lambda g: g.group(1) + products + g.group(2), m, flags=re.S)
    with open(path, "w") as f:
        f.write(m)
    # monkey.jungle generated block
    path = os.path.join(ROOT, "monkey.jungle")
    with open(path) as f:
        j = f.read()
    begin, end = "# BEGIN devices (generated by tools/devices.py update)\n", "# END devices\n"
    lines = []
    for r in ok:
        lines.append("%s.resourcePath = resources;%s" % (r["id"], icon_dir(r)))
        if r["bpp"] == 1:
            lines.append("%s.excludeAnnotations = color" % r["id"])
    block = begin + "\n".join(lines) + "\n" + end
    if begin in j:
        j = j[:j.index(begin)] + block + j[j.index(end) + len(end):]
    else:
        j = j.rstrip("\n") + "\n\n" + block
    with open(path, "w") as f:
        f.write(j)
    # launcher icons, one folder per (size, mono)
    for r in ok:
        d = os.path.join(ROOT, icon_dir(r), "drawables")
        if os.path.exists(os.path.join(d, "launcher_icon.png")):
            continue
        os.makedirs(d, exist_ok=True)
        w, h = (int(x) for x in r["icon"].split("x"))
        from PIL import Image
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        side = min(w, h)
        img.paste(draw_icon(side, r["bpp"] == 1), ((w - side) // 2, (h - side) // 2))
        img.save(os.path.join(d, "launcher_icon.png"))
        with open(os.path.join(d, "drawables.xml"), "w") as f:
            f.write('<drawables>\n    <bitmap id="LauncherIcon" filename="launcher_icon.png" />\n</drawables>\n')
    # README.md supported-watch table
    path = os.path.join(ROOT, "README.md")
    with open(path) as f:
        rd = f.read()
    begin, end = "<!-- BEGIN devices -->\n", "<!-- END devices -->\n"
    table = "| Watch | File |\n| ----- | ---- |\n" + "".join(
        "| %s | `TeslaKey-%s.prg` |\n" % (r["name"].replace("|", "/"), r["id"])
        for r in sorted(ok, key=lambda r: r["name"].lower()))
    if begin in rd:
        rd = rd[:rd.index(begin)] + begin + table + rd[rd.index(end):]
        with open(path, "w") as f:
            f.write(rd)
    print("%d devices written to manifest.xml, monkey.jungle and README.md" % len(ok))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    devs = sorted(x for x in os.listdir(DEV_DIR)
                  if os.path.exists(os.path.join(DEV_DIR, x, "compiler.json")))
    rows = [check(x) for x in devs]
    ok = [r for r in rows if not r["missing"]]
    if cmd == "ids":
        print("\n".join(r["id"] for r in ok))
    elif cmd == "json":
        json.dump(rows, sys.stdout, indent=1)
    elif cmd == "update":
        update(rows)
    else:
        for r in rows:
            status = "OK " if not r["missing"] else "NO "
            print("%s %-24s %-10s %-12s %-7s bpp=%-2s %s" % (
                status, r["id"], r["resolution"], r["shape"], r["api"], r["bpp"],
                "; ".join(r["missing"][:3])))
        print("%d of %d devices supported" % (len(ok), len(rows)), file=sys.stderr)


if __name__ == "__main__":
    main()
