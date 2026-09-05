#!/usr/bin/env python3
"""Generate a Homebrew cask from the final, already notarized release ZIP.

Called by release.sh after stapling and verification. This command does not
notarize, publish, or verify Apple's ticket; it validates packaging metadata
and computes the actual archive's SHA-256.
"""

import argparse
import hashlib
import pathlib
import plistlib
import re
import zipfile


def render(version: str, repository: str, archive: pathlib.Path) -> str:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Version must be x.y.z.")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Repository must be a GitHub owner/repository.")
    if archive.name != f"DotShelf-{version}.zip":
        raise ValueError("Archive name must be DotShelf-VERSION.zip.")
    with zipfile.ZipFile(archive) as package:
        metadata = plistlib.loads(package.read("DotShelf.app/Contents/Info.plist"))
        if metadata.get("CFBundleShortVersionString") != version:
            raise ValueError("The app version does not match the requested cask version.")
        if metadata.get("CFBundleIdentifier") != "ai.robin.konfigeditor":
            raise ValueError("The archive does not contain the DotShelf application.")
        if "DotShelf.app/Contents/MacOS/KonfigEditor" not in package.namelist():
            raise ValueError("The archive is missing the application executable.")
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return f'''cask "dotshelf" do
  version "{version}"
  sha256 "{digest.hexdigest()}"

  url "https://github.com/{repository}/releases/download/v#{{version}}/DotShelf-#{{version}}.zip"
  name "DotShelf"
  desc "Native editor for configuration files"
  homepage "https://github.com/{repository}"

  depends_on macos: ">= :sonoma"

  app "DotShelf.app"
end
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--archive", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    try:
        content = render(args.version, args.repository, args.archive)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Avoid accidentally replacing a cask supplied by the caller.
        with args.output.open("x", encoding="utf-8") as output:
            output.write(content)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Cannot generate cask: {error}\n")
    print(f"Generated cask from release archive: {args.output}")


if __name__ == "__main__":
    main()
