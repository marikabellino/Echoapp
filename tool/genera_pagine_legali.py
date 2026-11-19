"""Genera le pagine web di privacy, termini e regole dai testi dell'app.

Legge lib/features/legal/legal_texts.dart (unica fonte dei testi) e scrive
privacy.html, termini.html e regole.html nella cartella indicata, di solito
il repository mingle-web, così app e sito dicono sempre la stessa cosa.

Uso: python3 tool/genera_pagine_legali.py ../mingle-web/legal
"""
import html
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'lib', 'features', 'legal', 'legal_texts.dart')

LIT = r"'((?:[^'\\]|\\.)*)'"


def unescape(s):
    return s.replace("\\'", "'").replace('\\n', '\n').replace('\\\\', '\\')


def parse(src):
    consts = {}
    for m in re.finditer(r"const (\w+) =\s*" + LIT + ';', src):
        consts[m.group(1)] = unescape(m.group(2))
    for m in re.finditer(r'const (\w+) = (\d+);', src):
        consts[m.group(1)] = m.group(2)

    def subst(s):
        return re.sub(r'\$(\w+)', lambda m: consts.get(m.group(1), m.group(0)), s)

    lists = {}
    for m in re.finditer(r'const (\w+) = <LegalSection>\[(.*?)\n\];', src, re.S):
        sections = []
        for e in re.finditer(r'title:\s*' + LIT + r',\s*body:\s*((?:\s*' + LIT + r')+)\s*,', m.group(2)):
            body = ''.join(unescape(x) for x in re.findall(LIT, e.group(2)))
            sections.append((subst(unescape(e.group(1))), subst(body)))
        lists[m.group(1)] = sections
    return consts, lists


def body_html(text):
    out, items = [], []
    for line in text.split('\n'):
        if line.startswith('• '):
            items.append(f'<li>{html.escape(line[2:])}</li>')
            continue
        if items:
            out.append('<ul>' + ''.join(items) + '</ul>')
            items = []
        out.append(f'<p>{html.escape(line)}</p>')
    if items:
        out.append('<ul>' + ''.join(items) + '</ul>')
    return ''.join(out)


PAGE = """<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<meta name="theme-color" content="#0D0B0E" />
<title>mingle. — {title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Oi&family=Bricolage+Grotesque:opsz,wght@12..96,600..800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
/* Generata da Echoapp/tool/genera_pagine_legali.py: non modificare a mano. */
:root{{--ink:#0D0B0E;--ink2:#17131A;--paper:#F7F1F4;--muted:#A79CA8;--magenta:#FF3D7F;color-scheme:dark}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:var(--ink);color:var(--paper);font-family:"Inter",system-ui,sans-serif;line-height:1.6;padding:40px 20px 64px}}
main{{max-width:720px;margin:0 auto}}
.wordmark{{font-family:"Oi",Georgia,serif;font-size:30px;display:inline-flex;align-items:flex-end;gap:2px;color:var(--paper);text-decoration:none;margin-bottom:36px}}
.wordmark i{{width:13px;height:13px;border-radius:50%;background:var(--magenta);display:inline-block;margin-bottom:3px}}
nav{{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:32px}}
nav a{{color:var(--muted);text-decoration:none;font-size:14px;padding:8px 14px;border-radius:999px;background:var(--ink2)}}
nav a.on{{background:var(--paper);color:var(--ink);font-weight:600}}
h1{{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:40px;letter-spacing:-.03em;line-height:1.05;margin-bottom:8px}}
.ver{{color:var(--muted);font-size:14px;margin-bottom:32px}}
section{{background:var(--ink2);border:1px solid rgba(247,241,244,.08);border-radius:24px;padding:24px;margin-bottom:14px}}
h2{{font-family:"Bricolage Grotesque",sans-serif;font-weight:700;font-size:21px;margin-bottom:10px}}
p,li{{color:#D9D0D5;font-size:15.5px}}
p+p,ul+p,p+ul{{margin-top:10px}}
ul{{padding-left:20px}}
li+li{{margin-top:6px}}
footer{{margin-top:32px;color:var(--muted);font-size:13px}}
</style>
</head>
<body>
<main>
<a class="wordmark" href="../">mingle<i></i></a>
<nav>{nav}</nav>
<h1>{title}</h1>
<p class="ver">Versione del {version}</p>
{sections}
<footer>Gli stessi testi sono nell’app, in Profilo → Impostazioni.</footer>
</main>
</body>
</html>
"""

PAGES = [
    ('privacy.html', 'Informativa privacy', 'privacySections'),
    ('termini.html', 'Termini d’uso', 'termsSections'),
    ('regole.html', 'Regole della community', 'guidelinesSections'),
]


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    consts, lists = parse(open(SRC, encoding='utf-8').read())
    for fname, title, key in PAGES:
        nav = ''.join(f'<a href="{f}"{" class=\"on\"" if f == fname else ""}>{t}</a>' for f, t, _ in PAGES)
        secs = ''.join(f'<section><h2>{html.escape(t)}</h2>{body_html(b)}</section>' for t, b in lists[key])
        assert lists[key], key
        with open(os.path.join(out_dir, fname), 'w', encoding='utf-8') as fh:
            fh.write(PAGE.format(title=title, nav=nav, version=consts.get('legalVersion', ''), sections=secs))
        print(fname, len(lists[key]), 'sezioni')


if __name__ == '__main__':
    main()
