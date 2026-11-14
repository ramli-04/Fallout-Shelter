"""Render recorded results only. No inference, network access or simulation rerun."""
import argparse
import html
import json
from pathlib import Path

def render(source: Path) -> Path:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    data = json.loads(source.read_text(encoding='utf-8'))
    folder = source.parent
    (folder / '.gdignore').touch()
    ids = ['S1', 'S2', 'S3', 'S4', 'S5']
    samples = data['samples']
    charts = []
    for key, title, unit in [
        ('occupancy', 'Population over time', 'Living residents'),
        ('food_person_days', 'Food over time', 'Person-days'),
        ('water_liters', 'Water over time', 'Liters'),
        ('survival_rate', 'Survival rate', 'Fraction of shelter arrival cohort alive'),
        ('family_survivors', 'Family survival', 'Living residents with a family'),
        ('infrastructure_reliability', 'Infrastructure reliability', 'Mean power / air / water uptime fraction'),
    ]:
        fig, ax = plt.subplots(figsize=(9, 4.5), layout='constrained')
        for sid in ids:
            rows = [(s['day'], s['shelters'][sid].get(key)) for s in samples if s['shelters'][sid]['exists']]
            ax.plot([x for x, y in rows], [float('nan') if y is None else y for x, y in rows], label=sid)
        ax.set(xlabel='Simulated days after impact', ylabel=unit, title=title, xlim=(0, 10))
        ax.grid(alpha=.2); ax.legend(ncol=5)
        fig.savefig(folder / f'{key}.png', dpi=150)
        fig.savefig(folder / f'{key}.svg')
        plt.close(fig); charts.append((key, title))
    fig, ax = plt.subplots(figsize=(9, 4.5), layout='constrained')
    for sid in ids:
        values = data['shelters'][sid]['stress']
        if values:
            ax.hist(values, bins=range(0, 101, 10), histtype='step', linewidth=2, label=sid)
    ax.set(xlabel='Stress (0–100)', ylabel='Survivors', title='Final stress distribution')
    if ax.has_data(): ax.legend()
    else: ax.text(.5, .5, 'No sheltered survivors', transform=ax.transAxes, ha='center')
    fig.savefig(folder / 'stress.png', dpi=150); fig.savefig(folder / 'stress.svg'); plt.close(fig)
    charts.append(('stress', 'Final stress distribution'))
    page = ['<!doctype html><meta charset="utf-8"><title>ESSAIM survival results</title>',
            '<style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px;background:#f3f5ef;color:#24352f}img{width:100%}pre{white-space:pre-wrap;overflow-wrap:anywhere}section{background:white;padding:20px;margin:20px 0}</style>',
            '<h1>Ten-day survival results</h1><p>Recorded simulation data. Outside hazard indices are fictional scenario inputs. Missing observations remain gaps; empty arrival cohorts have no survival rate.</p>']
    for key in ['population', 'family', 'shelters', 'social', 'initial_social', 'storyteller', 'ai', 'survivor_outcomes']:
        page.append(f'<details><summary>{html.escape(key.replace("_", " ").title())}</summary><pre>{html.escape(json.dumps(data[key], indent=2))}</pre></details>')
    for key, title in charts:
        page.append(f'<section><h2>{title}</h2><img src="{key}.png" alt="{title}"><a href="{key}.svg">Download SVG</a></section>')
    page.append('<details><summary>Daily reports</summary><pre>'+html.escape(json.dumps(data['daily_reports'], indent=2))+'</pre></details>')
    target=folder/'report.html'; target.write_text('\n'.join(page), encoding='utf-8')
    return target

if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('results', type=Path)
    print(render(parser.parse_args().results))
