"""Genera gli sticker di mingle. da stampare, con linea di taglio (fustella).

Gli sticker:
- sticker-scritta: solo la scritta "mingle." con Dot che ride, sagomata
  (il taglio segue il contorno della scritta, con un bordo bianco)
- sticker-qr:      60 × 80 mm, angoli arrotondati, Dot sopra un QR code
                   verso instagram.com/mingletheapp
- dot/sticker-dot-*: Dot da solo in sei pose (ride, inclinato, occhiolino,
                   occhiali, salta, innamorato) e tre colori (rosa, ambra,
                   bianco su bordo scuro), con "mingle" piccolo, sagomato

Ogni PDF contiene la grafica e, sopra, la linea di taglio come tinta piatta
"CutContour" in sovrastampa: è il formato che chiedono le tipografie per gli
sticker sagomati. La linea di taglio non viene stampata.
Nelle anteprime PNG il taglio è la linea azzurra tratteggiata.

Uso: python3 genera_sticker.py   (richiede segno, opencv, reportlab, pypdf
e Playwright/Chromium)
"""
import os
import re
import subprocess

import cv2
import numpy as np
import segno
from pypdf import PdfReader, PdfWriter
from reportlab.lib.colors import CMYKColorSep
from reportlab.pdfgen import canvas

HERE = os.path.dirname(os.path.abspath(__file__))
DOT = os.path.join(HERE, '..', 'dot')
INK, PAPER, MAGENTA, BLUSH, AMBER = '#0D0B0E', '#F7F1F4', '#FF3D7F', '#FF8FB1', '#FFB547'
# colori di Dot (come sulla mappa): nome, corpo, scritta, fondo attorno a Dot
DOT_COLORS = [('rosa', MAGENTA, PAPER, '#FFFFFF'), ('ambra', AMBER, INK, '#FFFFFF'), ('bianco', PAPER, INK, INK)]
URL = 'https://www.instagram.com/mingletheapp/'
MM = 72 / 25.4          # punti PDF per millimetro
MASK_DPI = 600

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


def logo_laughing(variant):
    s = open(os.path.join(DOT, f'logo-mingle-per-fondo-{variant}.svg')).read()
    return re.sub(r'(<g id="Faccia" transform="[^"]+">).*?(</g></g></svg>)',
                  lambda m: m.group(1) + LAUGH + '</g></g></svg>', s, flags=re.S)


def wordmark(fill):
    """Solo la scritta "mingle" (senza Dot), in un <svg> ritagliato sulle lettere."""
    s = open(os.path.join(DOT, 'logo-mingle-per-fondo-scuro.svg')).read()
    g = re.search(r'<g id="Scritta"[^>]*>(.*?)</g>', s, re.S).group(1)
    # ingombro delle lettere nel vettoriale del logo (misurato con getBBox)
    return 8, -876, 5544, 1052, f'<g fill="{fill}">{g}</g>'


def dot_poses():
    """Le sei pose di Dot: (nome, rotazione °, scala x, scala y, faccia)."""
    import sys
    sys.path.insert(0, DOT)
    import genera_vettoriali as gv
    face = lambda k: gv.FACES[k][1]
    cheeks = gv.cheeks()
    occhiali = (re.search(r'<g id="Occhi">.*?</g>', face('festa')).group(0)
                + f'<path d="M80 113 Q100 146 120 113 Z" fill="{INK}"/><ellipse cx="100" cy="128" rx="8" ry="4.5" fill="{BLUSH}"/>')
    return [
        ('1-ride', 0, 1, 1, LAUGH),
        ('2-ride-inclinato', -14, 1, 1, LAUGH),
        ('3-occhiolino', 10, 1, 1, cheeks + face('occhiolino')),
        ('4-occhiali', -8, 1, 1, cheeks + occhiali),
        ('5-salta', 0, 1.08, 0.9, LAUGH),
        ('6-innamorato', 8, 1, 1, cheeks + face('innamorato')),
    ]


def qr_svg():
    q = segno.make(URL, error='q')
    n = q.symbol_size(border=0)[0]
    rects = ''.join(f'<rect x="{x}" y="{y}" width="1.02" height="1.02"/>'
                    for y, row in enumerate(q.matrix) for x, v in enumerate(row) if v)
    return (f'<svg viewBox="0 0 {n} {n}" width="100%" height="100%" shape-rendering="crispEdges">'
            f'<g fill="{INK}">{rects}</g></svg>')


