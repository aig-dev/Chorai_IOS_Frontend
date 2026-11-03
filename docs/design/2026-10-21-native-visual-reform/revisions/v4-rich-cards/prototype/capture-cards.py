#!/usr/bin/env python3
"""Capture the isolated native sample; never launches the production app."""
import os
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parent.parent
destination = root / "screenshots" / "cards"
destination.mkdir(parents=True, exist_ok=True)
environment = {**os.environ, "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"}
device = "92DE3535-B261-49B5-844F-9BD9B8C241B4"
bundle = "com.chorai.nativeprototype.v4"

def simctl(*arguments):
    subprocess.run(["xcrun", "simctl", *arguments], env=environment, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

palettes = ["green-gold", "original", "purple", "blue", "clay"]
cards = ["photo", "essay", "quote", "checklist", "code", "reference", "comparison", "short"]
simctl("status_bar", device, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
try:
    for palette in palettes:
        for mode in ["light", "dark"]:
            for card in cards:
                simctl("launch", "--terminate-running-process", device, bundle,
                       "--screen", "explore", "--appearance", mode,
                       "--palette", palette, "--card", card)
                time.sleep(2.6)
                path = destination / f"{palette}-{card}-{mode}.png"
                simctl("io", device, "screenshot", str(path))
                print(path.name, flush=True)
finally:
    simctl("status_bar", device, "clear")
