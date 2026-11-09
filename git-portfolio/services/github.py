import json
import os
import re
from urllib.request import Request, urlopen
from urllib.error import URLError
from utils.commands import run

def github_slug(url: str) -> str:
    patterns = [r'https?://(?:[^/@]+@)?github\.com/([^?#]+)',
                r'git@github\.com:(.+)', r'ssh://git@github\.com(?::[0-9]+)?/(.+)']
    for pattern in patterns:
        match = re.fullmatch(pattern, url)
        if match:
            slug = match[1].removesuffix('/').removesuffix('.git')
            return slug if re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', slug) else ''
    return ''

def visibility(url: str) -> str:
    slug = github_slug(url)
    if not slug:
        return 'DESCONHECIDO'
    values = {'public':'PUBLICO','private':'PRIVADO','internal':'INTERNO'}
    result = run(['gh','api',f'repos/{slug}','--jq','.visibility'], timeout=10)
    if result.code == 0 and result.out.strip() in values:
        return values[result.out.strip()]
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token:
        auth = run(['gh','auth','token'], timeout=10)
        token = auth.out.strip() if auth.code == 0 else ''
    headers = {'Accept':'application/vnd.github+json', 'User-Agent':'Git-Portfolio'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    try:
        with urlopen(Request(f'https://api.github.com/repos/{slug}', headers=headers), timeout=8) as response:
            data = json.load(response)
        return values.get(data.get('visibility'), 'DESCONHECIDO')
    except (URLError, OSError, ValueError, TypeError, AttributeError):
        return 'DESCONHECIDO'

def commit_url(remote: str, commit_hash: str) -> str | None:
    slug = github_slug(remote)
    if slug and re.fullmatch(r'[0-9a-fA-F]{40,64}', commit_hash):
        return f'https://github.com/{slug}/commit/{commit_hash}'
    return None
