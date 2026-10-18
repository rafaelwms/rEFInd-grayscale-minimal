#!/usr/bin/env python3
"""Gera fonts/<resolução da TELA>/font.png: texto Bold que o rEFInd desenha BRANCO com contorno PRETO.

ATENÇÃO (descoberto via F10): em fundo escuro o rEFInd INVERTE as cores do glifo (as fontes do pacote são
pretas e o texto sai branco). Por isso o PNG é entregue com a polaridade oposta: miolo PRETO e contorno
BRANCO, que na tela aparece como miolo branco com contorno preto. Em fundo claro não há inversão e o
texto sai preto com contorno branco (também legível).

O rEFInd desenha texto a partir de uma imagem de glifos (PNG RGBA, uma linha com 96 células:
ASCII 32-126 + 1 glifo de fallback, monoespaçada). Ele usa a cor do glifo (com a inversão acima).
O tamanho é em pixels da tela, então a fonte deve acompanhar a resolução do MONITOR, e não a do fundo.

Só para desenvolvimento (o instalador apenas copia os PNGs). Requer Pillow e a fonte Ubuntu Mono.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TTF = "/usr/share/fonts/truetype/ubuntu/UbuntuMono[wght].ttf"
# resolução da tela -> (tamanho em px, espessura do contorno em px)   (~1,9% da altura da tela)
PLAN = {
    "1280x720":  (16, 1),
    "1920x1080": (22, 1),
    "2560x1440": (30, 2),
    "3840x2160": (40, 2),
}
WEIGHT = 700   # Bold (eixo wght do Ubuntu Mono variável)
CELLS = 96


def build(size, r):
    font = ImageFont.truetype(TTF, size)
    font.set_variation_by_axes([WEIGHT])
    ascent, descent = font.getmetrics()
    cw = round(font.getlength("M"))
    px, py = r, r                     # folga para o contorno
    ow, oh = cw + 2 * px, ascent + descent + 2 * py
    out = Image.new("RGBA", (ow * CELLS, oh), (0, 0, 0, 0))
    for i in range(CELLS):
        ch = chr(32 + i) if i < 95 else "?"      # célula 96 = glifo de fallback
        cell = Image.new("L", (ow, oh), 0)
        ImageDraw.Draw(cell).text((px, py + ascent), ch, font=font, fill=255, anchor="ls")
        outline = cell.filter(ImageFilter.MaxFilter(2 * r + 1))
        black = Image.merge("RGBA", (Image.new("L", cell.size, 0),) * 3 + (outline,))
        white = Image.merge("RGBA", (Image.new("L", cell.size, 255),) * 3 + (cell,))
        black.alpha_composite(white)
        out.paste(black, (i * ow, 0))
    return out, (ow, oh)


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fonts")
    for res, (size, r) in PLAN.items():
        img, cell = build(size, r)
        d = os.path.join(root, res)
        os.makedirs(d, exist_ok=True)
        img.save(os.path.join(d, "font.png"), optimize=True)
        print(f"{res}: Ubuntu Mono Bold {size}px, contorno {r}px, célula {cell[0]}x{cell[1]}, imagem {img.size}")


if __name__ == "__main__":
    sys.exit(main())
