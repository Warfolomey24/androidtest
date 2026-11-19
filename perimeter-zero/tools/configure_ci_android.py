"""Configure Godot's editor-local Android SDK paths for a headless CI runner.

Godot 4.7 requires editor settings in addition to Android environment variables.
The script deliberately fails if Godot hasn't generated an editor settings file yet.
No user/project secrets are stored inside project files or exported artifacts.
"""
from __future__ import annotations
import os
from pathlib import Path
import re
import sys


def configure(home: Path, sdk: Path, java: Path) -> Path:
    if not sdk.is_dir() or not java.is_dir():
        raise RuntimeError(f"Invalid Android/JDK paths: {sdk}, {java}")
    config = home / ".config" / "godot"
    candidates = sorted(config.glob("editor_settings-4*.tres"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise RuntimeError("No Godot 4 editor settings found. Run 'godot --headless --path . --import' first.")
    path = candidates[0]
    original = path.read_text("utf-8")
    if "[resource]" not in original:
        raise RuntimeError(f"Unexpected Godot editor settings format: {path}")
    settings = {
        "export/android/android_sdk_path": str(sdk),
        "export/android/java_sdk_path": str(java),
    }
    content = original
    for key, val in settings.items():
        escaped = val.replace("\\", "\\\\").replace('"', '\\"')
        line = f'{key} = "{escaped}"'
        pattern = rf"(?m)^{re.escape(key)}\s*=.*$"
        if re.search(pattern, content):
            content = re.sub(pattern, lambda _m: line, content)
        else:
            content += "\n" + line
    path.write_text(content, "utf-8")
    for key in settings:
        if content.count(key + " = ") != 1:
            raise RuntimeError(f"Android setting occurred multiple times: {key}")
    return path


if __name__ == "__main__":
    try:
        sdk_env = os.getenv("ANDROID_SDK_ROOT") or os.getenv("ANDROID_HOME")
        java_env = os.getenv("JAVA_HOME")
        if not sdk_env or not java_env:
            raise RuntimeError("ANDROID_SDK_ROOT/ANDROID_HOME and JAVA_HOME must be set")
        result = configure(Path.home(), Path(sdk_env), Path(java_env))
        print(f"Configured Godot Android SDK and Java 17 in {result}")
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
