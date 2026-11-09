import sys
import webbrowser
from pathlib import Path

def open_report(path: Path):
    try:
        opened = webbrowser.open(path.resolve().as_uri())
    except (OSError, webbrowser.Error):
        opened = False
    if not opened:
        print(f'Aviso: abra o relatório manualmente: {path}',file=sys.stderr)
