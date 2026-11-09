from collections import Counter

def show(root, all_rows, rows, health, only_problems):
    print('\n=== RESUMO GERAL ===')
    print(f'Total de projetos: {len(all_rows)} | Exibidos: {len(rows)} | Indice de saude: {health}%')
    for name,count in sorted(Counter(r['Situacao'] for r in all_rows).items()):
        print(f'  {name:<23} {count:>4}')
    print('\nPROJETOS POR ULTIMO COMMIT (MAIS RECENTES PRIMEIRO)')
    show_cols = ['Projeto','Branch','Situacao','DataUltimoCommit','ArquivosAlterados','DiasSemAtividade','Inativo']
    if not rows:
        print('Nenhum projeto corresponde ao filtro.' if only_problems else 'Nenhum repositorio Git encontrado.')
    else:
        widths = [min(40,max(len(c),*(len(str(r[c] if r[c] is not None else '—')) for r in rows))) for c in show_cols]
        print('  '.join(c.ljust(w) for c,w in zip(show_cols,widths)))
        print('  '.join('-'*w for w in widths))
        for r in rows:
            print('  '.join(str(r[c] if r[c] is not None else '—')[:w].ljust(w) for c,w in zip(show_cols,widths)))
    committed = [r for r in rows if r['_timestamp'] is not None]
    for label,subset in [('TOP 5 MAIS RECENTES',committed[:5]),('TOP 5 MAIS ANTIGOS',list(reversed(committed[-5:])) )]:
        print('\n'+label)
        for r in subset:
            print(f"  {r['Projeto']:<35.35} {r['DataUltimoCommit']}  ({r['DiasSemAtividade']} dias)")
    for name in ['relatorio-git.csv','relatorio-git.json','relatorio-git.html','historico-git.json']:
        if (root/name).exists(): print(f'{name}: {root/name}')
