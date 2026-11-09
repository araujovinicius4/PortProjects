from datetime import datetime
from pathlib import Path
from models.repository import Commit
from utils.commands import git

def latest(repo: Path):
    result = git(repo, 'log','-1','--format=%an%x00%ct%x00%s')
    if result.code:
        return None
    parts = result.out.rstrip('\n').split('\0', 2)
    if len(parts) != 3:
        return None
    author, timestamp, message = parts
    ts = int(timestamp)
    return author, datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S'), ts, message

def pending(repo: Path, upstream: str) -> list[Commit]:
    result = git(repo, 'log','--reverse','--format=%H%x00%an%x00%aI%x00%s',f'HEAD..{upstream}')
    if result.code:
        return []
    commits = []
    for line in result.out.splitlines():
        parts = line.split('\0',3)
        if len(parts) == 4:
            commits.append(Commit(*parts))
    return commits
