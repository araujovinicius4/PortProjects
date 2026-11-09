from datetime import datetime
from pathlib import Path
from config.settings import COLUMNS
from services.health import health
from reports import csv_report, json_report, html_report, history, console

def generate(root: Path, all_rows: list[dict], only_problems: bool, inactive_days: int):
    rows = [r for r in all_rows if r['Situacao'] != 'SINCRONIZADO'] if only_problems else all_rows
    score = health(all_rows)
    run_at = datetime.now().astimezone().isoformat(timespec='seconds')
    exported = [{k:r[k] for k in COLUMNS} for r in rows]
    csv_report.write(root,COLUMNS,exported)
    json_report.write(root,run_at,all_rows,rows,score,only_problems,inactive_days,exported)
    history.append(root,run_at,all_rows,score)
    html_report.write(root,run_at,all_rows,rows,score,inactive_days,exported)
    console.show(root,all_rows,rows,score,only_problems)
