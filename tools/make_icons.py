#!/usr/bin/env python3
"""Gera icons/os_gamepad.png e icons/os_tails.png (brancos, fundo transparente, 320x320) no estilo
dos demais ícones do tema (consoles/retrogaming e sistemas de privacidade), e icons-black/ com todos os ícones em preto.

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


def tails():
    """Ícone genérico de privacidade (chapéu + óculos), desenho próprio: não usa o logotipo do Tails."""
    n = S * SCALE
    im = Image.new("RGBA", (n, n), T)
    d = ImageDraw.Draw(im)
    k = SCALE

    # chapéu: aba larga + copa
    d.rounded_rectangle((40 * k, 150 * k, 280 * k, 176 * k), radius=13 * k, fill=W)
    d.rounded_rectangle((90 * k, 56 * k, 230 * k, 160 * k), radius=22 * k, fill=W)
    # faixa do chapéu (recorte)
    d.rectangle((90 * k, 126 * k, 230 * k, 138 * k), fill=T)
    # óculos: duas lentes e a ponte
    for cx in (110 * k, 210 * k):
        d.ellipse((cx - 38 * k, 196 * k, cx + 38 * k, 266 * k), fill=W)
        d.ellipse((cx - 24 * k, 208 * k, cx + 24 * k, 254 * k), fill=T)
    d.rounded_rectangle((140 * k, 222 * k, 180 * k, 236 * k), radius=7 * k, fill=W)

    return im.resize((S, S), Image.LANCZOS)


def make_black(icons_dir, out_dir):
    """Cópia de cada ícone em preto puro, preservando o alfa (para fundos claros).
    Os quadros de seleção (selection_*.png) ficam de fora: são translúcidos e não são ícones."""
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    for name in sorted(os.listdir(icons_dir)):
        if not name.endswith(".png") or name.startswith("selection_"):
            continue
        src = Image.open(os.path.join(icons_dir, name)).convert("RGBA")
        black = Image.new("RGBA", src.size, (0, 0, 0, 0))
        black.putalpha(src.getchannel("A"))
        black.save(os.path.join(out_dir, name), optimize=True)
        count += 1
    return count


def main():
    force = "--force" in sys.argv[1:]
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons"))
    for name, fn in (("os_gamepad.png", gamepad), ("os_tails.png", tails)):
        out = os.path.join(root, name)
        if os.path.exists(out) and not force:
            print("já existe, não sobrescrevi:", out, "(use --force para regerar)")
            continue
        fn().save(out, optimize=True)
        print("gerado:", out)
    # versão preta de todos os ícones (sempre regerada a partir de icons/)
    out_dir = os.path.normpath(os.path.join(root, "..", "icons-black"))
    print(f"{make_black(root, out_dir)} ícones pretos em {out_dir}")


if __name__ == "__main__":
    sys.exit(main())
