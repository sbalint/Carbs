"""Draws the Carbs app icon: a blue C holding a slice of chocolate cake.

Run: python3 design/make_icon.py  (writes Carbs/Assets.xcassets/AppIcon.appiconset/AppIcon.png)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # drawn at 2x, scaled to 1024 for smooth edges
OUT = os.path.join(os.path.dirname(__file__), "..", "Carbs", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, top, bottom):
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(size[1]):
        d.line([(0, y), (size[0], y)], fill=lerp(top, bottom, y / (size[1] - 1)))
    return img


# Background: Carbs navy.
icon = vertical_gradient((S, S), (0x24, 0x31, 0x52), (0x12, 0x18, 0x2C))

# --- The C: a thick ring with an opening on the right and rounded ends ---
cx, cy = S // 2, S // 2
r_out, r_in = 800, 500
gap = 42  # degrees either side of 3 o'clock
mask = Image.new("L", (S, S), 0)
m = ImageDraw.Draw(mask)
m.pieslice([cx - r_out, cy - r_out, cx + r_out, cy + r_out], start=gap, end=360 - gap, fill=255)
m.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=0)
r_mid, r_cap = (r_out + r_in) / 2, (r_out - r_in) / 2
for a in (gap, -gap):
    x = cx + r_mid * math.cos(math.radians(a))
    y = cy + r_mid * math.sin(math.radians(a))
    m.ellipse([x - r_cap, y - r_cap, x + r_cap, y + r_cap], fill=255)

c_fill = vertical_gradient((S, S), (0x6A, 0xB8, 0xF5), (0x2E, 0x7F, 0xD0))
shadow = mask.filter(ImageFilter.GaussianBlur(30))
icon.paste((0x08, 0x0C, 0x18), (0, 24), shadow.point(lambda v: int(v * 0.55)))
icon.paste(c_fill, (0, 0), mask)

# --- Chocolate cake slice inside the C (three-quarter view, tip on the left) ---
layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)

sponge = (0x5A, 0x31, 0x1C, 255)
sponge_side = (0x46, 0x25, 0x14, 255)
cream = (0xF4, 0xDF, 0xC1, 255)
cream_side = (0xD9, 0xC1, 0xA0, 255)
ganache = (0x33, 0x19, 0x0D, 255)
ganache_top = (0x4A, 0x26, 0x14, 255)

T = (600, 1300)          # tip
A = (1290, 830)          # front face, top of the back edge
B = (1290, 1300)         # front face, bottom of the back edge
off = (150, -95)         # depth of the slice
A2 = (A[0] + off[0], A[1] + off[1])
B2 = (B[0] + off[0], B[1] + off[1])
T2 = (T[0] + off[0], T[1] + off[1])

# Plate.
d.ellipse([470, 1235, 1610, 1395], fill=(0xC9, 0xD3, 0xE3, 255))
d.ellipse([500, 1225, 1580, 1365], fill=(0xFF, 0xFF, 0xFF, 255))

def striped(polygon, base, band, bands):
    """Fill a face with sponge and horizontal cream bands, clipped to the polygon."""
    face = Image.new("RGBA", (S, S), base)
    fd = ImageDraw.Draw(face)
    for top, bottom in bands:
        fd.polygon([(0, top[0]), (S, top[1]), (S, bottom[1]), (0, bottom[0])], fill=band)
    clip = Image.new("L", (S, S), 0)
    ImageDraw.Draw(clip).polygon(polygon, fill=255)
    layer.paste(face, (0, 0), clip)

# Cream bands as (y at x=0, y at x=S) pairs, so the side face can slope with the depth.
front_bands = [((1150, 1150), (1185, 1185)), ((1000, 1000), (1035, 1035))]
slope = off[1] / off[0]
side_bands = [((y0 - slope * B[0], y0 + slope * (S - B[0])), (y1 - slope * B[0], y1 + slope * (S - B[0])))
              for (y0, _), (y1, _) in front_bands]

striped([A, B, B2, A2], sponge_side, cream_side, side_bands)   # back side face
striped([T, A, B], sponge, cream, front_bands)                   # front face
d = ImageDraw.Draw(layer)
d.polygon([T, A, A2, T2], fill=ganache_top)                      # frosted top
d.line([T, A], fill=ganache, width=34)
d.line([A, A2], fill=ganache, width=20)

# Drips hanging from the front top edge.
for frac, length in [(0.30, 70), (0.52, 120), (0.74, 85), (0.93, 60)]:
    x = T[0] + (A[0] - T[0]) * frac
    y = T[1] + (A[1] - T[1]) * frac
    w = 30
    d.rectangle([x - w, y, x + w, y + length], fill=ganache)
    d.ellipse([x - w, y + length - w, x + w, y + length + w], fill=ganache)

# Cherry on the frosted top, near the back.
ch_x, ch_y, ch_r = (A[0] + A2[0]) / 2 - 20, (A[1] + A2[1]) / 2 - 62, 74
d.line([(ch_x + 12, ch_y - ch_r + 12), (ch_x + 80, ch_y - ch_r - 95)], fill=(0x3E, 0x7D, 0x2E, 255), width=16)
d.ellipse([ch_x - ch_r, ch_y - ch_r, ch_x + ch_r, ch_y + ch_r], fill=(0xE2, 0x2B, 0x3A, 255))
d.ellipse([ch_x - 42, ch_y - 46, ch_x - 10, ch_y - 14], fill=(255, 255, 255, 200))

cake_shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(24))
icon.paste((0x08, 0x0C, 0x18), (0, 18), cake_shadow.point(lambda v: int(v * 0.45)))
icon.paste(layer, (0, 0), layer)

icon = icon.resize((1024, 1024), Image.LANCZOS).convert("RGB")  # App Store icons must be opaque
icon.save(OUT)
print("wrote", os.path.abspath(OUT))
