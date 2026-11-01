#!/usr/bin/env python3
"""Generates the Lodestar icon prototypes (SVG) from CompassTheme's palette.

Run from anywhere:  python3 generate.py
Colours are CompassTheme's (0-1 RGB -> hex). Angles are degrees clockwise from 12 o'clock,
slice 1 centred on 0 deg, nine slices of 40 deg, like RadialLayout.
"""
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))
C = 512  # canvas centre; canvas is 1024

PAPER, PAPER_LIT, PAPER_DEEP, PAPER_EDGE = "#DCCDAA", "#E0D1B1", "#BDA87E", "#877049"
INK, INK_RULE = "#33261A", "#3A2C1A"
VERM, VERM_LIT = "#8F3322", "#B44437"
BRASS_HI, BRASS_LIT, BRASS_MID, BRASS_DARK, BRASS_DEEP = "#D5C08F", "#B39257", "#856637", "#5A4325", "#2F2717"
LEATHER_HI, LEATHER_LO = "#3B2A19", "#17100A"

def pol(r, deg, cx=C, cy=C):
    a = math.radians(deg)
    return cx + r * math.sin(a), cy - r * math.cos(a)

def pt(p): return f"{p[0]:.1f},{p[1]:.1f}"

def sector(r0, r1, a0, a1):
    return (f"M{pt(pol(r0,a0))} L{pt(pol(r1,a0))} A{r1} {r1} 0 0 1 {pt(pol(r1,a1))} "
            f"L{pt(pol(r0,a1))} A{r0} {r0} 0 0 0 {pt(pol(r0,a0))} Z")

def spokes(r0, r1, width, color, opacity=1.0, offset=20):
    d = "".join(f"M{pt(pol(r0,offset+40*k))} L{pt(pol(r1,offset+40*k))} " for k in range(9))
    return f'<path d="{d}" stroke="{color}" stroke-width="{width}" stroke-linecap="round" opacity="{opacity}" fill="none"/>'

