#!/usr/bin/env python3
"""Submit a version bump to Godot's old Asset Library (godotengine.org/asset-library).

Credentials are prompted for and never written to disk. The library stores a commit hash
rather than a file, so publishing is just pointing asset 1303 at a new tag.

The new Asset Store (store.godotengine.org) has no write API yet — this prints the manual
steps for it at the end.
"""

import argparse
import getpass
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

API = "https://godotengine.org/asset-library/api"
FRONTEND = "https://godotengine.org/asset-library"
ASSET_ID = 1303
REPO = "glass-brick/Scene-Manager"
STORE_URL = "https://store.godotengine.org/asset/glass-brick/scene-manager/"

# The library takes a single minimum version; .uid files put the real floor at 4.4.
DEFAULT_GODOT_VERSION = "4.4"

# Cloudflare 403s the default Python-urllib agent.
USER_AGENT = f"scene-manager-publish (+https://github.com/{REPO})"

ROOT = Path(__file__).resolve().parent.parent
PLUGIN_CFG = ROOT / "addons" / "scene_manager" / "plugin.cfg"


def api(method, path, payload=None):
	body = json.dumps(payload).encode() if payload is not None else None
	request = urllib.request.Request(
		f"{API}/{path}",
		data=body,
		method=method,
		headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
	)
	try:
		with urllib.request.urlopen(request, timeout=30) as response:
			return json.load(response)
	except urllib.error.HTTPError as error:
		detail = error.read().decode(errors="replace")
		try:
			detail = json.loads(detail).get("error", detail)
		except json.JSONDecodeError:
			pass
		raise SystemExit(f"error: {method} {path} failed ({error.code}): {detail}")
	except urllib.error.URLError as error:
		raise SystemExit(f"error: could not reach the asset library: {error.reason}")


def plugin_version(ref=None):
	if ref is None:
		text = PLUGIN_CFG.read_text()
	else:
		result = subprocess.run(
			["git", "-C", str(ROOT), "show", f"{ref}:{PLUGIN_CFG.relative_to(ROOT)}"],
			capture_output=True,
			text=True,
		)
		if result.returncode != 0:
			raise SystemExit(f"error: no plugin.cfg in {ref}")
		text = result.stdout
	for line in text.splitlines():
		if line.startswith("version="):
			return line.split("=", 1)[1].strip().strip('"')
	raise SystemExit(f"error: no version= in {PLUGIN_CFG}")


def resolve_commit(ref):
	result = subprocess.run(
		["git", "-C", str(ROOT), "rev-parse", f"{ref}^{{commit}}"],
		capture_output=True,
		text=True,
	)
	if result.returncode != 0:
		raise SystemExit(f"error: '{ref}' is not a git ref here — tag the release first")
	return result.stdout.strip()


def is_pushed(commit):
	# The library hands out this exact URL, so check the artifact itself rather than the API.
	request = urllib.request.Request(
		f"https://github.com/{REPO}/archive/{commit}.zip",
		method="HEAD",
		headers={"User-Agent": USER_AGENT},
	)
	try:
		with urllib.request.urlopen(request, timeout=30):
			return True
	except urllib.error.HTTPError:
		return False


def main():
	parser = argparse.ArgumentParser(
		description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
	)
	parser.add_argument("--ref", help="git ref to publish (default: v<plugin.cfg version>)")
	parser.add_argument(
		"--godot-version",
		default=DEFAULT_GODOT_VERSION,
		help=f"minimum Godot version (default: {DEFAULT_GODOT_VERSION})",
	)
	parser.add_argument(
		"--dry-run", action="store_true", help="show the edit without submitting it"
	)
	args = parser.parse_args()

	ref = args.ref or f"v{plugin_version()}"
	commit = resolve_commit(ref)
	# The advertised version is whatever that commit declares, not what is checked out now.
	version = plugin_version(commit)
	if not is_pushed(commit):
		raise SystemExit(f"error: {commit[:10]} is not on GitHub yet — push {ref} first")

	current = api("GET", f"asset/{ASSET_ID}")
	changes = {
		"version_string": version,
		"godot_version": args.godot_version,
		"download_commit": commit,
	}

	print(f"asset {ASSET_ID} — {current['title']}, publishing {ref}\n")
	for key, value in changes.items():
		before = current.get(key) or "-"
		print(f"  {'*' if before != value else ' '} {key:16} {before}  ->  {value}")
	print(f"    {'download_url':16} https://github.com/{REPO}/archive/{commit}.zip")

	if all(current.get(key) == value for key, value in changes.items()):
		raise SystemExit("\nnothing to change — the library is already on this version")
	if args.dry_run:
		return

	if input("\nsubmit this edit? [y/N] ").strip().lower() not in ("y", "yes"):
		raise SystemExit("aborted")

	username = input("asset library username: ").strip()
	password = getpass.getpass("asset library password: ")
	token = api("POST", "login", {"username": username, "password": password})["token"]
	try:
		edit = api("POST", f"asset/{ASSET_ID}", dict(changes, token=token))
	finally:
		try:
			api("POST", "logout", {"token": token})
		except SystemExit:
			print("warning: could not invalidate the session token", file=sys.stderr)

	print(f"\nsubmitted edit {edit['id']}: {FRONTEND}/{edit['url']}")
	print("it is queued for moderator review and goes live once approved.")
	print("\nthe new asset store has no write API — upload that one by hand:")
	print(f"  1. open {STORE_URL}")
	print("  2. Versions -> add a version, attach the archive from the URL above")
	print(f"  3. name it {version}, set the minimum Godot version to {args.godot_version}")


if __name__ == "__main__":
	main()
