"""Turn the home page's stills into one-colour fields of dots.

Reads the opening still in art/ and the products' stills in
platform/priv/static/images/value-cards/, and writes each picture, on each of its
grids, to platform/priv/static/images/home/ as an SVG of dots, with
platform/assets/css/pages/home_pictures.css naming them. Each picture is a rectangle
of round dots on a square grid, one dot in every cell, the subject and its ground
alike. A dot's size follows the still's lightness: the ground draws in the smallest
dots and the parts that stand out from it in larger ones. The page paints the dots
in the home colour, through a mask (`.pic` in pages/home.css).

Each picture is drawn on a few grids, picked by the window's width, so the dots stay
about 5 to 8 CSS pixels apart at every width: 7 at 1440 wide and 5.5 at 390.

The dots are zero-length strokes with round ends, one path per dot size, which keeps a
field of twelve thousand dots small.

Run from the repository root:
    uv run --with pillow scripts/home-pictures/dither.py
"""

from pathlib import Path
from statistics import median

from PIL import Image, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent.parent
ART = Path(__file__).resolve().parent / "art"
STILLS = ROOT / "platform/priv/static/images/value-cards"
OUT = ROOT / "platform/priv/static/images/home"
CSS = ROOT / "platform/assets/css/pages/home_pictures.css"

# Ten dot sizes. The smallest covers 5% of its cell, so the ground still reads as dots;
# the largest covers 60%, a dot 0.87 of the cell across, so dots never touch.
LEVELS = 10
SMALLEST = 0.05
LARGEST = 0.60
# Tones past the ground are bent towards the smaller dots, so the brighter parts of a
# subject stay apart from its middle tones instead of merging into one dark mass.
CURVE = 1.3

# Grids as (window widths, columns, rows); the first has no condition, later ones win.
# The opening picture spans the page, less its gutters. A product picture fills half a
# row on wide windows and the whole row once the row stacks, at 48rem.
HERO = [
    (None, 196, 64),
    ("(width <= 62rem)", 110, 46),
    ("(width <= 34rem)", 65, 46),
]
PRODUCT = [
    (None, 95, 63),
    ("(width <= 33rem), (48rem < width <= 69rem)", 65, 43),
]

# name: still, the part of it to draw (left, top, right, bottom as fractions), blur in
# the still's pixels (enough to melt an LED grid into tone), grids. A part wider than its
# grid is trimmed at both sides; a narrower one is widened with its own ground.
PICTURES = {
    "hero": (ART / "splats-trainer-battle-wide.png", (0.0, 0.0, 1.0, 1.0), 0.6, HERO),
    "keyfleet": (STILLS / "fleet.webp", (0.05, 0.05, 0.95, 0.65), 5, PRODUCT),
    "autolaunch": (STILLS / "level.webp", (0.0, 0.25, 1.0, 0.92), 7, PRODUCT),
    "protocol": (STILLS / "prorata.webp", (0.0, 0.33, 1.0, 1.0), 7, PRODUCT),
    "patchbay": (STILLS / "blob.webp", (0.1, 0.12, 0.9, 0.65), 7, PRODUCT),
    "techtree": (STILLS / "compare.webp", (0.5, 0.04, 1.0, 0.38), 5, PRODUCT),
    "cloak": (STILLS / "cloak/rewrite.webp", (0.0, 0.15, 1.0, 0.82), 7, PRODUCT),
}


def ring(image):
    """The pixels round the image's edge."""
    width, height = image.size
    px = image.load()
    edge = [px[x, 0] for x in range(width)] + [px[x, height - 1] for x in range(width)]
    return edge + [px[0, y] for y in range(height)] + [px[width - 1, y] for y in range(height)]


def ground(image):
    """The still's ground: the median colour of its edge."""
    return tuple(round(median(channel)) for channel in zip(*ring(image)))


