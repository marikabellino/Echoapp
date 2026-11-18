"""Genera i vettoriali di Dot e del logo mingle. (SVG, apribili in Illustrator).

- dot-<espressione>.svg            Dot magenta
- dot-<espressione>-bianco.svg     Dot bianco (per fondi magenta o scuri)
- logo-mingle-chiaro.svg / -scuro  "mingle." con Dot al posto del punto,
                                   testo convertito in tracciati (font Oi, OFL)

Ogni SVG ha gruppi con nome (Corpo, Guance, Occhi, Bocca, Accessori), che
Illustrator mostra come livelli. Il corpo è un tracciato morbido con pochi
punti di ancoraggio, facile da ritoccare.

Uso: python3 genera_vettoriali.py [percorso/Oi.ttf]
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAGENTA = '#FF3D7F'
PAPER = '#F7F1F4'
INK = '#0D0B0E'
AMBER = '#FFB547'
BLUSH = '#FF8FB1'


# ── Corpo: blob morbido (stessa forma "viva" dell'app, fermata in un istante)
def blob_path(cx=100, cy=100, r=70, n=12, amp=0.045, t=0.6, seed=1.3):
    pts = []
    for i in range(n):
        a = i / n * 2 * math.pi
        k = 1 + amp * (0.55 * math.sin(3 * a + t * 1.4 + seed)
                       + 0.35 * math.sin(5 * a - t * 1.1 + seed * 2)
                       + 0.25 * math.sin(2 * a + t * 0.8))
        pts.append((cx + math.cos(a) * r * k, cy + math.sin(a) * r * k))
    # Catmull-Rom chiusa → curve di Bézier cubiche
    d = f'M{pts[0][0]:.2f} {pts[0][1]:.2f}'
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f' C{c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {p2[0]:.2f} {p2[1]:.2f}'
    return d + ' Z'


HEART = 'M0 9 C-16 -2 -12 -16 0 -8 C12 -16 16 -2 0 9 Z'
LINE = f'fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"'


def cheeks(on_paper=False):
    # Su un Dot bianco le guance bianche sparirebbero: diventano rosa.
    fill, op = (BLUSH, '0.55') if on_paper else ('#FFFFFF', '0.24')
    return (f'<g id="Guance" fill="{fill}" opacity="{op}">'
            '<ellipse cx="63" cy="110" rx="9" ry="5"/><ellipse cx="137" cy="110" rx="9" ry="5"/></g>')


def eyes_open(left=True, right=True, dx=0):
    out = ''
    for on, x in ((left, 79 + dx), (right, 121 + dx)):
        if on:
            out += (f'<ellipse cx="{x}" cy="88" rx="8" ry="11" fill="{INK}"/>'
                    f'<circle cx="{x + 3}" cy="83" r="2.6" fill="#FFFFFF"/>')
    return out


FACES = {
    'felice': ('Felice',
               f'<g id="Occhi">{eyes_open()}</g>'
               f'<g id="Bocca"><path d="M88 119 Q100 130 112 119" {LINE}/></g>', True),
    'innamorato': ('Innamorato',
                   '<g id="Occhi">'
                   f'<path transform="translate(78 90) scale(1.3)" d="{HEART}" fill="{INK}"/>'
                   f'<path transform="translate(122 90) scale(1.3)" d="{HEART}" fill="{INK}"/></g>'
                   f'<g id="Bocca"><path d="M84 118 Q100 131 116 118" {LINE}/></g>', True),
    'occhiolino': ('Occhiolino',
                   f'<g id="Occhi">{eyes_open(right=False)}'
                   f'<path d="M112 89 Q122 80 132 89" {LINE}/></g>'
                   f'<g id="Bocca"><path d="M88 119 Q100 130 112 119" {LINE}/></g>', True),
    'assonnato': ('Assonnato',
                  f'<g id="Occhi"><path d="M70 92 Q80 100 90 92" {LINE}/>'
                  f'<path d="M110 92 Q120 100 130 92" {LINE}/></g>'
                  f'<g id="Bocca"><ellipse cx="100" cy="121" rx="6" ry="7" fill="{INK}"/></g>', True),
    'confuso': ('Confuso',
                '<g id="Occhi"><circle cx="78" cy="90" r="13" fill="#FFFFFF"/>'
                '<circle cx="122" cy="90" r="13" fill="#FFFFFF"/>'
                f'<circle cx="72" cy="94" r="6" fill="{INK}"/><circle cx="126" cy="84" r="6" fill="{INK}"/></g>'
                f'<g id="Bocca"><path d="M82 124 q6 -7 12 0 t12 0 t12 0" {LINE.replace("6", "5", 1)}/></g>', False),
    'goloso': ('Goloso',
               f'<g id="Occhi"><path d="M68 96 L78 85 L88 96" {LINE}/>'
               f'<path d="M112 96 L122 85 L132 96" {LINE}/></g>'
               f'<g id="Bocca"><path d="M82 112 Q100 140 118 112 Z" fill="{INK}"/>'
               f'<ellipse cx="104" cy="126" rx="7" ry="5" fill="{BLUSH}"/></g>', True),
    'sbircia': ('Sbircia',
                '<g id="Occhi">'
                f'<ellipse cx="128" cy="92" rx="9" ry="12" fill="{INK}"/><circle cx="131" cy="86" r="3" fill="#FFFFFF"/>'
                f'<ellipse cx="160" cy="92" rx="9" ry="12" fill="{INK}"/><circle cx="163" cy="86" r="3" fill="#FFFFFF"/></g>', False),
    'festa': ('Festa',
              f'<g id="Occhi"><rect x="61" y="79" width="34" height="24" rx="11" fill="{INK}"/>'
              f'<rect x="105" y="79" width="34" height="24" rx="11" fill="{INK}"/>'
              f'<path d="M95 88 L105 88" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>'
              '<path d="M69 86 L75 81 M113 86 L119 81" fill="none" stroke="#FFFFFF" stroke-opacity="0.8" stroke-width="3.5" stroke-linecap="round"/></g>'
              f'<g id="Bocca"><path d="M80 113 Q100 146 120 113 Z" fill="{INK}"/>'
              f'<ellipse cx="100" cy="128" rx="8" ry="4.5" fill="{BLUSH}"/></g>'
              '<g id="Accessori"><g transform="translate(124 36) rotate(18)">'
              '<clipPath id="cono"><path d="M0 -64 L27 2 L-27 2 Z"/></clipPath>'
              f'<path d="M0 -64 L27 2 L-27 2 Z" fill="{AMBER}"/>'
              f'<g clip-path="url(#cono)" stroke="{PAPER}" stroke-width="8">'
              '<path d="M-40 -40 L40 -60"/><path d="M-40 -22 L40 -42"/>'
              '<path d="M-40 -4 L40 -24"/><path d="M-40 14 L40 -6"/></g>'
              f'<circle cx="0" cy="-64" r="9" fill="{PAPER}"/></g></g>', True),
}


def dot_svg(key, body):
    name, inner, has_cheeks = FACES[key]
    vb = '0 -40 200 240' if key == 'festa' else '0 0 200 200'
    w, h = (1000, 1200) if key == 'festa' else (1000, 1000)
    on_paper = body == PAPER
    if on_paper:
        # bianco degli occhi (Confuso) su corpo bianco: contorno sottile
        inner = inner.replace('fill="#FFFFFF"/>', f'fill="#FFFFFF" stroke="{INK}" stroke-width="2.5"/>') \
            if key == 'confuso' else inner
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="{w}" height="{h}">'
            f'<title>Dot – {name}</title>'
            f'<g id="Corpo"><path d="{blob_path()}" fill="{body}"/></g>'
            + (cheeks(on_paper) if has_cheeks else '') + inner + '</svg>\n')


# ── Logo: "mingle" in tracciati + Dot al posto del punto ────────────────────
def logo_svg(font_path, text_color, with_face=True):
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    f = TTFont(font_path)
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    upm = f['head'].unitsPerEm
    x = 0
    paths = []
    for ch in 'mingle':
        gname = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        # coordinate del font: y verso l'alto → nell'SVG y verso il basso
        gs[gname].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        paths.append((ch, pen.getCommands()))
        x += f['hmtx'][gname][0]
    fs = upm
    d = fs * 0.44
    gap = fs * 0.03
    cx = x + gap + d / 2
    cy = -fs * 0.05 - d / 2
    r = d / 2
    pad = fs * 0.12
    asc = f['hhea'].ascent
    desc = -f['hhea'].descent
    vb_x, vb_y = -pad, -asc - pad
    vb_w, vb_h = x + gap + d + pad * 2, asc + desc + pad * 2
    letters = ''.join(f'<path id="lettera-{c}" d="{p}"/>' for c, p in paths)
    s = r / 70
    face = ''
    if with_face:
        face = (f'<g id="Faccia" transform="translate({cx - 100 * s:.2f} {cy - 100 * s:.2f}) scale({s:.4f})">'
                + cheeks() + FACES['felice'][1] + '</g>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb_x:.0f} {vb_y:.0f} {vb_w:.0f} {vb_h:.0f}" '
            f'width="{vb_w * 0.6:.0f}" height="{vb_h * 0.6:.0f}">'
            '<title>mingle. – logo</title>'
            f'<g id="Scritta" fill="{text_color}">{letters}</g>'
            f'<g id="Dot"><path transform="translate({cx - 100 * s:.2f} {cy - 100 * s:.2f}) scale({s:.4f})" '
            f'd="{blob_path()}" fill="{MAGENTA}"/>{face}</g></svg>\n')


def main():
    for key in FACES:
        for suffix, body in (('', MAGENTA), ('-bianco', PAPER)):
            with open(os.path.join(HERE, f'dot-{key}{suffix}.svg'), 'w') as fh:
                fh.write(dot_svg(key, body))
    if len(sys.argv) > 1:
        for suffix, col in (('-per-fondo-scuro', PAPER), ('-per-fondo-chiaro', INK)):
            with open(os.path.join(HERE, f'logo-mingle{suffix}.svg'), 'w') as fh:
                fh.write(logo_svg(sys.argv[1], col))
    print('ok')


if __name__ == '__main__':
    main()