HTML = """<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600..800&family=DM+Mono:wght@500&display=swap">
<style>
@page{{size:{W}mm {H}mm;margin:0}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}mm;height:{H}mm;overflow:hidden}}
body{{position:relative;background:{bg};-webkit-print-color-adjust:exact;print-color-adjust:exact}}
body.mask{{background:#fff}} body.mask .art{{filter:brightness(0)}}
{css}
</style></head><body><div class="art">{inner}</div></body></html>"""

JS = r"""
const {chromium}=require('playwright');
(async()=>{const [path,W,H,out,dpi]=process.argv.slice(2);const b=await chromium.launch();const p=await b.newPage();
await p.goto('file://'+path,{waitUntil:'networkidle'});await p.evaluate(()=>document.fonts.ready);
await p.pdf({path:out+'.grafica.pdf',width:W+'mm',height:H+'mm',printBackground:true,pageRanges:'1'});
const px=mm=>Math.round(mm/25.4*dpi);await p.setViewportSize({width:px(W),height:px(H)});
await p.evaluate(d=>{document.body.style.zoom=d/96},+dpi);
await p.screenshot({path:out+'.render.png'});
await p.evaluate(()=>document.body.classList.add('mask'));
await p.screenshot({path:out+'.mask.png'});
await b.close();})();
"""


def contour_from_mask(mask_png, offset_mm):
    """Contorno esterno della grafica, allargato di offset_mm, in millimetri."""
    m = cv2.imread(mask_png, cv2.IMREAD_GRAYSCALE)
    r = int(round(offset_mm / 25.4 * MASK_DPI))
    pad = r * 4  # margine vuoto: le operazioni sul bordo dell'immagine non creano punte
    ink = cv2.copyMakeBorder((m < 128).astype(np.uint8) * 255, pad, pad, pad, pad, cv2.BORDER_CONSTANT, value=0)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    grown = cv2.dilate(ink, k)
    # chiude i piccoli rientri tra le lettere, poi ammorbidisce il bordo
    grown = cv2.morphologyEx(grown, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (r * 5 + 1,) * 2))
    grown = (cv2.GaussianBlur(grown, (0, 0), r * 0.6) > 127).astype(np.uint8) * 255
    cs, _ = cv2.findContours(grown, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, 0.6, True)[:, 0, :].astype(float) - pad
    return c * 25.4 / MASK_DPI


def rounded_rect(x, y, w, h, r, n=12):
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for i in range(n + 1):
            a = np.radians(a0 + 90 * i / n)
            pts.append((cx + r * np.cos(a), cy + r * np.sin(a)))
    return np.array(pts)


def add_cut_line(art_pdf, pts_mm, W, H, out_pdf):
    cut_pdf = out_pdf + '.taglio.pdf'
    c = canvas.Canvas(cut_pdf, pagesize=(W * MM, H * MM))
    c.setStrokeColor(CMYKColorSep(0, 1, 0, 0, spotName='CutContour', density=1))
    c.setStrokeOverprint(True)
    c.setLineWidth(0.25)
    p = c.beginPath()
    for i, (x, y) in enumerate(pts_mm):
        (p.moveTo if i == 0 else p.lineTo)(x * MM, (H - y) * MM)
    p.close()
    c.drawPath(p, stroke=1, fill=0)
    c.save()
    page = PdfReader(art_pdf).pages[0]
    page.merge_page(PdfReader(cut_pdf).pages[0])
    w = PdfWriter()
    w.add_page(page)
    with open(out_pdf, 'wb') as fh:
        w.write(fh)
    os.remove(cut_pdf)