def ticks(r_out, step=5, long_every=2, short=14, long=26, card=90, w=2.6, color=INK_RULE):
    d = ""
    for i in range(360 // step):
        deg = i * step
        n = i
        ln = card if deg % 90 == 0 else long if n % long_every == 0 else short
        d += f"M{pt(pol(r_out,deg))} L{pt(pol(r_out-ln,deg))} "
    return f'<path d="{d}" stroke="{color}" stroke-width="{w}" fill="none" opacity=".8"/>'

def needle(theta, length, tail, half, tail_color=(BRASS_DARK, BRASS_DEEP)):
    """Kite needle pointing up, rotated to theta. Vermilion front, dark tail, split into lit/shaded facets."""
    L, T, w = length, tail, half
    return f'''<g transform="rotate({theta} {C} {C})">
      <path d="M{C},{C-L} L{C+w},{C} L{C},{C} Z" fill="{VERM}"/>
      <path d="M{C},{C-L} L{C-w},{C} L{C},{C} Z" fill="{VERM_LIT}"/>
      <path d="M{C},{C+T} L{C+w},{C} L{C},{C} Z" fill="{tail_color[1]}"/>
      <path d="M{C},{C+T} L{C-w},{C} L{C},{C} Z" fill="{tail_color[0]}"/>
      <path d="M{C},{C-L} L{C+w},{C} L{C},{C+T} L{C-w},{C} Z" fill="none" stroke="{BRASS_DEEP}" stroke-opacity=".55" stroke-width="3" stroke-linejoin="round"/>
    </g>'''

def hub(r):
    """A domed brass boss. Lit by gradient alone: a dark centre or a bright dot reads as an eye."""
    return f'''<circle cx="{C}" cy="{C}" r="{r}" fill="url(#hub)" stroke="{BRASS_DEEP}" stroke-width="4"/>
    <circle cx="{C}" cy="{C}" r="{r*0.74:.1f}" fill="none" stroke="{BRASS_DEEP}" stroke-opacity=".45" stroke-width="2.5"/>
    <circle cx="{C}" cy="{C}" r="{r*0.52:.1f}" fill="url(#dome)" stroke="{BRASS_DARK}" stroke-opacity=".8" stroke-width="2.5"/>'''

def defs():
    return f'''<defs>
  <radialGradient id="leather" cx=".35" cy=".25" r="1.0"><stop offset="0" stop-color="{LEATHER_HI}"/><stop offset="1" stop-color="{LEATHER_LO}"/></radialGradient>
  <linearGradient id="brassRing" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="{BRASS_HI}"/><stop offset=".28" stop-color="{BRASS_LIT}"/>
    <stop offset=".6" stop-color="{BRASS_MID}"/><stop offset=".85" stop-color="{BRASS_DARK}"/><stop offset="1" stop-color="{BRASS_MID}"/></linearGradient>
  <linearGradient id="brassRev" x1="1" y1="1" x2="0" y2="0">
    <stop offset="0" stop-color="{BRASS_HI}"/><stop offset=".3" stop-color="{BRASS_LIT}"/>
    <stop offset=".7" stop-color="{BRASS_MID}"/><stop offset="1" stop-color="{BRASS_DARK}"/></linearGradient>
  <linearGradient id="brassBody" x1=".1" y1="0" x2=".9" y2="1">
    <stop offset="0" stop-color="{BRASS_HI}"/><stop offset=".35" stop-color="{BRASS_LIT}"/>
    <stop offset=".75" stop-color="{BRASS_MID}"/><stop offset="1" stop-color="{BRASS_DARK}"/></linearGradient>
  <radialGradient id="card" cx=".42" cy=".38" r=".75">
    <stop offset="0" stop-color="{PAPER_LIT}"/><stop offset=".68" stop-color="{PAPER}"/>
    <stop offset=".93" stop-color="{PAPER_DEEP}"/><stop offset="1" stop-color="{PAPER_EDGE}"/></radialGradient>
  <radialGradient id="hub" cx=".38" cy=".32" r=".8"><stop offset="0" stop-color="{BRASS_HI}"/><stop offset=".5" stop-color="{BRASS_MID}"/><stop offset="1" stop-color="{BRASS_DARK}"/></radialGradient>
  <radialGradient id="dome" cx=".36" cy=".3" r=".85"><stop offset="0" stop-color="{BRASS_HI}"/><stop offset=".45" stop-color="{BRASS_LIT}"/><stop offset="1" stop-color="{BRASS_MID}"/></radialGradient>
  <linearGradient id="gloss" x1="0" y1="0" x2=".7" y2=".8"><stop offset="0" stop-color="#fff" stop-opacity=".20"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="22" stdDeviation="24" flood-color="#000" flood-opacity=".55"/></filter>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="6" stdDeviation="7" flood-color="#000" flood-opacity=".45"/></filter>
</defs>'''

def svg(body, title, canvas=1024):
    clip = '<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="188"/></clipPath>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {canvas} {canvas}" width="{canvas}" height="{canvas}">'
            f'<title>{title}</title>{defs()}{clip}<g clip-path="url(#tile)">{body}</g></svg>\n')

def leather_squircle():
    return (f'<rect x="100" y="100" width="824" height="824" rx="188" fill="url(#leather)"/>'
            f'<rect x="101.5" y="101.5" width="821" height="821" rx="187" fill="none" stroke="#fff" stroke-opacity=".10" stroke-width="3"/>')

def numerals(r, size, aimed):
    out = ""
    for k in range(9):
        x, y = pol(r, 40 * k)
        col = VERM if k == aimed else INK
        out += (f'<text x="{x:.1f}" y="{y+size*0.34:.1f}" text-anchor="middle" font-size="{size}" font-weight="700" '
                f'font-family="Baskerville, \'Baskerville Old Face\', Palatino, Georgia, serif" fill="{col}">{k+1}</text>')
    return out

# ---------- A: faithful ----------
def variant_a():
    aimed = 1  # slice 2 centred at 40 deg
    body = leather_squircle() + f'''
<g filter="url(#drop)">
  <circle cx="{C}" cy="{C}" r="372" fill="url(#brassRing)" stroke="{BRASS_DEEP}" stroke-width="3"/>
  <circle cx="{C}" cy="{C}" r="352" fill="none" stroke="{BRASS_HI}" stroke-opacity=".5" stroke-width="2"/>
  <circle cx="{C}" cy="{C}" r="334" fill="url(#brassRev)" stroke="{BRASS_DEEP}" stroke-width="3"/>
  <circle cx="{C}" cy="{C}" r="316" fill="url(#card)" stroke="{PAPER_EDGE}" stroke-width="3"/>
</g>
{ticks(304)}
<circle cx="{C}" cy="{C}" r="268" fill="none" stroke="{INK_RULE}" stroke-opacity=".6" stroke-width="2.5"/>
<circle cx="{C}" cy="{C}" r="118" fill="none" stroke="{INK_RULE}" stroke-opacity=".6" stroke-width="2.5"/>
<path d="{sector(118,268,20,60)}" fill="{VERM}" fill-opacity=".17"/>
{spokes(118,268,3,INK_RULE,.7)}
{numerals(224,60,aimed)}
<circle cx="{C}" cy="{C}" r="316" fill="url(#gloss)"/>
<g filter="url(#soft)">{needle(40,176,170,36)}{hub(50)}</g>
'''
    return svg(body, "Lodestar A - faithful compass")

