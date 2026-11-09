import json
import sys

def append(root, run_at, all_rows, health):
    hist_path = root/'historico-git.json'
    history = []
    if hist_path.exists():
        try:
            data = json.loads(hist_path.read_text(encoding='utf-8-sig'))
            if isinstance(data,list): history = data
            elif isinstance(data,dict): history = [data]
        except (OSError,ValueError):
            print('Aviso: historico anterior invalido; sera preservado em vez de sobrescrito.',file=sys.stderr)
            history = None
    if history is not None:
        history.append({'DataExecucao':run_at,'TotalProjetos':len(all_rows),'IndiceSaude':health})
        hist_path.write_text(json.dumps(history,ensure_ascii=False,indent=2),encoding='utf-8')


