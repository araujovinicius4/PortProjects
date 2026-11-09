from datetime import datetime, timezone
from models.repository import Repository

def prepare(repositories: list[Repository], inactive_days: int, now: datetime | None = None) -> list[dict]:
    now = now or datetime.now(timezone.utc)
    for r in repositories:
        if r._timestamp is not None:
            r.DiasSemAtividade = max(0, (now - datetime.fromtimestamp(r._timestamp,timezone.utc)).days)
        r.Inativo = 'SIM' if r.DiasSemAtividade is not None and r.DiasSemAtividade >= inactive_days else 'NAO'
    repositories.sort(key=lambda r: (-r._timestamp if r._timestamp is not None else float('inf'), r.Projeto.casefold()))
    return [r.row() for r in repositories]

def health(rows: list[dict]) -> int:
    healthy = sum(r['Situacao'] == 'SINCRONIZADO' and r['ArquivosAlterados'] == 0 for r in rows)
    return round(100 * healthy / len(rows)) if rows else 0