# ---------- B: bold (survives 32px) ----------
def variant_b():
    body = leather_squircle() + f'''
<g filter="url(#drop)">
  <circle cx="{C}" cy="{C}" r="392" fill="url(#brassRing)" stroke="{BRASS_DEEP}" stroke-width="4"/>
  <circle cx="{C}" cy="{C}" r="352" fill="url(#brassRev)" stroke="{BRASS_DEEP}" stroke-width="4"/>
  <circle cx="{C}" cy="{C}" r="332" fill="url(#card)" stroke="{PAPER_EDGE}" stroke-width="4"/>
</g>
<path d="{sector(0,332,20,60)}" fill="{VERM}" fill-opacity=".22"/>
{spokes(90,320,10,INK_RULE,.55)}
<circle cx="{C}" cy="{C}" r="332" fill="url(#gloss)"/>
<g filter="url(#soft)">{needle(40,300,200,58)}{hub(68)}</g>
'''
    return svg(body, "Lodestar B - bold")

# ---------- C: lodestar (sight vanes) ----------
def vane(dist, deg, slit):
    """A sight vane: a small brass post across the bar at `dist` from the centre, with a slit (far) or hairline (near)."""
    x, y = pol(dist, deg)
    inner = (f'<rect x="-3.5" y="-24" width="7" height="48" rx="3" fill="{BRASS_DEEP}"/>' if slit else
             f'<rect x="-1.5" y="-24" width="3" height="48" fill="{VERM_LIT}"/>')
    return f'''<g transform="translate({x:.1f} {y:.1f}) rotate({deg})">
      <rect x="-52" y="-30" width="104" height="60" rx="14" fill="url(#brassBody)" stroke="{BRASS_DEEP}" stroke-width="4"/>
      <rect x="-40" y="-24" width="80" height="14" rx="6" fill="{BRASS_HI}" opacity=".35"/>
      {inner}
    </g>'''

def variant_c():
    th = 40
    bar = f'''<g transform="rotate({th} {C} {C})">
      <rect x="{C-14}" y="{C-300}" width="28" height="600" rx="10" fill="url(#brassBody)" stroke="{BRASS_DEEP}" stroke-width="4"/>
      <rect x="{C-6}" y="{C-290}" width="6" height="580" rx="3" fill="{BRASS_HI}" opacity=".45"/>
    </g>'''
    body = leather_squircle() + f'''
<g filter="url(#drop)">
  <circle cx="{C}" cy="{C}" r="384" fill="url(#brassRing)" stroke="{BRASS_DEEP}" stroke-width="3"/>
  <circle cx="{C}" cy="{C}" r="338" fill="url(#brassRev)" stroke="{BRASS_DEEP}" stroke-width="3"/>
  <circle cx="{C}" cy="{C}" r="320" fill="url(#card)" stroke="{PAPER_EDGE}" stroke-width="3"/>
</g>
{ticks(372,step=5,long_every=2,short=12,long=22,card=34,w=3,color=BRASS_DEEP)}
<path d="{sector(60,300,20,60)}" fill="{VERM}" fill-opacity=".17"/>
{spokes(60,300,3.5,INK_RULE,.65)}
<circle cx="{C}" cy="{C}" r="300" fill="none" stroke="{INK_RULE}" stroke-opacity=".5" stroke-width="2.5"/>
<circle cx="{C}" cy="{C}" r="320" fill="url(#gloss)"/>
<g filter="url(#soft)">
  {bar}
  <g transform="rotate({th} {C} {C})">
    <path d="M{C},{C-250} L{C+30},{C} L{C-30},{C} Z" fill="{VERM}"/>
    <path d="M{C},{C-250} L{C-30},{C} L{C},{C} Z" fill="{VERM_LIT}"/>
  </g>
  {vane(292, th+180, True)}{vane(292, th, False)}
  {hub(46)}
</g>
'''
    return svg(body, "Lodestar C - sight vanes")

