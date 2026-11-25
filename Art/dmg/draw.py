# Draws the window shown when Docked.dmg opens: 640x400 points, at 1x and 2x. Original art, in the colours of Art/hero.png.
# python3 Art/dmg/draw.py Art/dmg/background.png Art/dmg/background@2x.png   (needs Pillow and the Inter font; INTER=folder if it lives elsewhere)
import os, sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont
W, H = 640, 400
APP, APPS, ICON_Y = 170, 470, 190   # icon centres, must match Bundle/dmg.sh
F = os.environ.get('INTER', '/usr/share/fonts/opentype/inter').rstrip('/') + '/'
def draw(s, out):
    w, h = W*s, H*s
    # base: the hero's dark slate, a little lighter at the top
    im = Image.new('RGB', (w, h))
    px = im.load()
    top, bot = (0xf7,0xfa,0xfb), (0xe4,0xee,0xf0)
    for y in range(h):
        t = y/(h-1); c = tuple(round(top[i]+(bot[i]-top[i])*t) for i in range(3))
        for x in range(w): px[x,y] = c
    # teal glow low in the middle, as in the hero
    glow = Image.new('L', (w, h), 0); g = ImageDraw.Draw(glow)
    g.ellipse([w*0.18, h*0.55, w*0.82, h*1.35], fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(90*s))
    im = Image.composite(Image.new('RGB', (w, h), (0x9f,0xd3,0xdb)), im, glow.point(lambda v: v*0.5))
    d = ImageDraw.Draw(im, 'RGBA')
    # soft wells the two icons sit in
    for cx in (APP, APPS):
        r = 86*s; d.rounded_rectangle([cx*s-r, ICON_Y*s-r, cx*s+r, ICON_Y*s+r+16*s], radius=34*s, fill=(255,255,255,150), outline=(0x1f,0x66,0x75,28), width=max(1,s))
    # dotted arc with an arrowhead, from Docked to Applications
    x0, x1, y = (APP+94)*s, (APPS-112)*s, ICON_Y*s
    n = 9
    for i in range(n):
        t = i/(n-1); x = x0+(x1-x0)*t; yy = y - math.sin(math.pi*t)*14*s
        r = (2.2+1.2*t)*s; a = int(90+140*t)
        d.ellipse([x-r, yy-r, x+r, yy+r], fill=(0x1f,0x66,0x75,a))
    ax = x1+20*s
    d.polygon([(ax, y), (ax-14*s, y-9*s), (ax-14*s, y+9*s)], fill=(0x1f,0x66,0x75,235))
    # words
    big = ImageFont.truetype(F+'Inter-SemiBold.otf', 22*s); small = ImageFont.truetype(F+'Inter-Regular.otf', 13*s)
    def centre(text, font, yy, fill):
        bw = d.textlength(text, font=font); d.text(((w-bw)/2, yy), text, font=font, fill=fill)
    centre('Drag Docked into Applications', big, 314*s, (0x16,0x1e,0x23,255))
    centre('Then open it from your Applications folder.', small, 348*s, (0x5a,0x6b,0x73,255))
    im.save(out, dpi=(72*s, 72*s))
draw(1, sys.argv[1]); draw(2, sys.argv[2])
