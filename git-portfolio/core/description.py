"""Conservative local description extraction; no network or generated content."""
import html
import json
import re
import unicodedata
from pathlib import Path

UNAVAILABLE = 'Descrição do problema não disponível'


def plain(value: str) -> str:
    value = re.sub(r'<!--.*?-->|<(script|style)\b[^>]*>.*?</\1>', '', value, flags=re.S | re.I)
    value = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', value)
    value = re.sub(r'\[([^\]]+)\]\([^)]*\)|\[([^\]]+)\]\[[^\]]*\]', lambda m: m[1] or m[2], value)
    value = re.sub(r'<[^>]*>', '', value)
    value = html.unescape(value)
    value = re.sub(r'[*_`~]', '', value)
    return ' '.join(value.split())


def shorten(value: str) -> str:
    if len(value) <= 300:
        return value
    prefix = value[:300]
    endings = list(re.finditer(r'[.!?](?=\s|$)', prefix))
    if endings:
        return prefix[:endings[-1].end()]
    return prefix[:297].rsplit(' ', 1)[0].rstrip() + '…'


def relevant(value: str) -> bool:
    return len(value) >= 20 and len(re.findall(r'[^\W\d_]+', value)) >= 4


def normalized(value: str) -> str:
    return ''.join(c for c in unicodedata.normalize('NFKD', value.lower()) if not unicodedata.combining(c))


def extract_readme(source: str) -> str:
    candidates = []
    paragraph = []
    priority = False
    excluded = False
    fenced = False

    def flush():
        value = plain(' '.join(paragraph))
        paragraph.clear()
        if not excluded and relevant(value) and not re.match(
            r'^(?:pip |npm |yarn |git |python |curl |sudo |cd |install|instal|execute|run |usage|uso\b)',
            normalized(value)
        ):
            candidates.append((priority, value))

    lines = source.splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r'^(`{3,}|~{3,})', stripped):
            flush()
            fenced = not fenced
            continue
        if fenced:
            continue
        heading = re.match(r'^#{1,6}\s+(.+?)(?:\s+#+)?$', stripped)
        underline = index + 1 < len(lines) and re.fullmatch(r'\s*(?:=+|-+)\s*', lines[index + 1])
        if heading or (stripped and underline):
            flush()
            title = normalized(plain(heading[1] if heading else stripped))
            priority = bool(re.search(r'\b(problema|objetivo|sobre|descricao)\b', title))
            excluded = bool(re.search(r'\b(instalacao|installation|install|setup|getting started|uso|usage|comandos|commands|requisitos|requirements)\b', title))
            continue
        if not stripped or re.match(r'^(?:\s{4}|\t|!\[|<|\[!|\[.*\]:|[-=*]{3,}$|\$ |[|])', line):
            flush()
            continue
        if re.match(r'^[-*+]\s|^\d+[.)]\s', stripped):
            flush()
            stripped = re.sub(r'^(?:[-*+]|\d+[.)])\s+', '', stripped)
        paragraph.append(stripped)
    flush()
    for preferred in (True, False):
        for priority, value in candidates:
            if priority == preferred:
                return shorten(value)
    return UNAVAILABLE


def describe(repo: Path) -> str:
    try:
        data = json.loads((repo / 'portfolio.json').read_text(encoding='utf-8-sig'))
        value = data.get('problema') if isinstance(data, dict) else None
        if isinstance(value, str):
            value = plain(value)
            if relevant(value):
                return shorten(value)
    except (OSError, ValueError):
        pass
    try:
        files = sorted((p for p in repo.iterdir() if re.fullmatch(r'readme(?:\.[^.]+)?', p.name, re.I)),
                       key=lambda p: (p.name.lower() != 'readme.md', p.name.lower(), p.name))
        for path in files:
            try:
                value = extract_readme(path.read_text(encoding='utf-8-sig'))
                if value != UNAVAILABLE:
                    return value
            except (OSError, UnicodeError):
                continue
    except OSError:
        pass
    return UNAVAILABLE
