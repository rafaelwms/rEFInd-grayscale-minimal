#!/usr/bin/env python3
"""Prepara uma imagem do usuário como fundo do tema: recorta para 16:9 (centro), ajusta à resolução
escolhida, tira o canal alpha, opcionalmente converte para cinza e limita os canais a [4,251].
(O limite evita pixels coloridos: o rEFInd estoura valores quase pretos/brancos ao reescalar.)

Uso: python3 tools/make_background.py ENTRADA SAÍDA.png LARGURAxALTURA [--color]
Saída sempre em PNG (JPEG como fundo já causou tela preta no boot). Requer Pillow.
"""
import sys
from PIL import Image, ImageOps

LO, HI = 4, 251


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    color = "--color" in argv
    if len(args) != 3:
        print(__doc__)
        return 2
    src, dst, res = args
    try:
        w, h = (int(x) for x in res.lower().split("x"))
    except ValueError:
        print("resolução inválida:", res)
        return 2

    im = ImageOps.exif_transpose(Image.open(src))
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        base = Image.new("RGBA", im.size, (0, 0, 0, 255))
        im = Image.alpha_composite(base, im)
    im = im.convert("RGB")
    sw, sh = im.size

    # recorte central na proporção do destino
    want = w / h
    if sw / sh > want:
        nw = round(sh * want)
        box = ((sw - nw) // 2, 0, (sw - nw) // 2 + nw, sh)
    else:
        nh = round(sw / want)
        box = (0, (sh - nh) // 2, sw, (sh - nh) // 2 + nh)
    im = im.crop(box)
    if im.size[0] < w or im.size[1] < h:
        print(f"aviso: a imagem ({im.size[0]}x{im.size[1]} após o recorte) é menor que {w}x{h}; será ampliada.")
    im = im.resize((w, h), Image.LANCZOS)

    if not color:
        im = ImageOps.grayscale(im).convert("RGB")
    im = im.point(lambda v: min(max(v, LO), HI))
    im.save(dst, "PNG", optimize=True)
    print(f"gerado: {dst} ({w}x{h}, {'cores' if color else 'cinza'})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
