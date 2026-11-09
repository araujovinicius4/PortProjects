import json

def write(root, run_at, all_rows, rows, health, only_problems, inactive_days, export_rows):
    with open(root/'relatorio-git.json','w',encoding='utf-8') as f:
        json.dump({'DataExecucao':run_at,'TotalProjetos':len(all_rows),'ProjetosExibidos':len(rows),
                   'IndiceSaude':health,'FiltroSomenteProblemas':only_problems,
                   'LimiteInatividadeDias':inactive_days,'Projetos':export_rows},f,ensure_ascii=False,indent=2)


