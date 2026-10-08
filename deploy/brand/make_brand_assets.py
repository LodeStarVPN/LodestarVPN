# Lodestar brand assets. Run: python deploy/brand/make_brand_assets.py
# [desktop] [android] (both without arguments; needs Pillow + numpy). Writes
# the app/installer icons, the start-page logo, tray icons, the star sprites
# used by the connect animation and the Android launcher icon.
#
# The mark: a round night sky; the guiding star (a point of light with
# diffraction rays, the north ray longest) in the upper right third; a route
# entering from beyond the lower-left edge, through three relay nodes that
# brighten towards the star, thinning and dissolving into its light.
# Everything is computed as light fields (numpy), so edges and falloff are
# clean at every size; 16–32 px get only the star, with bolder rays.
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMG = os.path.join(ROOT, "client", "images")
CFG = os.path.join(ROOT, "deploy", "installer", "config")
SS = 3

TOP = np.array([10, 16, 48], np.float32)
BOTTOM = np.array([4, 6, 20], np.float32)
SKY_LIGHT = np.array([34, 62, 170], np.float32)
STAR_TINT = np.array([150, 185, 255], np.float32)
WHITE = np.array([255, 255, 255], np.float32)
ROUTE = np.array([140, 172, 255], np.float32)
ACCENT = (39, 87, 255)
STAR = (0.635, 0.335)
STAR_R = 0.40


def grid(s):
    y, x = np.mgrid[0:s, 0:s].astype(np.float32)
    return (x + 0.5) / s, (y + 0.5) / s


def gauss(d2, sigma):
    return np.exp(-d2 / (2 * sigma * sigma))


def circle_alpha(s, r=0.48):
    x, y = grid(s)
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) / r
    return np.clip((1 - d) / (1.5 / s / r) + 0.5, 0, 1), d


def star_light(s, cx, cy, R, detail=True, ray_w=1.0, ray_gain=1.0, taper=1.0, xy=None):
    """(core, glow) intensity fields of a bright star at (cx, cy).
    taper < 1 keeps the rays bright further out."""
    x, y = grid(s) if xy is None else xy
    dx, dy = x - cx, y - cy
    d2 = dx * dx + dy * dy
    core = gauss(d2, R * 0.062) + gauss(d2, R * 0.13) * 0.5

    def spike(ax, ay, length, width, power):
        along = dx * ax + dy * ay
        across = -dx * ay + dy * ax
        t = np.clip(np.abs(along) / length, 0, 1)
        w = width * (0.25 + 0.75 * (1 - t))
        return gauss(across * across, w) * (1 - t) ** (power * taper) * (np.abs(along) < length)

    rays = spike(0, 1, R * 1.08, R * 0.020 * ray_w, 1.5) * (dy < 0)          # north: longest
    rays += spike(0, 1, R * 0.78, R * 0.022 * ray_w, 1.8) * (dy >= 0)
    rays += spike(1, 0, R * 0.62, R * 0.020 * ray_w, 1.9)
    if detail:
        k = math.sqrt(0.5)
        rays += spike(k, k, R * 0.30, R * 0.012, 2.2) * 0.55
        rays += spike(k, -k, R * 0.30, R * 0.012, 2.2) * 0.55
    glow = gauss(d2, R * 0.30) * 0.55 + gauss(d2, R * 0.65) * 0.16
    return np.clip(core + rays * 0.95 * ray_gain, 0, 1.6), glow


def node_light(s, cx, cy, r, strength=1.0, xy=None):
    x, y = grid(s) if xy is None else xy
    d2 = (x - cx) ** 2 + (y - cy) ** 2
    return (gauss(d2, r * 0.45) + gauss(d2, r * 1.6) * 0.25) * strength


def bezier(p0, p1, p2, p3, n=400):
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def route_field(s, pts, width, xy=None):
    """Stroke that fades in, thins towards its end and dissolves before it.
    s: the pixels per unit (the edge is 1.2 px soft)."""
    x, y = grid(s) if xy is None else xy
    field = np.zeros_like(x)
    n = len(pts)
    P = np.array(pts, np.float32)
    step = 6
    for i in range(0, n - 1, step):
        a, b = P[i], P[min(i + step, n - 1)]
        ab = b - a
        L2 = float(ab @ ab) or 1e-9
        t = np.clip(((x - a[0]) * ab[0] + (y - a[1]) * ab[1]) / L2, 0, 1)
        dist = np.sqrt((x - a[0] - t * ab[0]) ** 2 + (y - a[1] - t * ab[1]) ** 2)
        k = (i + step / 2) / (n - 1)
        bright = min(1.0, 0.25 + 1.1 * k) * (1 - max(0.0, (k - 0.86) / 0.14)) ** 1.5
        w = width * (1 - 0.55 * k ** 2)
        field = np.maximum(field, np.clip((w / 2 - dist) / (1.2 / s) + 0.5, 0, 1) * bright)
    return field