def preview(render_png, pts_mm, out_png, shade):
    im = cv2.imread(render_png)
    s = MASK_DPI / 25.4
    poly = (pts_mm * s).astype(np.int32)
    if shade:  # fuori dal taglio: grigio, così si vede la forma dello sticker
        mask = np.zeros(im.shape[:2], np.uint8)
        cv2.fillPoly(mask, [poly], 255)
        im[mask == 0] = (im[mask == 0] * 0.35 + np.array([150, 150, 150]) * 0.65).astype(np.uint8)
    # linea tratteggiata: punti ogni ~0,5 mm lungo il contorno, tratti alterni
    dense = []
    for a, b in zip(poly, np.roll(poly, -1, axis=0)):
        n = max(1, int(np.hypot(*(b - a)) / (0.5 * s)))
        dense += [a + (b - a) * t / n for t in range(n)]
    dense = np.array(dense).astype(np.int32)
    for i in range(len(dense)):
        if (i // 4) % 2 == 0:
            cv2.line(im, tuple(dense[i]), tuple(dense[(i + 1) % len(dense)]), (255, 194, 0), 4, cv2.LINE_AA)
    im = cv2.resize(im, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
    cv2.imwrite(out_png, im)


def make(name, W, H, bg, css, inner, cut):
    path = os.path.join(HERE, name + '.html')
    open(path, 'w').write(HTML.format(W=W, H=H, bg=bg, css=css, inner=inner))
    out = os.path.join(HERE, name)
    subprocess.run(['node', os.path.join(HERE, '.render.js'), path, str(W), str(H), out, str(MASK_DPI)], check=True)
    pts = cut(out + '.mask.png')
    add_cut_line(out + '.grafica.pdf', pts, W, H, out + '.pdf')
    preview(out + '.render.png', pts, out + '-anteprima.png', shade=True)
    for ext in ('.grafica.pdf', '.render.png', '.mask.png', '.html'):
        os.remove(out + ext)
    xs, ys = pts[:, 0], pts[:, 1]
    print(f'{name}.pdf  sticker {xs.max() - xs.min():.0f} × {ys.max() - ys.min():.0f} mm')


def main():
    open(os.path.join(HERE, '.render.js'), 'w').write(JS)
    # 1 · solo scritta, sagomata, bordo bianco di 1,5 mm
    make('sticker-scritta', 100, 40, '#FFFFFF',
         '.logo{position:absolute;left:10mm;top:8mm;width:80mm} .logo svg{width:80mm;height:auto;display:block}',
         f'<div class="logo">{logo_laughing("chiaro")}</div>',
         lambda m: contour_from_mask(m, 1.5))
    # 2 · QR, angoli arrotondati, fondo scuro con 3 mm di abbondanza
    B = 3
    make('sticker-qr', 66, 86, INK, f"""
.card{{position:absolute;left:{B + 8}mm;top:{B + 20}mm;width:44mm;height:44mm;background:#FFFFFF;border-radius:4mm;padding:4.6mm}}
.dot{{position:absolute;left:{B + 19}mm;top:{B + 1}mm;width:22mm;height:22mm}}
.handle{{position:absolute;left:0;right:0;top:{B + 67}mm;text-align:center;font-family:'Bricolage Grotesque',sans-serif;font-weight:800;font-size:5.2mm;letter-spacing:-.02em;color:{PAPER}}}
.sub{{position:absolute;left:0;right:0;top:{B + 73.4}mm;text-align:center;font-family:'DM Mono',monospace;font-size:2.3mm;letter-spacing:.18em;color:{BLUSH}}}
""", f'<div class="card">{qr_svg()}</div>'
        f'<div class="dot"><svg viewBox="0 0 200 200" width="100%" height="100%"><path d="{blob()}" fill="{MAGENTA}"/>{LAUGH}</svg></div>'
        '<div class="handle">@mingletheapp</div><div class="sub">SEGUICI SU INSTAGRAM</div>',
         lambda m: rounded_rect(B, B, 60, 80, 6))
    # 3 · Dot da solo: sei pose × tre colori (quelli della mappa), con la scritta piccola;
    #     sagomato con bordo di 1,2 mm (bianco, o scuro per il Dot bianco)
    wx, wy, ww, wh, _ = wordmark(PAPER)
    os.makedirs(os.path.join(HERE, 'dot'), exist_ok=True)
    for cname, body, word, back in DOT_COLORS:
        wg = wordmark(word)[4]
        for name, rot, sx, sy, face in dot_poses():
            if body == PAPER:  # su Dot bianco le guance bianche sparirebbero: diventano rosa
                face = face.replace('fill="#FFFFFF" opacity="0.24"', f'fill="{BLUSH}" opacity="0.55"')
            make(f'dot/sticker-dot-{name}-{cname}', 60, 60, back,
                 '.dot{position:absolute;left:10mm;top:10mm;width:40mm;height:40mm} .dot svg{overflow:visible}',
                 f'<div class="dot"><svg viewBox="28 26 148 148" width="100%" height="100%">'
                 f'<g transform="translate(100 100) rotate({rot}) scale({sx} {sy}) translate(-100 -100)">'
                 f'<path d="{blob()}" fill="{body}"/>{face}</g>'
                 f'<svg x="{100 - 33}" y="146" width="66" height="12.5" viewBox="{wx} {wy} {ww} {wh}">{wg}</svg></svg></div>',
                 lambda m: contour_from_mask(m, 1.2))
    os.remove(os.path.join(HERE, '.render.js'))


if __name__ == '__main__':
    main()