def part(image, box, cols, rows):
    """The chosen part of the still, trimmed or widened with its ground to the grid's shape."""
    width, height = image.size
    left, top, right, bottom = box
    image = image.crop((round(left * width), round(top * height), round(right * width), round(bottom * height)))
    width, height = image.size
    target = cols / rows
    if width / height > target:
        keep = round(height * target)
        cut = (width - keep) // 2
        return image.crop((cut, 0, cut + keep, height))
    canvas = Image.new("RGB", (round(height * target), height), ground(image))
    canvas.paste(image, ((canvas.width - width) // 2, 0))
    return canvas


def levels(name, cols, rows):
    """Each cell's dot size, 0 (smallest) to LEVELS - 1, from the still's lightness.

    The ground takes the smallest dots: on a dark ground the light parts draw large, on a
    light ground the dark parts do. Clear parts of a still count as dark ground.
    """
    still, box, blur, _ = PICTURES[name]
    image = Image.open(still).convert("RGBA")
    flat = Image.new("RGBA", image.size, (0, 0, 0, 255))
    flat.alpha_composite(image)
    image = part(flat.convert("RGB"), box, cols, rows).filter(ImageFilter.GaussianBlur(blur))
    cells = image.resize((cols, rows), Image.Resampling.BOX).convert("L")
    if median(ring(cells)) > 127:
        cells = ImageOps.invert(cells)
    # Sharpened, so a subject's inner edges show. The darkest dots are set by the cells as
    # they were, so the dip sharpening leaves round an edge never draws a ring below the
    # ground; the largest by the sharpened cells, so bright parts keep their detail.
    tones = list(cells.filter(ImageFilter.UnsharpMask(2, 110, 0)).tobytes())
    dark = sorted(cells.tobytes())[cols * rows // 50]
    light = sorted(tones)[-cols * rows // 50 - 1]
    span = max(1, light - dark)
    return [
        [round(min(1, max(0, (tones[y * cols + x] - dark) / span)) ** CURVE * (LEVELS - 1)) for x in range(cols)]
        for y in range(rows)
    ]


def diameter(level):
    """A dot's width, in cells, for its size level."""
    cover = SMALLEST + (LARGEST - SMALLEST) * level / (LEVELS - 1)
    return 2 * (cover / 3.141592653589793) ** 0.5


def svg(grid_levels):
    """The dots as an SVG: one path of zero-length round-ended strokes per size."""
    rows, cols = len(grid_levels), len(grid_levels[0])
    paths = []
    for level in range(LEVELS):
        moves, at = [], None
        for y in range(rows):
            for x in range(cols):
                if grid_levels[y][x] != level:
                    continue
                moves.append(f"M{x} {y}h0" if at is None else f"m{x - at[0]} {y - at[1]}h0")
                at = (x, y)
        if moves:
            paths.append(f"<path stroke-width='{diameter(level):.3f}' d='{''.join(moves)}'/>")
    return (
        f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='-0.5 -0.5 {cols} {rows}' "
        "fill='none' stroke='black' stroke-linecap='round'>" + "".join(paths) + "</svg>\n"
    )


def main():
    OUT.mkdir(exist_ok=True)
    blocks = {}
    for name, (still, _, _, grids) in PICTURES.items():
        for media, cols, rows in grids:
            file = f"{name}-{cols}x{rows}.svg"
            (OUT / file).write_text(svg(levels(name, cols, rows)))
            rule = f'.pic--{name} {{ aspect-ratio: {cols} / {rows}; --pic: url("/images/home/{file}"); }}'
            blocks.setdefault(media, []).append(rule)
        print(f"{name:11} {still.name:34} " + ", ".join(f"{cols}x{rows}" for _, cols, rows in grids))

    lines = [
        "/* Generated by scripts/home-pictures/dither.py. Run it again rather than editing.",
        " * Each picture is a mask of round dots; .pic (pages/home.css) paints it. */",
    ]
    for media, rules in blocks.items():
        if media is None:
            lines += rules
        else:
            lines += [f"@media {media} {{", *(f"  {rule}" for rule in rules), "}"]
    CSS.write_text("\n".join(lines) + "\n")
    print(f"wrote {CSS} and {OUT}")


if __name__ == "__main__":
    main()
