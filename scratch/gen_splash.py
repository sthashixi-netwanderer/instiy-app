import subprocess, os
from PIL import Image

SVG = "assets/logo.svg"
OUT_LEGACY = "assets/splash_logo.png"
OUT_A12 = "assets/splash_logo_android12.png"

def render_svg(width, out):
    subprocess.run(["rsvg-convert", "-w", str(width), "-h", str(width), SVG, "-o", out], check=True)

# --- Legacy splash source ---
# Canvas 768, logo content ~512 centered (gives breathing room, matches A12 scale)
legacy_canvas = 768
legacy_logo = 512
tmp = "scratch/_logo_legacy.png"
render_svg(legacy_logo, tmp)
logo = Image.open(tmp).convert("RGBA")
canvas = Image.new("RGBA", (legacy_canvas, legacy_canvas), (0,0,0,0))
off = (legacy_canvas - legacy_logo)//2
canvas.alpha_composite(logo, (off, off))
canvas.save(OUT_LEGACY)
print("wrote", OUT_LEGACY, canvas.size)

# --- Android 12 splash source ---
# A12 masked icon: canvas should be 4x the safe content. Safe zone is the inner 2/3.
# Use 1152 canvas, logo content 768 (=> content occupies 2/3, sits fully inside circular mask)
a12_canvas = 1152
a12_logo = 768
tmp2 = "scratch/_logo_a12.png"
render_svg(a12_logo, tmp2)
logo2 = Image.open(tmp2).convert("RGBA")
canvas2 = Image.new("RGBA", (a12_canvas, a12_canvas), (0,0,0,0))
off2 = (a12_canvas - a12_logo)//2
canvas2.alpha_composite(logo2, (off2, off2))
canvas2.save(OUT_A12)
print("wrote", OUT_A12, canvas2.size)
