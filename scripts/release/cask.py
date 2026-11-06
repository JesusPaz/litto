#!/usr/bin/env python3
"""Generate the Homebrew cask from the exact notarized release archive."""
import hashlib
from pathlib import Path
import sys
from version import parse

tag, archive, destination = sys.argv[1:]
_, preview = parse(tag)
token, conflict = ("litto@preview", "litto") if preview else ("litto", "litto@preview")
checksum = hashlib.sha256(Path(archive).read_bytes()).hexdigest()
Path(destination).write_text(f'''cask "{token}" do
  version "{tag[1:]}"
  sha256 "{checksum}"

  url "https://github.com/JesusPaz/litto/releases/download/v#{{version}}/Litto-v#{{version}}-macOS.zip"
  name "Litto"
  desc "Spaced-repetition flashcards with decks made by Claude"
  homepage "https://github.com/JesusPaz/litto"

  conflicts_with cask: "{conflict}"
  depends_on macos: :sequoia

  app "Litto.app"
end
''')