# ---------- D: brass squircle ----------
def variant_d():
    body = f'''
<rect x="100" y="100" width="824" height="824" rx="188" fill="url(#brassBody)"/>
<rect x="104" y="104" width="816" height="816" rx="184" fill="none" stroke="{BRASS_HI}" stroke-opacity=".6" stroke-width="4"/>
<rect x="100" y="100" width="824" height="824" rx="188" fill="none" stroke="{BRASS_DEEP}" stroke-opacity=".7" stroke-width="3"/>
<circle cx="{C}" cy="{C+4}" r="352" fill="none" stroke="{BRASS_HI}" stroke-opacity=".55" stroke-width="6"/>
<circle cx="{C}" cy="{C}" r="352" fill="{BRASS_DEEP}" fill-opacity=".55"/>
<g filter="url(#soft)"><circle cx="{C}" cy="{C}" r="332" fill="url(#card)" stroke="{PAPER_EDGE}" stroke-width="4"/></g>
{ticks(318,step=5,long_every=2,short=12,long=22,card=38,w=3)}
<path d="{sector(100,280,20,60)}" fill="{VERM}" fill-opacity=".2"/>
{spokes(100,276,5,INK_RULE,.6)}
<circle cx="{C}" cy="{C}" r="332" fill="url(#gloss)"/>
<g filter="url(#soft)">{needle(40,290,190,48,tail_color=('#8A7149','#5E4A2D'))}{hub(58)}</g>
'''
    return svg(body, "Lodestar D - brass tile")

# ---------- E: menu-bar template glyphs (black + alpha only) ----------
def menubar(kind):
    c = 32
    def p(r, d): return pol(r, d, c, c)
    ring = '<circle cx="32" cy="32" r="27" fill="none" stroke="#000" stroke-width="4.5"/>'
    # needle: kite pointing 40 deg, solid
    tip, tl = p(21, 40), p(14, 220)
    l, r_ = p(5.5, 40-90), p(5.5, 40+90)
    needle_ = f'<path d="M{pt(tip)} L{pt(r_)} L{pt(tl)} L{pt(l)} Z" fill="#000"/>'
    if kind == "a":
        tk = "".join(f"M{pt(p(21.5,20+40*k))} L{pt(p(15.5,20+40*k))} " for k in range(9))
        extra = f'<path d="{tk}" stroke="#000" stroke-width="2" stroke-linecap="round" fill="none"/>'
        needle_ = f'<path d="M{pt(p(15,40))} L{pt(p(4.5,130))} L{pt(p(10,220))} L{pt(p(4.5,310))} Z" fill="#000"/>'
        title = "Lodestar menu bar A - ring, nine marks, needle"
    else:
        # nine arcs, one per slice, with gaps on the slice boundaries
        arcs = ""
        for k in range(9):
            a0, a1 = 40*k - 20 + 6, 40*k + 20 - 6
            arcs += f"M{pt(p(27,a0))} A27 27 0 0 1 {pt(p(27,a1))} "
        ring = f'<path d="{arcs}" fill="none" stroke="#000" stroke-width="5" stroke-linecap="butt"/>'
        extra = ""
        title = "Lodestar menu bar B - nine arcs and needle"
        needle_ = f'<path d="M{pt(p(19,40))} L{pt(p(6.5,130))} L{pt(p(12,220))} L{pt(p(6.5,310))} Z" fill="#000"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64"><title>{title}</title>'
            f'{ring}{extra}{needle_}</svg>\n')

files = {
    "lodestar-a-faithful.svg": variant_a(),
    "lodestar-b-bold.svg": variant_b(),
    "lodestar-c-sight-vanes.svg": variant_c(),
    "lodestar-d-brass-tile.svg": variant_d(),
    "menubar-a.svg": menubar("a"),
    "menubar-b.svg": menubar("b"),
}
for name, content in files.items():
    with open(os.path.join(OUT, name), "w") as f: f.write(content)
print("wrote", ", ".join(files))
