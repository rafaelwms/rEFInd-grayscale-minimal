#!/usr/bin/env python3
"""Gera icons/os_gamepad.png: ícone monocromático (branco, fundo transparente, 320x320) no estilo
dos demais ícones do tema, para consoles/retrogaming (ex.: Recalbox, Batocera, RetroPie).

Só para desenvolvimento (o instalador apenas copia o PNG). Requer Pillow.
Uso: python3 tools/make_icons.py [--force]
Não sobrescreve um os_gamepad.png que já exista (por exemplo, um ícone próprio) sem --force.
"""
import os
import sys
from PIL import Image, ImageDraw

S = 320
SCALE = 4          # supersampling para bordas suaves
W = (255, 255, 255, 255)
T = (0, 0, 0, 0)


def gamepad():
    n = S * SCALE
    im = Image.new("RGBA", (n, n), T)
    d = ImageDraw.Draw(im)
    k = SCALE

    # corpo: barra central + duas empunhaduras arredondadas
    d.rounded_rectangle((52 * k, 112 * k, 268 * k, 196 * k), radius=40 * k, fill=W)
    d.ellipse((38 * k, 126 * k, 128 * k, 252 * k), fill=W)          # empunhadura esquerda
    d.ellipse((192 * k, 126 * k, 282 * k, 252 * k), fill=W)         # empunhadura direita

    # recortes (transparentes): D-pad, botões, start/select
    def cut(shape, *a, **kw):
        getattr(d, shape)(*a, fill=T, **kw)

    # D-pad (cruz)
    cx, cy, arm, th = 96 * k, 160 * k, 26 * k, 11 * k
    cut("rounded_rectangle", (cx - arm, cy - th, cx + arm, cy + th), radius=4 * k)
    cut("rounded_rectangle", (cx - th, cy - arm, cx + th, cy + arm), radius=4 * k)
    # botões de ação (losango de 4 círculos)
    bx, by, r, dd = 226 * k, 160 * k, 10 * k, 24 * k
    for ox, oy in ((0, -dd), (0, dd), (-dd, 0), (dd, 0)):
        cut("ellipse", (bx + ox - r, by + oy - r, bx + ox + r, by + oy + r))
    # select / start
    for px in (146 * k, 174 * k):
        cut("rounded_rectangle", (px - 10 * k, 150 * k, px + 10 * k, 160 * k), radius=5 * k)

    return im.resize((S, S), Image.LANCZOS)


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")
    out = os.path.join(root, "os_gamepad.png")
    if os.path.exists(out) and "--force" not in sys.argv[1:]:
        print("já existe, não sobrescrevi:", os.path.normpath(out), "(use --force para regerar)")
        return 0
    gamepad().save(out, optimize=True)
    print("gerado:", os.path.normpath(out))


if __name__ == "__main__":
    sys.exit(main())
