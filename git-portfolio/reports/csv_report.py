import csv
import json

def write(root, columns, export_rows):
    with open(root/'relatorio-git.csv','w',encoding='utf-8-sig',newline='') as f:
        writer = csv.DictWriter(f,fieldnames=columns)
        writer.writeheader(); writer.writerows([{**r,'CommitsPendentes':json.dumps(r['CommitsPendentes'],ensure_ascii=False)} for r in export_rows])

