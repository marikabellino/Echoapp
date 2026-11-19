"""Genera gli sticker di mingle. da stampare (PDF vettoriali con abbondanza).

- sticker-logo:  90 × 36 mm, logo "mingle." con Dot che ride, fondo scuro
- sticker-qr:    60 × 80 mm, Dot che spunta sopra un QR code verso
                 instagram.com/mingletheapp

Ogni PDF ha 3 mm di abbondanza per lato (fondo esteso oltre il taglio).
Nelle anteprime PNG la linea tratteggiata è il taglio: non va stampata.

Uso: python3 genera_sticker.py   (richiede segno e Playwright/Chromium)
"""
import os
import re
import subprocess

import segno

HERE = os.path.dirname(os.path.abspath(__file__))
DOT = os.path.join(HERE, '..', 'dot')
INK, PAPER, MAGENTA, BLUSH = '#0D0B0E', '#F7F1F4', '#FF3D7F', '#FF8FB1'
BLEED = 3
URL = 'https://www.instagram.com/mingletheapp/'

# Dot che ride: occhi chiusi all'insù, bocca aperta con la lingua
LAUGH = (
    '<g fill="#FFFFFF" opacity="0.24"><ellipse cx="63" cy="110" rx="9" ry="5"/><ellipse cx="137" cy="110" rx="9" ry="5"/></g>'
    f'<path d="M68 96 L78 85 L88 96" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>'
    f'<path d="M112 96 L122 85 L132 96" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>'
    f'<path d="M82 112 Q100 142 118 112 Z" fill="{INK}"/>'
    f'<ellipse cx="104" cy="127" rx="7" ry="5" fill="{BLUSH}"/>'
)


def blob():
    s = open(os.path.join(DOT, 'dot-felice.svg')).read()
    return re.search(r'<g id="Corpo"><path d="([^"]+)"', s).group(1)


def logo_laughing():
    s = open(os.path.join(DOT, 'logo-mingle-per-fondo-scuro.svg')).read()
    return re.sub(r'(<g id="Faccia" transform="[^"]+">).*?(</g></g></svg>)',
                  lambda m: m.group(1) + LAUGH + '</g></g></svg>', s, flags=re.S)


def qr_svg():
    q = segno.make(URL, error='q', micro=False)
    n = q.symbol_size(border=0)[0]
    rects = ''.join(f'<rect x="{x}" y="{y}" width="1.02" height="1.02"/>'
                    for y, row in enumerate(q.matrix) for x, v in enumerate(row) if v)
    return (f'<svg viewBox="0 0 {n} {n}" width="100%" height="100%" shape-rendering="crispEdges">'
            f'<g fill="{INK}">{rects}</g></svg>')


HEAD = """<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600..800&family=DM+Mono:wght@500&display=swap">
<style>
@page{{size:{W}mm {H}mm;margin:0}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}mm;height:{H}mm;overflow:hidden}}
body{{position:relative;background:{bg};-webkit-print-color-adjust:exact;print-color-adjust:exact}}
.cut{{position:absolute;left:{b}mm;top:{b}mm;width:{w}mm;height:{h}mm;border-radius:{r}mm;border:.25mm dashed #00C2FF;display:none}}
body.preview .cut{{display:block}}
{css}
</style></head><body>"""


def page(name, w, h, r, bg, css, inner):
    W, H = w + 2 * BLEED, h + 2 * BLEED
    html = HEAD.format(W=W, H=H, bg=bg, b=BLEED, w=w, h=h, r=r, css=css) + inner + '<div class="cut"></div></body></html>'
    path = os.path.join(HERE, name + '.html')
    open(path, 'w').write(html)
    return path, W, H


def build():
    blob_d = blob()
    p1 = page('sticker-logo', 90, 36, 6, INK, f"""
.logo{{position:absolute;left:{BLEED + 9}mm;top:{BLEED + 7.5}mm;width:72mm}}
.logo svg{{width:72mm;height:auto;display:block}}
""", f'<div class="logo">{logo_laughing()}</div>')

    p2 = page('sticker-qr', 60, 80, 6, INK, f"""
.card{{position:absolute;left:{BLEED + 8}mm;top:{BLEED + 20}mm;width:44mm;height:44mm;background:#FFFFFF;border-radius:4mm;padding:4.6mm}}
.dot{{position:absolute;left:{BLEED + 30 - 11}mm;top:{BLEED + 1}mm;width:22mm;height:22mm}}
.handle{{position:absolute;left:0;right:0;top:{BLEED + 67}mm;text-align:center;font-family:'Bricolage Grotesque',sans-serif;font-weight:800;font-size:5.2mm;letter-spacing:-.02em;color:{PAPER}}}
.sub{{position:absolute;left:0;right:0;top:{BLEED + 73.4}mm;text-align:center;font-family:'DM Mono',monospace;font-size:2.3mm;letter-spacing:.18em;color:{BLUSH}}}
""", f'<div class="card">{qr_svg()}</div>'
        f'<div class="dot"><svg viewBox="0 0 200 200" width="100%" height="100%"><path d="{blob_d}" fill="{MAGENTA}"/>{LAUGH}</svg></div>'
        '<div class="handle">@mingletheapp</div><div class="sub">SEGUICI SU INSTAGRAM</div>')
    return [p1, p2]


JS = r"""
const {chromium}=require('playwright');
(async()=>{const [path,W,H,out]=process.argv.slice(2);const b=await chromium.launch();const p=await b.newPage();
await p.goto('file://'+path,{waitUntil:'networkidle'});await p.evaluate(()=>document.fonts.ready);
await p.pdf({path:out+'.pdf',width:W+'mm',height:H+'mm',printBackground:true,pageRanges:'1'});
const px=mm=>Math.round(mm/25.4*300);await p.setViewportSize({width:px(W),height:px(H)});
await p.evaluate(()=>{document.body.style.zoom=300/96;document.body.classList.add('preview')});
await p.screenshot({path:out+'-anteprima.png'});await b.close();})();
"""


if __name__ == '__main__':
    js = os.path.join(HERE, '.render.js')
    open(js, 'w').write(JS)
    for path, W, H in build():
        out = path[:-5]
        subprocess.run(['node', js, path, str(W), str(H), out], check=True)
        os.remove(path)
        print(os.path.basename(out) + '.pdf', f'{W}x{H} mm')
    os.remove(js)
