# Converts en.txt (one blocked word/phrase per line) into blocked_phrases.json (a JSON array of those
# lines, blank lines skipped) for chatFilter.ts. Paths are relative to this script, so it runs from anywhere.
import json
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent

with open(DATA_DIR / "en.txt", "r", encoding="utf-8") as file:
    lines = [line.strip() for line in file if line.strip()]

with open(DATA_DIR / "blocked_phrases.json", "w", encoding="utf-8") as file:
    json.dump(lines, file, indent=4)
