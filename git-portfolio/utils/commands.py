import os
import re
import subprocess
from pathlib import Path
from dataclasses import dataclass

@dataclass
class Result:
    code: int
    out: str = ''
    error: str = ''

def redact(value: str) -> str:
    value = re.sub(r'(https?://)[^/\s@]+@', r'\1[credencial]@', value)
    for key in ('GH_TOKEN', 'GITHUB_TOKEN'):
        token = os.environ.get(key)
        if token:
            value = value.replace(token, '[credencial]')
    return value

def run(args: list[str], timeout: int = 20, cwd: Path | None = None) -> Result:
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never',
               GIT_SSH_COMMAND='ssh -oBatchMode=yes -oConnectTimeout=8')
    try:
        p = subprocess.run(args, cwd=cwd, env=env, capture_output=True,
                           timeout=timeout, encoding='utf-8', errors='replace')
        return Result(p.returncode, p.stdout, redact(p.stderr))
    except subprocess.TimeoutExpired:
        return Result(124, error='Tempo limite excedido')
    except OSError:
        return Result(127, error='Comando indisponível ou não executável')

def git(repo: Path, *args: str, timeout: int = 20) -> Result:
    return run(['git', '-C', str(repo), *args], timeout)
