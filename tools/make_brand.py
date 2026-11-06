"""Genera el logo de Dreamer's Space World (ícono y pantalla de arranque) con Pillow.

    python tools/make_brand.py

Escribe en assets/brand/: icon.png (256), icon_1024.png, icon.ico (16-256) y splash.png.
El dibujo: un faro sobre una roca, con su haz, bajo una luna creciente y la órbita de un
planeta; noche azul profunda. Se dibuja a 4x y se reduce para que los bordes salgan suaves.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "brand")
S = 1024 * 4  # lienzo de trabajo (luego se reduce)

NIGHT_TOP = (16, 22, 52)
NIGHT_BOTTOM = (40, 30, 82)
GOLD = (255, 201, 120)
CREAM = (240, 232, 214)
RED = (196, 70, 64)
ROCK = (22, 26, 44)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def draw_icon(size=S):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):  # cielo en degradado
        d.line([(0, y), (size, y)], fill=lerp(NIGHT_TOP, NIGHT_BOTTOM, y / size))
    u = size / 1024.0

    # Estrellas
    import random
    rnd = random.Random(7)
    for _ in range(70):
        x, y = rnd.uniform(60, 964) * u, rnd.uniform(60, 560) * u
        r = rnd.uniform(1.5, 4.0) * u
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, rnd.randint(110, 230)))

    # Órbita (elipse inclinada) alrededor de la luna
    orbit = Image.new("RGBA", (size, size))
    od = ImageDraw.Draw(orbit)
    od.ellipse((150 * u, 250 * u, 870 * u, 470 * u), outline=(150, 180, 255, 150), width=int(10 * u))
    orbit = orbit.rotate(-14, center=(510 * u, 360 * u), resample=Image.BICUBIC)
    img.alpha_composite(orbit)

    # Luna creciente (un círculo menos otro desplazado)
    moon = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(moon)
    cx, cy, r = 640 * u, 300 * u, 150 * u
    md.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    md.ellipse((cx - r + 70 * u, cy - r - 30 * u, cx + r + 70 * u, cy + r - 30 * u), fill=0)
    glow = moon.filter(ImageFilter.GaussianBlur(28 * u))
    img.paste(Image.new("RGBA", (size, size), GOLD + (255,)), (0, 0), glow.point(lambda p: p * 0.55))
    img.paste(Image.new("RGBA", (size, size), (255, 236, 196, 255)), (0, 0), moon)

    # Planeta pequeño sobre la órbita
    px, py, pr = 230 * u, 420 * u, 38 * u
    d.ellipse((px - pr, py - pr, px + pr, py + pr), fill=(120, 170, 255))

    # Haz del faro (triángulo translúcido hacia la izquierda)
    beam = Image.new("RGBA", (size, size))
    bd = ImageDraw.Draw(beam)
    lamp = (512 * u, 560 * u)
    bd.polygon([lamp, (40 * u, 470 * u), (40 * u, 640 * u)], fill=(255, 226, 170, 150))
    beam = beam.filter(ImageFilter.GaussianBlur(10 * u))
    img.alpha_composite(beam)

    # Roca y mar
    d.ellipse((180 * u, 860 * u, 850 * u, 1180 * u), fill=ROCK)
    d.rectangle((0, 930 * u, size, size), fill=(18, 30, 70))
    for i in range(3):  # olas
        y = (955 + i * 30) * u
        d.arc((60 * u, y - 20 * u, 300 * u, y + 20 * u), 200, 340, fill=(90, 130, 200), width=int(6 * u))
        d.arc((700 * u, y - 20 * u, 960 * u, y + 20 * u), 200, 340, fill=(90, 130, 200), width=int(6 * u))

    # Faro: torre troncocónica a franjas, galería y linterna
    top_w, bot_w, top_y, bot_y = 96 * u, 170 * u, 620 * u, 900 * u
    tower = [(512 * u - top_w / 2, top_y), (512 * u + top_w / 2, top_y), (512 * u + bot_w / 2, bot_y), (512 * u - bot_w / 2, bot_y)]
    d.polygon(tower, fill=CREAM)
    for k in range(2):  # franjas rojas
        y0 = top_y + (60 + k * 110) * u
        y1 = y0 + 50 * u
        w0 = top_w + (bot_w - top_w) * (y0 - top_y) / (bot_y - top_y)
        w1 = top_w + (bot_w - top_w) * (y1 - top_y) / (bot_y - top_y)
        d.polygon([(512 * u - w0 / 2, y0), (512 * u + w0 / 2, y0), (512 * u + w1 / 2, y1), (512 * u - w1 / 2, y1)], fill=RED)
    d.rectangle((512 * u - 70 * u, 596 * u, 512 * u + 70 * u, 622 * u), fill=(44, 44, 60))       # galería
    d.rectangle((512 * u - 40 * u, 530 * u, 512 * u + 40 * u, 598 * u), fill=GOLD)               # linterna encendida
    d.polygon([(512 * u - 52 * u, 532 * u), (512 * u + 52 * u, 532 * u), (512 * u, 478 * u)], fill=RED)  # cúpula
    d.rectangle((512 * u - 20 * u, 830 * u, 512 * u + 20 * u, 900 * u), fill=(60, 50, 50))       # puerta (una sola)
    halo = Image.new("L", (size, size), 0)
    ImageDraw.Draw(halo).ellipse((512 * u - 90 * u, 480 * u, 512 * u + 90 * u, 650 * u), fill=200)
    img.paste(Image.new("RGBA", (size, size), GOLD + (255,)), (0, 0), halo.filter(ImageFilter.GaussianBlur(40 * u)).point(lambda p: p * 0.5))
    d.rectangle((512 * u - 40 * u, 530 * u, 512 * u + 40 * u, 598 * u), fill=(255, 226, 160))

    # Esquinas redondeadas (como los íconos de las apps)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), rounded_mask(size, int(180 * u)))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    big = draw_icon()
    icon1024 = big.resize((1024, 1024), Image.LANCZOS)
    icon1024.save(os.path.join(OUT, "icon_1024.png"))
    icon1024.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
    icon1024.save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Pantalla de arranque: el logo centrado sobre la noche, con el nombre debajo
    w, h = 1280, 720
    splash = Image.new("RGBA", (w, h))
    sd = ImageDraw.Draw(splash)
    for y in range(h):
        sd.line([(0, y), (w, y)], fill=lerp((8, 11, 28), (24, 18, 50), y / h))
    logo = icon1024.resize((300, 300), Image.LANCZOS)
    splash.alpha_composite(logo, ((w - 300) // 2, 150))
    try:
        font = ImageFont.truetype("seguisb.ttf", 46)
    except OSError:
        font = ImageFont.load_default()
    text = "Dreamer's Space World"
    tw = sd.textlength(text, font=font)
    sd.text(((w - tw) / 2, 485), text, font=font, fill=CREAM)
    splash.convert("RGB").save(os.path.join(OUT, "splash.png"))
    print("Listo:", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