def mark(size, mode="color", small=None):
    """The round app mark. mode: color | gray (disconnected) | error.
    small: only the centred star (default for 32 px and below)."""
    s = size * SS
    x, y = grid(s)
    small = size <= 32 if small is None else small
    t = np.clip(y * 0.9 + (1 - x) * 0.1, 0, 1)[..., None]
    rgb = TOP * (1 - t) + BOTTOM * t
    sx, sy = (STAR if not small else (0.5, 0.5))
    pool = gauss((x - sx) ** 2 + (y - sy) ** 2, 0.24)[..., None]
    rgb = rgb * (1 - pool * 0.55) + SKY_LIGHT * pool * 0.55
    vig = np.clip(((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.5, 0, 1)[..., None]
    rgb = rgb * (1 - vig * 0.35)

    if not small:
        r = np.random.default_rng(19)
        dust = np.zeros_like(x)
        for _ in range(38):
            px, py = r.random(), r.random()
            if (px - STAR[0]) ** 2 + (py - STAR[1]) ** 2 < 0.05:
                continue
            dust += node_light(s, px, py, 0.004 + 0.004 * r.random(), 0.25 + 0.45 * r.random())
        rgb = rgb + WHITE * np.clip(dust, 0, 1)[..., None] * 0.55
        pts = bezier((-0.04, 1.02), (0.20, 0.66), (0.38, 0.44), (STAR[0] - 0.02, STAR[1] + 0.035))
        route = route_field(s, pts, 0.010 if size >= 128 else 0.016)[..., None]
        rgb = rgb * (1 - route * 0.9) + ROUTE * route * 0.9
        nodes = np.zeros_like(x)
        for k, strength in ((0.30, 0.55), (0.52, 0.75), (0.72, 0.95)):
            px, py = pts[int(k * (len(pts) - 1))]
            nodes += node_light(s, px, py, 0.016 if size >= 64 else 0.022, strength)
        rgb = rgb + WHITE * np.clip(nodes, 0, 1.2)[..., None] * 0.9

    core, glow = star_light(s, sx, sy, STAR_R if not small else 0.66, detail=not small, ray_w=1.0 if not small else 3.2)
    tint = STAR_TINT if mode != "error" else np.array([255, 90, 90], np.float32)
    rgb = rgb + tint * glow[..., None] * (0.55 if mode != "error" else 0.9)
    c = np.clip(core, 0, 1)[..., None]
    rgb = rgb * (1 - c) + (WHITE if mode != "error" else np.array([255, 120, 120], np.float32)) * c

    alpha, d = circle_alpha(s)
    # hairline rim: bright along the top (glass edge), faint all round so the
    # circle still reads on a black background
    rim = np.clip(1 - np.abs(d - 0.985) / 0.012, 0, 1) * (0.09 + np.clip(1.2 - y * 1.6, 0, 1) * 0.30)
    rgb = rgb * (1 - rim[..., None]) + ROUTE * rim[..., None]
    if mode == "gray":
        lum = (rgb @ np.array([0.30, 0.59, 0.11], np.float32))[..., None]
        rgb = np.repeat(lum * 0.85 + 12, 3, axis=2)
    rgb = rgb + np.random.default_rng(5).uniform(-0.5, 0.5, rgb.shape)   # dither
    rgba = np.dstack([np.clip(rgb + 0.5, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").resize((size, size), Image.LANCZOS)


def scene(w, h, ox, oy, unit, dust=38):
    """The mark's night sky without its circle, on a w x h canvas: the mark's
    unit square sits at (ox, oy) with a side of `unit` px, and the sky, its
    dust, the route and the star carry on to the canvas edges. For a picture
    the system shapes itself (Android's adaptive icon)."""
    W, H, U = w * SS, h * SS, unit * SS
    py, px = np.mgrid[0:H, 0:W].astype(np.float32)
    x = (px + 0.5 - ox * SS) / U
    y = (py + 0.5 - oy * SS) / U
    xy = (x, y)
    t = np.clip(y * 0.9 + (1 - x) * 0.1, 0, 1)[..., None]
    rgb = TOP * (1 - t) + BOTTOM * t
    pool = gauss((x - STAR[0]) ** 2 + (y - STAR[1]) ** 2, 0.24)[..., None]
    rgb = rgb * (1 - pool * 0.55) + SKY_LIGHT * pool * 0.55
    vig = np.clip(((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.5, 0, 1)[..., None]
    rgb = rgb * (1 - vig * 0.35)

    # dust over the whole canvas, as dense as in the mark
    x0, x1, y0, y1 = float(x.min()), float(x.max()), float(y.min()), float(y.max())
    r = np.random.default_rng(19)
    field = np.zeros_like(x)
    for _ in range(int(dust * (x1 - x0) * (y1 - y0))):
        sx, sy = x0 + r.random() * (x1 - x0), y0 + r.random() * (y1 - y0)
        if (sx - STAR[0]) ** 2 + (sy - STAR[1]) ** 2 < 0.05:
            continue
        field += node_light(0, sx, sy, 0.004 + 0.004 * r.random(), 0.25 + 0.45 * r.random(), xy=xy)
    rgb = rgb + WHITE * np.clip(field, 0, 1)[..., None] * 0.55

    # the route comes from beyond the lower-left corner of the canvas
    start = (min(-0.04, x0 - 0.05), max(1.02, y1 + 0.05))
    pts = bezier(start, (0.20, 0.66), (0.38, 0.44), (STAR[0] - 0.02, STAR[1] + 0.035))
    route = route_field(U, pts, 0.010 if unit >= 128 else 0.016, xy=xy)[..., None]
    rgb = rgb * (1 - route * 0.9) + ROUTE * route * 0.9
    nodes = np.zeros_like(x)
    for k, strength in ((0.30, 0.55), (0.52, 0.75), (0.72, 0.95)):
        nx, ny = pts[int(k * (len(pts) - 1))]
        nodes += node_light(0, nx, ny, 0.016 if unit >= 64 else 0.022, strength, xy=xy)
    rgb = rgb + WHITE * np.clip(nodes, 0, 1.2)[..., None] * 0.9

    core, glow = star_light(0, STAR[0], STAR[1], STAR_R, xy=xy)
    rgb = rgb + STAR_TINT * glow[..., None] * 0.55
    c = np.clip(core, 0, 1)[..., None]
    rgb = rgb * (1 - c) + WHITE * c
    rgb = rgb + np.random.default_rng(5).uniform(-0.5, 0.5, rgb.shape)   # dither
    img = Image.fromarray(np.clip(rgb + 0.5, 0, 255).astype(np.uint8), "RGB")
    return img.resize((w, h), Image.LANCZOS)


def star_sprite(size, core_rgb=(255, 255, 255), glow_rgb=(150, 185, 255), ray_w=2.6, core_k=1.7, glow_k=0.6, detail=True):
    """Transparent luminous star for the connect animation: the same light as
    the icon's star, drawn bolder since it is shown at 26–46 px."""
    s = size * SS
    R = 0.44                                   # north ray (1.08 R) stays inside
    core, glow = star_light(s, 0.5, 0.5, R, detail=detail, ray_w=ray_w, ray_gain=1.8, taper=0.7)
    x, y = grid(s)
    d2 = (x - 0.5) ** 2 + (y - 0.5) ** 2
    core = core + gauss(d2, R * 0.062 * core_k) * 0.6
    window = np.clip((0.5 - np.sqrt(d2)) / 0.14, 0, 1) ** 2   # glow ends before the edge
    c = np.clip(core, 0, 1)
    g = np.clip(glow * glow_k * window, 0, 1)
    a = np.clip(c + g * (1 - c), 0, 1)
    col = (np.array(core_rgb, np.float32) * c[..., None] + np.array(glow_rgb, np.float32) * (g * (1 - c))[..., None]) / np.maximum(a, 1e-4)[..., None]
    rgba = np.dstack([np.clip(col, 0, 255), a * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").resize((size, size), Image.LANCZOS)


FONTS = r"C:\Windows\Fonts"


def wordmark(w, h, color, parts=(("LODESTAR", "seguisb.ttf"), ("VPN", "segoeuil.ttf")), spacing=0.32):
    """Letter-spaced product name; "VPN" in a light weight, so LODESTARVPN
    reads as one word with two parts."""
    s_w, s_h = w * SS, h * SS
    img = Image.new("RGBA", (s_w, s_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def layout(px):
        glyphs = []                                     # (char, font, advance)
        for text, face in parts:
            f = ImageFont.truetype(os.path.join(FONTS, face), px)
            glyphs += [(ch, f, d.textlength(ch, font=f)) for ch in text]
        gap = px * spacing
        return glyphs, gap, sum(g[2] for g in glyphs) + gap * (len(glyphs) - 1)

    px = int(s_h * 0.9)
    glyphs, gap, total = layout(px)
    if total > s_w * 0.98:
        px = int(px * s_w * 0.98 / total)
        glyphs, gap, total = layout(px)
    ref = glyphs[0][1]
    bbox = d.textbbox((0, 0), parts[0][0], font=ref)
    yy = (s_h - (bbox[3] - bbox[1])) / 2 - bbox[1]
    xx = (s_w - total) / 2
    for ch, f, adv in glyphs:
        d.text((xx, yy), ch, font=f, fill=color)
        xx += adv + gap
    return img.resize((w, h), Image.LANCZOS)


def hero(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    m = mark(int(h * 0.64))
    img.alpha_composite(m, ((w - m.width) // 2, int(h * 0.03)))
    wm = wordmark(int(w * 0.84), int(h * 0.11), ACCENT)
    img.alpha_composite(wm, ((w - wm.width) // 2, int(h * 0.79)))
    return img


def save_ico(path, sizes):
    frames = [mark(s) for s in sizes]
    frames[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[:-1])


def make_android_assets():
    AND = os.path.join(ROOT, "client", "android", "res")
    META = os.path.join(ROOT, "metadata", "en-US", "images")

    # 0. The adaptive launcher icon (all our Android versions, 8+): the sky
    # fills the whole 108 dp layer and the launcher cuts it to its own shape —
    # a round picture on its own got a white plate around it (HyperOS, One UI).
    # The mark's square spans 75 dp, so the star and the route stay inside the
    # 66 dp safe circle; the foreground is empty, the monochrome layer
    # (themed icons, Android 13+) is the status bar's star
    for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        size = int(108 * scale)
        unit = 75 * scale
        scene(size, size, (size - unit) / 2, (size - unit) / 2, unit).save(
            os.path.join(AND, f"mipmap-{density}", "icon_background.png"))

    # 1. Launcher icons
    densities = {
        "ldpi": 36,
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192
    }
    for density, size in densities.items():
        folder = os.path.join(AND, f"mipmap-{density}")
        os.makedirs(folder, exist_ok=True)
        m = mark(size)
        m.save(os.path.join(folder, "icon.png"))
        m.save(os.path.join(folder, "icon_round.png"))

    # 2. TV Banners
    banner_bg = Image.new("RGB", (320, 180), (10, 16, 48))
    m110 = mark(110)
    banner_bg.paste(m110, (24, 35), m110)
    wm = wordmark(150, 24, (255, 255, 255))
    banner_bg.paste(wm, (144, 78), wm)

    banner_fg = Image.new("RGBA", (320, 180), (0, 0, 0, 0))
    banner_fg.paste(m110, (24, 35), m110)
    banner_fg.paste(wm, (144, 78), wm)

    for density in ["mdpi", "hdpi", "xhdpi"]:
        folder = os.path.join(AND, f"mipmap-{density}")
        banner_bg.save(os.path.join(folder, "ic_banner.png"))
    banner_fg.save(os.path.join(AND, "mipmap-xhdpi", "ic_banner_foreground.png"))

    # 3. Drawable logo wordmarks
    wm_logo = wordmark(150, 22, (255, 255, 255)).convert("L")
    for density in ["ldpi", "mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]:
        folder = os.path.join(AND, f"drawable-{density}")
        os.makedirs(folder, exist_ok=True)
        wm_logo.save(os.path.join(folder, "logo.png"))

    # 4. Store metadata icon
    if os.path.exists(META):
        mark(512).save(os.path.join(META, "icon.png"))
    print("android assets done")


def make_desktop_assets():
    save_ico(os.path.join(IMG, "app.ico"), [16, 20, 24, 32, 40, 48, 64, 96, 128, 256])
    mark(256).save(os.path.join(IMG, "icon.png"))
    mark(1024).save(os.path.join(IMG, "app.icns"))
    hero(1280, 1024).save(os.path.join(IMG, "dopamineBigLogo.png"))
    wordmark(170, 22, (151, 153, 155)).save(os.path.join(IMG, "Dopamine.png"))
    # tray (shown at 16–32 px): the small mark - colour when connected,
    # grey when not, red star on error
    for name, mode in (("active", "color"), ("default", "gray"), ("error", "error")):
        mark(200, mode, small=True).save(os.path.join(IMG, "tray", name + ".png"))
    # the lodestar of the connect button (it always flies over the button's
    # night sky, so one white star serves both themes; the background stars
    # are drawn by client/shaders/nightsky.frag)
    star_sprite(256).save(os.path.join(IMG, "star.png"))
    # installer (Qt IFW) icons
    save_ico(os.path.join(CFG, "frkn.ico"), [16, 32, 48, 64, 128, 256])
    mark(256).save(os.path.join(CFG, "frkn.png"))
    mark(1024).save(os.path.join(CFG, "frkn.icns"))


if __name__ == "__main__":
    import sys
    parts = {"desktop": make_desktop_assets, "android": make_android_assets}
    for name in (sys.argv[1:] or list(parts)):
        parts[name]()
    print("done")

