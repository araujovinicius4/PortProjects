import os
from pathlib import Path
from config.settings import EXCLUDED

def discover(root: Path):
    for directory, dirs, files in os.walk(root, followlinks=False):
        if '.git' in dirs or '.git' in files:
            marker = Path(directory) / '.git'
            if marker.is_dir() or marker.is_file():
                yield Path(directory)
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED)
