#!/usr/bin/env python3
"""Generate manifest.json from revenant-scripts directory.

Scans scripts/ for single-file (.lua) and package (dir/init.lua) scripts,
parses their metadata headers or manifest.lua, computes SHA256, and outputs
manifest.json.

Usage:
    python generate-manifest.py --channel stable --registry-name revenant-official \
        --base-url https://raw.githubusercontent.com/Sordal-GSIV/revenant-scripts \
        --scripts-dir . --output manifest.json [--merge existing-manifest.json]
"""

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime, timezone


def parse_single_file_header(filepath: Path) -> dict | None:
    """Parse --- @revenant-script header from a .lua file."""
    metadata = {}
    in_header = False
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.rstrip()
            if stripped == "--- @revenant-script":
                in_header = True
                continue
            if in_header and stripped.startswith("--- "):
                kv = stripped[4:]
                match = re.match(r"(\w+):\s*(.*)", kv)
                if match:
                    metadata[match.group(1)] = match.group(2).strip()
            elif in_header:
                break
    if not metadata.get("name"):
        return None
    return metadata


def parse_manifest_lua(filepath: Path) -> dict | None:
    """Parse a manifest.lua file (simple key = value extraction)."""
    metadata = {}
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    # Extract simple string fields
    for match in re.finditer(r'(\w+)\s*=\s*"([^"]*)"', content):
        metadata[match.group(1)] = match.group(2)
    # Extract depends array
    depends_match = re.search(r'depends\s*=\s*\{([^}]*)\}', content)
    if depends_match:
        deps = re.findall(r'"([^"]*)"', depends_match.group(1))
        metadata["depends"] = deps
    # Extract tags array
    tags_match = re.search(r'tags\s*=\s*\{([^}]*)\}', content)
    if tags_match:
        tags = re.findall(r'"([^"]*)"', tags_match.group(1))
        metadata["tags"] = tags
    if not metadata.get("name"):
        return None
    return metadata


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(filepath: Path) -> str:
    return sha256_bytes(filepath.read_bytes())


def scan_scripts(scripts_dir: Path, channel: str) -> list:
    """Scan for scripts and return manifest entries."""
    entries = []
    skip_dirs = {"_pkg", "pkg", ".github", "tools", ".git", "__pycache__"}

    for item in sorted(scripts_dir.iterdir()):
        if item.name.startswith(".") or item.name.startswith("_"):
            continue

        if item.is_dir():
            if item.name in skip_dirs:
                continue
            init_lua = item / "init.lua"
            manifest_lua = item / "manifest.lua"
            if not init_lua.exists():
                continue

            # Package script
            meta = None
            if manifest_lua.exists():
                meta = parse_manifest_lua(manifest_lua)
            if not meta:
                meta = {"name": item.name}

            # Enumerate files
            files = []
            all_bytes = b""
            file_paths = sorted(item.rglob("*.lua"))
            for fp in file_paths:
                rel = fp.relative_to(item)
                content = fp.read_bytes()
                files.append({
                    "name": str(rel),
                    "sha256": sha256_bytes(content),
                })
                all_bytes += content

            entry = {
                "name": meta["name"],
                "author": meta.get("author", "unknown"),
                "description": meta.get("description", ""),
                "tags": meta.get("tags", []),
                "channels": {
                    channel: {
                        "version": meta.get("version", "0.0.0"),
                        "sha256": sha256_bytes(all_bytes),
                        "path": item.name + "/",
                        "depends": meta.get("depends", []),
                        "files": files,
                    }
                }
            }
            entries.append(entry)

        elif item.suffix == ".lua":
            meta = parse_single_file_header(item)
            if not meta:
                continue

            entry = {
                "name": meta["name"],
                "author": meta.get("author", "unknown"),
                "description": meta.get("description", ""),
                "tags": [t.strip() for t in meta.get("tags", "").split(",") if t.strip()],
                "channels": {
                    channel: {
                        "version": meta.get("version", "0.0.0"),
                        "sha256": sha256_file(item),
                        "path": item.name,
                        "depends": [d.strip() for d in meta.get("depends", "").split(",") if d.strip()],
                    }
                }
            }
            entries.append(entry)

    return entries


def merge_manifests(existing: dict, new_entries: list, channel: str) -> list:
    """Merge new channel data into existing manifest entries."""
    by_name = {}
    for entry in existing.get("scripts", []):
        by_name[entry["name"]] = entry

    for entry in new_entries:
        name = entry["name"]
        if name in by_name:
            # Merge channel info
            by_name[name]["channels"][channel] = entry["channels"][channel]
            # Update top-level metadata from newest
            by_name[name]["author"] = entry["author"]
            by_name[name]["description"] = entry["description"]
            by_name[name]["tags"] = entry["tags"]
        else:
            by_name[name] = entry

    return sorted(by_name.values(), key=lambda e: e["name"])


def main():
    parser = argparse.ArgumentParser(description="Generate revenant-scripts manifest.json")
    parser.add_argument("--channel", required=True, choices=["stable", "beta", "dev"])
    parser.add_argument("--registry-name", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--scripts-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--merge", help="Path to existing manifest.json to merge with")
    args = parser.parse_args()

    scripts_dir = Path(args.scripts_dir)
    entries = scan_scripts(scripts_dir, args.channel)

    if args.merge and os.path.exists(args.merge):
        with open(args.merge) as f:
            existing = json.load(f)
        all_entries = merge_manifests(existing, entries, args.channel)
    else:
        all_entries = entries

    manifest = {
        "registry": args.registry_name,
        "url": args.base_url,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "manifest_version": 1,
        "scripts": all_entries,
    }

    with open(args.output, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"Generated manifest with {len(all_entries)} scripts for channel '{args.channel}'")


if __name__ == "__main__":
    main()
