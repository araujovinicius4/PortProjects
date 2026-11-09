import html
import re
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit
from services.github import commit_url as remote_commit_url
from utils.commands import redact


def remote_values(value):
    """Return credential-free display/copy text and an optional web destination."""
    if not value or value == '—':
        return '', None
    original = str(value)
    try:
        if '://' in original:
            parts = urlsplit(original)
            if parts.scheme.lower() not in ('http', 'https', 'ssh', 'git'):
                return '[remoto não suportado]', None
            host = parts.hostname
            if not host or any(c.isspace() for c in host):
                return '[remoto inválido]', None
            host = f'[{host}]' if ':' in host else host
            port = f':{parts.port}' if parts.port else ''
            # Query strings and fragments can contain access tokens.
            authority = host + port
            if parts.scheme.lower() == 'ssh' and parts.username and not parts.password:
                authority = parts.username + '@' + authority
            display = urlunsplit((parts.scheme, authority, parts.path, '', ''))
            target = urlunsplit((parts.scheme if parts.scheme.lower() in ('http', 'https') else 'https',
                                host + (port if parts.scheme.lower() in ('http', 'https') else ''),
                                parts.path, '', ''))
            return redact(display), redact(target)
        match = re.fullmatch(r'([^/@:\s]+@)?([A-Za-z0-9.-]+):([^?#]+)', original)
        if match and match[2].lower() not in ('javascript', 'data', 'vbscript', 'file'):
            return redact(original), redact(f'https://{match[2]}/{match[3]}')
        return redact(original.split('?', 1)[0].split('#', 1)[0]), None
    except ValueError:
        return '[remoto inválido]', None

def write(root, run_at, all_rows, rows, health, inactive_days, export_rows):
    html_cols = ['Projeto','Visibilidade','Branch','Situacao','ArquivosAlterados','Autor',
                 'DataUltimoCommit','DiasSemAtividade','Inativo','UltimoCommit','Remoto']
    colors = {'SINCRONIZADO':'#16a34a','RECEBER':'#f59e0b','ENVIAR':'#2563eb',
              'DIVERGENTE':'#a855f7','ALTERACOES LOCAIS':'#0d9488'}
    counts = Counter(r['Situacao'] for r in all_rows)
    total = len(all_rows)
    segments = []
    start = 0
    for name, n in sorted(counts.items(),key=lambda x:(-x[1],x[0])):
        end = start + (100*n/total if total else 0)
        segments.append(f"{colors.get(name,'#64748b')} {start:.4f}% {end:.4f}%")
        start = end
    pie_style = 'conic-gradient(' + ','.join(segments) + ')' if segments else '#e2e8f0'
    legend = ''.join(f'<li><span class="dot" style="background:{colors.get(name,"#64748b")}"></span>'
                     f'{html.escape(name)} <strong>{n}</strong></li>' for name,n in sorted(counts.items(),key=lambda x:(-x[1],x[0])))

    def render_cell(r,c):
        if c == 'Remoto':
            display, target = remote_values(r[c])
            if not display:
                return '—'
            label = html.escape(display, quote=True)
            link = (f'<a href="{html.escape(target, quote=True)}" target="_blank" '
                    f'rel="noopener noreferrer">{label}</a>' if target else label)
            return (f'<button type="button" class="copy-remote" data-remote="{label}" '
                    f'aria-label="Copiar URL do remoto">Copiar</button> {link}')
        if c != 'Situacao' or r[c] not in ('RECEBER','DIVERGENTE'):
            return html.escape(str(r[c] if r[c] is not None else '—'))
        commits = r.get('CommitsPendentes',[])
        if not commits:
            return html.escape(r[c])+' <small>(detalhes indisponíveis)</small>'
        entries = []
        for commit in commits:
            h = commit['hash']
            short = html.escape(h[:10])
            url = remote_commit_url(r['Remoto'],h)
            hash_label = (f'<a href="{html.escape(url,quote=True)}" target="_blank" rel="noopener noreferrer">{short}</a>'
                          if url else f'<code>{short}</code>')
            entries.append(f'<li>{hash_label} — {html.escape(commit["mensagem"])}'
                           f'<div class="commit-meta">{html.escape(commit["autor"])} · {html.escape(commit["data"])}</div></li>')
        return (f'<details class="pending"><summary>{html.escape(r[c])} ({len(commits)})</summary>'
                f'<div class="pending-content"><strong>Commits disponíveis para receber</strong>'
                f'<ol>{"".join(entries)}</ol><small>Somente consulta; nenhum git pull é executado.</small></div></details>')

    trs = '\n'.join('<tr>'+''.join('<td>'+render_cell(r,c)+'</td>' for c in html_cols)+'</tr>' for r in export_rows)
    heads = ''.join('<th>'+html.escape(c)+'</th>' for c in html_cols)
    escaped_run_at = html.escape(run_at)
    displayed = len(rows)
    chart_label = html.escape('; '.join(f'{k}: {v}' for k,v in counts.items()),quote=True)
    template_dir = Path(__file__).parent / 'templates'
    stylesheet = (template_dir / 'report.css').read_text(encoding='utf-8')
    javascript = (template_dir / 'report.js').read_text(encoding='utf-8')
    page = (template_dir / 'report.html').read_text(encoding='utf-8').format_map(locals())
    (root/'relatorio-git.html').write_text(page,encoding='utf-8')


