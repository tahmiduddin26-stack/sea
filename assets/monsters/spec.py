# Tide Tamers: every sea monster, enemy and boss as a blocky voxel toy.
#
# ONE spec drives everything:
#   * Game:    src/shared/MonsterShapes.luau (GENERATED, never hand-edit). The client builds
#              each creature from parts and animates the same bones with the same formulas
#              (shared/MonsterModels.luau), so nothing has to be uploaded.
#   * Blender: build_blender.py builds each model (bevelled blocks), rigs it (one bone per
#              moving part, rigid skinning) and bakes A_<Id>_Idle / _Swim / _Attack actions,
#              exports FBX per creature and renders a contact sheet.
#
# Coordinates are Roblox space: studs, Y up, the face looks down -Z, creature centred on
# the origin, about 3 studs tall at scale 1. Style: chunky blocks, flat colours, big
# square eyes, a few neon accents. Keep every model under ~30 pieces.
#
# Plain Python (no bpy needed) for the Luau export:
#   python assets/monsters/spec.py
import math, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_LUAU = os.path.join(ROOT, "src", "shared", "MonsterShapes.luau")

LOOP = 2.0  # seconds; each bone's speed is whole cycles per LOOP so loops are seamless

INK = (22, 24, 40)
WHITE = (255, 255, 255)
BONE = (238, 232, 210)


class Creature:
    def __init__(self, cid, name, kind):
        self.id = cid
        self.name = name
        self.kind = kind  # "monster" | "enemy" | "boss"
        # the root bone floats: a gentle bob on the water
        self.bones = [dict(name="Body", parent=None, pivot=(0, 0, 0), anim="move", axis="Y", amp=0.08,
                           speed=1, phase=0.0, swim=None)]
        self.pieces = []

    def bone(self, name, pivot, parent="Body", anim="rot", axis="X", amp=8.0, speed=1, phase=0.0,
             swim=None):
        """anim: None | rot (sine swing, amp deg) | spin (turns per loop) | move (sine bob, amp studs).
        swim: optional dict overriding anim/axis/amp/speed/phase for the faster battle cycle."""
        self.bones.append(dict(name=name, parent=parent, pivot=pivot, anim=anim, axis=axis, amp=amp,
                               speed=speed, phase=phase, swim=swim))

    def box(self, bone, size, pos, color, rot=(0, 0, 0), mat="p"):
        self._add("B", bone, size, pos, color, rot, mat)

    def ball(self, bone, size, pos, color, rot=(0, 0, 0), mat="p"):
        if isinstance(size, (int, float)):
            size = (size, size, size)
        self._add("S", bone, size, pos, color, rot, mat)

    def _add(self, kind, bone, size, pos, color, rot, mat):
        assert any(b["name"] == bone for b in self.bones), (self.id, bone)
        self.pieces.append(dict(kind=kind, bone=bone, size=size, pos=pos, rot=rot, color=color, mat=mat))


CREATURES = []


def creature(cid, name, kind="monster"):
    c = Creature(cid, name, kind)
    CREATURES.append(c)
    return c


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------
def eyes(c, bone, y, z, dx=0.32, s=0.34, pupil=INK, white=WHITE, angry=False, glow=None):
    """Big square toy eyes on a face plane at z (face looks -Z)."""
    for side in (-1, 1):
        if glow:
            c.box(bone, (s, s, 0.08), (side * dx, y, z - 0.02), glow, mat="n")
            continue
        c.box(bone, (s, s * 1.1, 0.08), (side * dx, y, z - 0.02), white)
        c.box(bone, (s * 0.5, s * 0.6, 0.06), (side * dx + side * -0.04, y - 0.03, z - 0.07), pupil)
        if angry:
            c.box(bone, (s * 1.1, 0.09, 0.08), (side * dx, y + s * 0.62, z - 0.05), INK, rot=(0, 0, side * -18))


def tail_chain(c, start, segs, axis="Y", amp=14, speed=1, parent="Body", prefix="Tail", lag=0.9):
    """A chain of tail blocks along +Z, each its own bone, phase-lagged so the tail ripples.
    segs: list of (size, color, mat)."""
    z = start[2]
    prev = parent
    for i, (size, color, mat) in enumerate(segs):
        name = "%s%d" % (prefix, i + 1)
        c.bone(name, (start[0], start[1], z), parent=prev, anim="rot", axis=axis, amp=amp, speed=speed,
               phase=-i * lag)
        c.box(name, size, (start[0], start[1], z + size[2] / 2), color, mat=mat)
        z += size[2] * 0.92
        prev = name
    return prev, z


def fin_pair(c, size, x, y, z, color, axis="Z", amp=20, speed=2, rot=(0, 0, 0), name="Fin", parent="Body"):
    for side, tag in ((-1, "L"), (1, "R")):
        c.bone(name + tag, (side * x, y, z), parent=parent, anim="rot", axis=axis, amp=amp * side, speed=speed)
        c.box(name + tag, size, (side * (x + size[0] / 2), y, z), color, rot=(rot[0], rot[1] * side, rot[2] * side))


def tentacles(c, n, radius, y, color, length=3, seg=(0.22, 0.4, 0.22), amp=18, mat="p", tip=None):
    for i in range(n):
        a = i / n * math.tau
        x, z = math.cos(a) * radius, math.sin(a) * radius
        prev = "Body"
        yy = y
        for j in range(length):
            name = "Ten%d_%d" % (i, j)
            c.bone(name, (x, yy, z), parent=prev, anim="rot", axis="X" if i % 2 == 0 else "Z", amp=amp,
                   speed=1, phase=i * 0.7 + j * 0.8)
            col = tip if (tip and j == length - 1) else color
            c.box(name, seg, (x, yy - seg[1] / 2, z), col, mat=mat)
            yy -= seg[1] * 0.9
            prev = name


def legs(c, spots, size, color, amp=14):
    for i, (x, y, z) in enumerate(spots):
        name = "Leg%d" % (i + 1)
        c.bone(name, (x, y, z), anim="rot", axis="X", amp=amp, speed=2, phase=0 if i % 2 == 0 else math.pi)
        c.box(name, size, (x, y - size[1] / 2, z), color)


def spikes(c, bone, points, size, color, mat="p"):
    for (x, y, z, rx, rz) in points:
        c.box(bone, size, (x, y, z), color, rot=(rx, 0, rz), mat=mat)


# ===========================================================================
# MONSTERS (player side) - chunky voxel SEA DRAGONS, like the reference game's
# dragons: big head, horns or fin crest, flapping fin-wings, claws, a fat tapering
# tail, element accents. Rarity (stars) adds detail: 3* glowing runes + teeth,
# 4* a crown and extra spikes, 5* a second pair of wings and a halo.
# ===========================================================================
CLAW = (250, 248, 240)
TOOTH = (255, 255, 255)


def sea_dragon(c, body, belly, accent, horn=None, glow=None, crest="horns", wing="fin", tail_end="fin",
               size=1.0, stars=1, whiskers=False, snout=1.0, chunky=1.0, legs4=True, spikes_col=None):
    s = size
    hx = 1.55 * chunky
    # body + belly + back spikes
    c.box("Body", (1.7 * s * chunky, 1.4 * s, 2.1 * s), (0, 0.05 * s, 0.35 * s), body)
    c.box("Body", (1.3 * s * chunky, 0.45 * s, 1.9 * s), (0, -0.5 * s, 0.35 * s), belly)
    sc = spikes_col or accent
    n_sp = 2 + min(stars, 4)
    for i in range(n_sp):
        z = -0.45 * s + i * (1.9 * s / n_sp)
        h = (0.55 - abs(i - n_sp / 2) * 0.06) * s
        c.box("Body", (0.22 * s, h, 0.38 * s), (0, 0.85 * s + h / 2 - 0.1 * s, z), sc, rot=(-20, 0, 0))
    # neck + head
    c.bone("Head", (0, 0.45 * s, -0.55 * s), anim="rot", axis="X", amp=6, speed=1,
           swim=dict(anim="rot", axis="X", amp=12, speed=2, phase=0))
    c.box("Head", (0.9 * s, 0.9 * s, 0.7 * s), (0, 0.55 * s, -0.75 * s), body)  # neck
    c.box("Head", (hx * s, 1.3 * s, 1.35 * s), (0, 1.0 * s, -1.25 * s), body)
    c.box("Head", (1.05 * s * chunky, 0.6 * s, 0.75 * s * snout), (0, 0.72 * s, -2.1 * s - 0.15 * (snout - 1)), body)  # snout
    c.box("Head", (0.85 * s * chunky, 0.2 * s, 0.6 * s * snout), (0, 0.42 * s, -2.05 * s), belly)  # upper lip
    for sx in (-1, 1):
        c.box("Head", (0.14 * s, 0.1 * s, 0.06 * s), (sx * 0.28 * s, 0.88 * s, -2.48 * s - 0.15 * (snout - 1)), (30, 30, 40))  # nostrils
    # eyes: white, pupil, shine, brow
    for sx in (-1, 1):
        ex = sx * 0.45 * s * chunky
        c.box("Head", (0.44 * s, 0.48 * s, 0.1 * s), (ex, 1.2 * s, -1.93 * s), WHITE)
        c.box("Head", (0.24 * s, 0.32 * s, 0.08 * s), (ex + sx * 0.04 * s, 1.15 * s, -1.99 * s), INK)
        c.box("Head", (0.1 * s, 0.1 * s, 0.05 * s), (ex - sx * 0.05 * s, 1.27 * s, -2.03 * s), WHITE, mat="n")
        c.box("Head", (0.5 * s, 0.12 * s, 0.14 * s), (ex, 1.5 * s, -1.92 * s), accent, rot=(0, 0, sx * 14))
        # cheek fins
        c.box("Head", (0.12 * s, 0.5 * s, 0.6 * s), (sx * (hx * s / 2 + 0.05 * s), 1.0 * s, -1.2 * s), accent,
              rot=(0, sx * 25, 0))
    # jaw (opens when swimming / biting)
    c.bone("Jaw", (0, 0.42 * s, -1.4 * s), parent="Head", anim="rot", axis="X", amp=3, speed=1,
           swim=dict(anim="rot", axis="X", amp=14, speed=4, phase=0))
    c.box("Jaw", (0.95 * s * chunky, 0.3 * s, 1.0 * s * snout), (0, 0.27 * s, -1.95 * s), belly)
    if stars >= 3:
        for x in (-0.3, 0.3):
            c.box("Jaw", (0.12 * s, 0.18 * s, 0.1 * s), (x * s, 0.47 * s, -2.35 * s), TOOTH)
    # crest
    hc = horn or accent
    if crest == "horns":
        for sx in (-1, 1):
            c.box("Head", (0.22 * s, 0.75 * s, 0.22 * s), (sx * 0.5 * s, 1.85 * s, -1.0 * s), hc, rot=(-30, 0, sx * -20))
            c.box("Head", (0.16 * s, 0.45 * s, 0.16 * s), (sx * 0.62 * s, 2.25 * s, -0.75 * s), hc, rot=(-55, 0, sx * -25))
    elif crest == "fin":
        for i in range(3):
            c.box("Head", (0.12 * s, (0.75 - i * 0.15) * s, 0.4 * s), (0, (1.85 - i * 0.05) * s, (-1.45 + i * 0.35) * s),
                  hc, rot=(-25, 0, 0))
    elif crest == "flame":
        for i, (h, z) in enumerate(((0.7, -1.5), (0.95, -1.15), (0.6, -0.8))):
            c.box("Head", (0.35 * s, h * s, 0.35 * s), (0, 1.7 * s + h * s / 2, z * s), glow or hc, mat="n")
    elif crest == "crown":
        for i in range(5):
            a = -0.6 + i * 0.3
            c.box("Head", (0.14 * s, 0.5 * s, 0.14 * s), (a * s, 1.85 * s, -1.2 * s), (255, 215, 60), mat="m")
    if whiskers:
        for sx in (-1, 1):
            c.bone("Whisk" + ("L" if sx < 0 else "R"), (sx * 0.5 * s, 0.7 * s, -2.3 * s), parent="Head", anim="rot",
                   axis="Y", amp=18 * sx, speed=1)
            c.box("Whisk" + ("L" if sx < 0 else "R"), (0.08 * s, 0.08 * s, 1.0 * s), (sx * 0.85 * s, 0.6 * s, -2.55 * s),
                  glow or accent, rot=(0, sx * 50, 0), mat="n" if glow else "p")
    # wings (fins) - flap
    if wing:
        mem = glow if (wing == "glow" and glow) else accent
        for sx, tag in ((-1, "L"), (1, "R")):
            name = "Wing" + tag
            c.bone(name, (sx * 0.8 * s, 0.6 * s, 0.1 * s), anim="rot", axis="Z", amp=20 * sx, speed=1,
                   swim=dict(anim="rot", axis="Z", amp=38 * sx, speed=2, phase=0))
            c.box(name, (1.4 * s, 0.16 * s, 0.24 * s), (sx * 1.35 * s, 1.15 * s, -0.05 * s), body, rot=(0, 0, sx * 38))
            c.box(name, (1.5 * s, 0.1 * s, 1.3 * s), (sx * 1.35 * s, 1.0 * s, 0.6 * s), mem,
                  mat="n" if wing == "glow" else "p", rot=(0, sx * 8, sx * 34))
            c.box(name, (0.8 * s, 0.1 * s, 0.8 * s), (sx * 1.95 * s, 1.55 * s, 0.4 * s), mem,
                  mat="n" if wing == "glow" else "p", rot=(0, sx * 25, sx * 48))
            if stars >= 5:
                name2 = "Wing2" + tag
                c.bone(name2, (sx * 0.7 * s, 0.4 * s, 0.7 * s), anim="rot", axis="Z", amp=26 * sx, speed=1, phase=1.2)
                c.box(name2, (1.0 * s, 0.1 * s, 0.8 * s), (sx * 1.25 * s, 0.4 * s, 0.95 * s), glow or mem, mat="n",
                      rot=(0, sx * -10, sx * 10))
    # legs with claws
    if legs4:
        spots = [(-0.6, -0.55, -0.35), (0.6, -0.55, -0.35), (-0.6, -0.55, 1.05), (0.6, -0.55, 1.05)]
        for i, (x, y, z) in enumerate(spots):
            name = "Leg%d" % (i + 1)
            c.bone(name, (x * s, y * s, z * s), anim="rot", axis="X", amp=10, speed=1, phase=0 if i % 2 == 0 else math.pi,
                   swim=dict(anim="rot", axis="X", amp=30, speed=2, phase=0 if i % 2 == 0 else math.pi))
            c.box(name, (0.42 * s, 0.55 * s, 0.48 * s), (x * s, (y - 0.25) * s, z * s), body)
            c.box(name, (0.46 * s, 0.14 * s, 0.56 * s), (x * s, (y - 0.55) * s, (z - 0.05) * s), belly)
            for cx in (-0.12, 0.12):
                c.box(name, (0.1 * s, 0.1 * s, 0.14 * s), ((x + cx) * s, (y - 0.56) * s, (z - 0.35) * s), CLAW)
    # tail chain, tapering
    segs = [((1.1 * s, 0.95 * s, 0.9 * s), body, "p"), ((0.85 * s, 0.75 * s, 0.85 * s), body, "p"),
            ((0.6 * s, 0.55 * s, 0.8 * s), body, "p")]
    last, zend = tail_chain(c, (0, 0.0, 1.4 * s), segs, amp=14)
    if tail_end == "fin":
        c.box(last, (1.4 * s, 0.14 * s, 0.7 * s), (0, 0.0, zend + 0.25 * s), accent)
    elif tail_end == "spike":
        c.box(last, (0.3 * s, 0.6 * s, 0.6 * s), (0, 0.2 * s, zend + 0.15 * s), hc, rot=(30, 0, 0))
    elif tail_end == "orb":
        c.ball(last, 0.55 * s, (0, 0.1 * s, zend + 0.25 * s), glow or accent, mat="n")
    elif tail_end == "flame":
        c.box(last, (0.5 * s, 0.5 * s, 0.6 * s), (0, 0.1 * s, zend + 0.25 * s), glow or accent, mat="n")
    # rarity extras
    if stars >= 3 and glow:
        for z in (0.0, 0.55, 1.1):
            for sx in (-1, 1):
                c.box("Body", (0.06 * s, 0.35 * s, 0.25 * s), (sx * 0.87 * s * chunky, 0.15 * s, z * s), glow, mat="n")
    if stars >= 4:
        c.bone("Halo", (0, 2.4 * s, -1.2 * s), parent="Head", anim="spin", axis="Y", amp=0, speed=1)
        for i in range(6):
            a = i / 6 * math.tau
            c.box("Halo", (0.22 * s, 0.1 * s, 0.22 * s), (math.cos(a) * 0.55 * s, 2.45 * s, -1.2 * s + math.sin(a) * 0.55 * s),
                  glow or (255, 220, 80), mat="n")


# --- 1 star (commons: the winch eggs) -------------------------------------------------
c = creature("Splashfin", "Splashfin")
sea_dragon(c, (45, 150, 255), (190, 235, 255), (25, 100, 210), crest="fin", wing="fin", tail_end="fin", size=0.85, stars=1)

c = creature("Reefback", "Reefling")
sea_dragon(c, (255, 120, 150), (255, 225, 200), (120, 210, 160), horn=(255, 190, 210), crest="horns", wing=None,
           tail_end="spike", size=0.85, stars=1, chunky=1.15)
for (x, z) in ((-0.45, 0.0), (0.45, 0.5), (0.0, 0.9)):
    c.box("Body", (0.25, 0.55, 0.25), (x * 0.85, 0.95, z * 0.85), (255, 190, 210))

c = creature("Zapjelly", "Zappy")
sea_dragon(c, (255, 215, 50), (255, 245, 190), (255, 150, 30), glow=(255, 255, 150), crest="flame", wing="fin",
           tail_end="orb", size=0.85, stars=1, whiskers=True)

c = creature("Gloomeel", "Gloomy")
sea_dragon(c, (120, 70, 200), (200, 170, 240), (70, 35, 130), glow=(160, 255, 220), crest="fin", wing=None,
           tail_end="orb", size=0.85, stars=1, legs4=False, snout=1.2)
c.bone("Lure", (0, 1.85 * 0.85, -1.2 * 0.85), parent="Head", anim="rot", axis="X", amp=16, speed=1)
c.box("Lure", (0.08, 0.7, 0.08), (0, 1.95, -1.3), (70, 35, 130), rot=(30, 0, 0))
c.ball("Lure", 0.35, (0, 2.25, -1.65), (160, 255, 220), mat="n")

# --- 2 stars (rares + hybrids) -----------------------------------------------------
c = creature("Wavecrest", "Wavecrest")
sea_dragon(c, (30, 120, 235), (200, 240, 255), (120, 220, 255), glow=(150, 240, 255), crest="fin", wing="glow",
           tail_end="fin", size=1.0, stars=2, whiskers=True)

c = creature("Shellguard", "Shellguard")
sea_dragon(c, (240, 100, 90), (255, 220, 190), (255, 170, 120), horn=(255, 240, 220), crest="horns", wing=None,
           tail_end="spike", size=1.0, stars=2, chunky=1.25)
c.box("Body", (2.1, 0.7, 2.2), (0, 0.85, 0.4), (255, 140, 120))
c.box("Body", (1.6, 0.3, 1.7), (0, 1.3, 0.4), (255, 200, 170))

c = creature("Voltfin", "Voltfin")
sea_dragon(c, (60, 80, 200), (200, 210, 255), (255, 225, 40), glow=(255, 240, 90), crest="flame", wing="glow",
           tail_end="flame", size=1.0, stars=2)

c = creature("Inkling", "Inkling")
sea_dragon(c, (70, 40, 120), (190, 150, 230), (230, 90, 200), glow=(255, 120, 230), crest="horns", wing="fin",
           tail_end="orb", size=1.0, stars=2, whiskers=True)

c = creature("Kelpdrake", "Kelpdrake")
sea_dragon(c, (40, 175, 160), (210, 245, 220), (110, 220, 80), horn=(255, 205, 120), crest="horns", wing="fin",
           tail_end="fin", size=1.0, stars=2)

c = creature("Thunderwhale", "Thunderwhale")
sea_dragon(c, (55, 115, 225), (225, 240, 255), (255, 230, 40), glow=(255, 240, 120), crest="fin", wing="fin",
           tail_end="fin", size=1.05, stars=2, chunky=1.3, legs4=False)

c = creature("Inkshark", "Inkshark")
sea_dragon(c, (60, 70, 140), (210, 210, 235), (140, 90, 220), crest="fin", wing="fin", tail_end="fin", size=1.0,
           stars=2, snout=1.35)

c = creature("Sparkcrab", "Sparkcrab")
sea_dragon(c, (255, 125, 80), (255, 230, 200), (255, 220, 40), glow=(255, 240, 90), crest="horns", wing=None,
           tail_end="spike", size=1.0, stars=2, chunky=1.2)
for sx, tag in ((-1, "L"), (1, "R")):
    c.bone("Claw" + tag, (sx * 1.0, 0.3, -0.6), anim="rot", axis="Y", amp=12 * sx, speed=2,
           swim=dict(anim="rot", axis="Y", amp=30 * sx, speed=4, phase=0))
    c.box("Claw" + tag, (0.5, 0.5, 0.8), (sx * 1.3, 0.3, -0.9), (255, 125, 80))
    c.box("Claw" + tag, (0.7, 0.6, 0.6), (sx * 1.4, 0.4, -1.45), (255, 230, 60), mat="n")

c = creature("Bonereef", "Bonereef")
sea_dragon(c, (235, 230, 210), (150, 90, 210), (190, 120, 255), glow=(190, 120, 255), crest="horns", wing="fin",
           tail_end="spike", size=1.0, stars=2, spikes_col=(190, 120, 255))

c = creature("Voidray", "Voidray")
sea_dragon(c, (60, 30, 110), (200, 180, 240), (255, 220, 60), glow=(255, 230, 90), crest="fin", wing="glow",
           tail_end="orb", size=1.0, stars=2, legs4=False)

# --- 3 stars (epics) ---------------------------------------------------------------
c = creature("Tsunamaw", "Tsunamaw")
sea_dragon(c, (20, 95, 220), (180, 230, 255), (90, 210, 255), glow=(140, 240, 255), crest="horns", wing="glow",
           tail_end="fin", size=1.2, stars=3, whiskers=True, horn=(230, 250, 255))

c = creature("Coralord", "Coralord")
sea_dragon(c, (235, 80, 130), (255, 210, 220), (120, 230, 170), glow=(255, 160, 210), crest="horns", wing="fin",
           tail_end="spike", size=1.2, stars=3, chunky=1.15, horn=(255, 200, 220))

c = creature("Thunderjaw", "Thunderjaw")
sea_dragon(c, (40, 45, 90), (180, 190, 230), (255, 220, 40), glow=(255, 240, 80), crest="flame", wing="glow",
           tail_end="flame", size=1.2, stars=3, snout=1.2)

c = creature("Nightfang", "Nightfang")
sea_dragon(c, (35, 20, 60), (130, 90, 190), (200, 60, 255), glow=(220, 90, 255), crest="horns", wing="glow",
           tail_end="orb", size=1.2, stars=3, horn=(220, 210, 240))

# --- 4 stars (legendary) -----------------------------------------------------------
c = creature("Leviathan", "Leviathan")
sea_dragon(c, (20, 90, 100), (160, 220, 200), (90, 255, 200), glow=(90, 255, 200), crest="horns", wing="glow",
           tail_end="orb", size=1.35, stars=4, whiskers=True, horn=(235, 230, 210), snout=1.2)

c = creature("PearlDragon", "Pearl Dragon")
sea_dragon(c, (250, 245, 255), (255, 200, 225), (255, 170, 210), glow=(255, 235, 250), crest="crown", wing="glow",
           tail_end="orb", size=1.35, stars=4, whiskers=True)

# --- 5 stars (mythic) --------------------------------------------------------------
c = creature("KrakenKing", "Kraken King")
sea_dragon(c, (150, 20, 60), (255, 170, 190), (255, 210, 60), glow=(255, 90, 130), crest="crown", wing="glow",
           tail_end="flame", size=1.5, stars=5, whiskers=True, chunky=1.15)
tentacles(c, 4, 0.7, -0.75, (180, 30, 70), length=2, seg=(0.3, 0.45, 0.3), amp=18, tip=(255, 210, 60))


# --- 3 star hybrid evolutions (two of the same hybrid fused) -------------------------
c = creature("Kelpking", "Kelp King")
sea_dragon(c, (30, 150, 130), (210, 250, 220), (120, 230, 90), glow=(170, 255, 140), crest="crown", wing="glow",
           tail_end="fin", size=1.2, stars=3, whiskers=True)
for z in (0.0, 0.6, 1.2):
    c.box("Body", (0.5, 0.9, 0.12), (0.7, 1.0, z), (90, 200, 80), rot=(0, 0, -25))

c = creature("TempestWhale", "Tempest Whale")
sea_dragon(c, (40, 70, 170), (220, 235, 255), (255, 230, 60), glow=(255, 245, 120), crest="flame", wing="glow",
           tail_end="flame", size=1.25, stars=3, chunky=1.4, legs4=False)

c = creature("AbyssShark", "Abyss Shark")
sea_dragon(c, (40, 40, 100), (200, 200, 230), (150, 90, 255), glow=(170, 110, 255), crest="fin", wing="glow",
           tail_end="spike", size=1.2, stars=3, snout=1.5)

c = creature("Voltclaw", "Voltclaw")
sea_dragon(c, (230, 90, 60), (255, 225, 190), (255, 230, 50), glow=(255, 245, 110), crest="horns", wing="glow",
           tail_end="spike", size=1.2, stars=3, chunky=1.3)
for sx, tag in ((-1, "L"), (1, "R")):
    c.bone("Claw" + tag, (sx * 1.2, 0.3, -0.6), anim="rot", axis="Y", amp=14 * sx, speed=2,
           swim=dict(anim="rot", axis="Y", amp=32 * sx, speed=4, phase=0))
    c.box("Claw" + tag, (0.6, 0.6, 1.0), (sx * 1.6, 0.35, -1.0), (230, 90, 60))
    c.box("Claw" + tag, (0.8, 0.7, 0.7), (sx * 1.7, 0.45, -1.7), (255, 245, 110), mat="n")

c = creature("Bonelord", "Bonelord")
sea_dragon(c, (240, 235, 215), (120, 60, 180), (200, 110, 255), glow=(210, 130, 255), crest="crown", wing="glow",
           tail_end="spike", size=1.2, stars=3, spikes_col=(210, 130, 255))

c = creature("Nightray", "Nightray")
sea_dragon(c, (30, 15, 70), (190, 170, 240), (255, 220, 60), glow=(255, 235, 90), crest="flame", wing="glow",
           tail_end="orb", size=1.2, stars=3, legs4=False, chunky=1.3)

# --- 4 star element legendaries (two Epics of the same element fused) ---------------
c = creature("Tidalord", "Tidalord")
sea_dragon(c, (15, 80, 210), (190, 235, 255), (120, 230, 255), glow=(160, 245, 255), crest="crown", wing="glow",
           tail_end="fin", size=1.35, stars=4, whiskers=True, snout=1.2)

c = creature("ReefColossus", "Reef Colossus")
sea_dragon(c, (220, 70, 110), (255, 215, 225), (130, 240, 180), glow=(255, 170, 215), crest="horns", wing="glow",
           tail_end="spike", size=1.4, stars=4, chunky=1.35, horn=(255, 220, 235))
for (x, z) in ((-0.6, -0.2), (0.6, 0.3), (0.0, 0.8), (-0.4, 1.2)):
    c.box("Body", (0.3, 0.9, 0.3), (x * 1.4, 1.5, z * 1.4), (255, 180, 210), mat="n")

c = creature("Stormwyrm", "Stormwyrm")
sea_dragon(c, (25, 30, 70), (170, 180, 230), (255, 230, 50), glow=(255, 245, 100), crest="flame", wing="glow",
           tail_end="flame", size=1.35, stars=4, whiskers=True, snout=1.3)

c = creature("VoidSerpent", "Void Serpent")
sea_dragon(c, (25, 10, 50), (120, 80, 180), (230, 80, 255), glow=(240, 110, 255), crest="horns", wing="glow",
           tail_end="orb", size=1.35, stars=4, legs4=False, snout=1.4, horn=(230, 220, 250))

# --- 5 star mythics -----------------------------------------------------------------
c = creature("StormEmperor", "Storm Emperor")
sea_dragon(c, (250, 220, 60), (255, 250, 210), (60, 120, 255), glow=(255, 250, 160), crest="crown", wing="glow",
           tail_end="flame", size=1.5, stars=5, whiskers=True)

c = creature("CoralTitan", "Coral Titan")
sea_dragon(c, (255, 110, 150), (255, 235, 240), (255, 230, 60), glow=(255, 190, 220), crest="crown", wing="glow",
           tail_end="spike", size=1.55, stars=5, chunky=1.4)

c = creature("TideSeraph", "Tide Seraph")
sea_dragon(c, (235, 250, 255), (180, 230, 255), (90, 200, 255), glow=(200, 245, 255), crest="crown", wing="glow",
           tail_end="orb", size=1.5, stars=5, whiskers=True, snout=1.1)

# ===========================================================================
# ENEMIES
# ===========================================================================
c = creature("Crab", "Crab", "enemy")
R1, R2 = (220, 50, 40), (170, 30, 30)
c.box("Body", (1.9, 0.9, 1.4), (0, 0.1, 0), R1)
for s in (-1, 1):
    c.box("Body", (0.3, 0.3, 0.3), (s * 0.35, 0.8, -0.5), WHITE)
    c.box("Body", (0.16, 0.18, 0.08), (s * 0.35, 0.8, -0.68), INK)
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Claw" + tag, (s * 0.9, 0.1, -0.4), anim="rot", axis="Y", amp=14 * s, speed=2,
           swim=dict(anim="rot", axis="Y", amp=30 * s, speed=4, phase=0))
    c.box("Claw" + tag, (0.6, 0.55, 0.75), (s * 1.25, 0.2, -0.8), R2)
legs(c, [(-0.8, -0.3, 0.1), (0.8, -0.3, 0.1), (-0.8, -0.3, 0.5), (0.8, -0.3, 0.5)], (0.2, 0.45, 0.2), R2, amp=22)

c = creature("Puffer", "Puffer", "enemy")
PF, PF2 = (255, 200, 60), (255, 240, 180)
c.bone("Puff", (0, 0, 0), anim="rot", axis="Y", amp=10, speed=1)
c.box("Puff", (1.8, 1.7, 1.8), (0, 0.2, 0), PF)
c.box("Puff", (1.5, 0.5, 1.5), (0, -0.55, 0), PF2)
eyes(c, "Puff", 0.45, -0.92, dx=0.42, s=0.34, angry=True)
for (x, y, z, rx, rz) in ((0, 1.15, 0, 0, 0), (0.95, 0.3, 0, 0, -90), (-0.95, 0.3, 0, 0, 90), (0, 0.3, 0.95, 90, 0),
                          (0.7, 0.9, 0.5, 30, -40), (-0.7, 0.9, -0.5, -30, 40)):
    c.box("Puff", (0.18, 0.45, 0.18), (x, y, z), (200, 140, 40), rot=(rx, 0, rz))
fin_pair(c, (0.35, 0.12, 0.35), 0.9, 0.0, 0.0, (255, 160, 40), amp=30, speed=4, parent="Puff")

c = creature("Gull", "Sea Gull", "enemy")
G1, G2 = (250, 250, 250), (170, 180, 195)
c.bones[0].update(anim="move", amp=0.35, speed=1)
c.box("Body", (1.0, 0.9, 1.6), (0, 0.4, 0.1), G1)
c.box("Body", (0.9, 0.8, 0.8), (0, 0.85, -0.7), G1)
c.box("Body", (0.35, 0.25, 0.5), (0, 0.75, -1.3), (255, 190, 40))
eyes(c, "Body", 1.0, -1.12, dx=0.25, s=0.2, angry=True)
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Wing" + tag, (s * 0.5, 0.6, 0.1), anim="rot", axis="Z", amp=35 * s, speed=3)
    c.box("Wing" + tag, (1.4, 0.15, 0.8), (s * 1.2, 0.6, 0.1), G2)

c = creature("Urchin", "Urchin", "enemy")
U1 = (70, 40, 110)
c.bone("Core", (0, 0, 0), anim="spin", axis="Y", amp=0, speed=1)
c.box("Core", (1.5, 1.5, 1.5), (0, 0.3, 0), U1)
for (x, y, z, rx, rz) in ((0, 1.25, 0, 0, 0), (0.9, 0.3, 0, 0, -90), (-0.9, 0.3, 0, 0, 90), (0, 0.3, 0.9, 90, 0),
                          (0, 0.3, -0.9, -90, 0), (0.65, 0.95, 0.65, 35, -35), (-0.65, 0.95, -0.65, -35, 35),
                          (0.65, 0.95, -0.65, -35, -35), (-0.65, 0.95, 0.65, 35, 35)):
    c.box("Core", (0.2, 0.7, 0.2), (x, y, z), (140, 90, 200), rot=(rx, 0, rz))
eyes(c, "Body", 0.35, -0.8, dx=0.3, s=0.3, angry=True)

c = creature("Squid", "Squid", "enemy")
Q1 = (240, 110, 170)
c.bones[0]["amp"] = 0.2
c.box("Body", (1.3, 1.8, 1.3), (0, 1.0, 0), Q1)
c.box("Body", (1.5, 0.5, 0.2), (0, 1.9, 0), Q1, rot=(0, 0, 0))
eyes(c, "Body", 0.6, -0.67, dx=0.3, s=0.3, angry=True)
tentacles(c, 5, 0.4, 0.1, (220, 80, 150), length=3, amp=22)

c = creature("Skelefish", "Skelefish", "enemy")
c.box("Body", (1.0, 1.0, 1.0), (0, 0.3, -0.7), BONE)
eyes(c, "Body", 0.45, -1.22, dx=0.24, s=0.24, glow=(120, 255, 160))
c.box("Body", (0.2, 0.2, 1.6), (0, 0.3, 0.4), BONE)
for z in (0.0, 0.4, 0.8):
    c.box("Body", (0.15, 1.0, 0.12), (0, 0.3, z), BONE)
tail_chain(c, (0, 0.3, 1.2), [((0.2, 0.9, 0.6), BONE, "p")], amp=24)

# ===========================================================================
# BOSSES (scaled up in game)
# ===========================================================================
c = creature("Clawbeard", "Captain Clawbeard", "boss")
c.box("Body", (1.9, 1.0, 1.5), (0, 0.1, 0), R1)
c.box("Body", (1.3, 0.5, 0.15), (0, -0.2, -0.8), (240, 240, 240))  # beard
c.box("Body", (2.1, 0.2, 1.7), (0, 0.75, 0), INK)  # hat brim
c.box("Body", (1.3, 0.6, 1.1), (0, 1.15, 0), INK)
c.box("Body", (0.4, 0.3, 0.05), (0, 1.15, -0.58), WHITE)
eyes(c, "Body", 0.45, -0.77, dx=0.4, s=0.28, angry=True)
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Claw" + tag, (s * 0.9, 0.1, -0.4), anim="rot", axis="Y", amp=14 * s, speed=2,
           swim=dict(anim="rot", axis="Y", amp=35 * s, speed=4, phase=0))
    c.box("Claw" + tag, (0.7, 0.65, 0.9), (s * 1.3, 0.2, -0.85), R2)
legs(c, [(-0.8, -0.35, 0.1), (0.8, -0.35, 0.1), (-0.8, -0.35, 0.5), (0.8, -0.35, 0.5)], (0.2, 0.45, 0.2), R2, amp=22)

c = creature("Hammerjaw", "Hammerjaw", "boss")
H1, H2 = (110, 130, 150), (220, 225, 235)
c.box("Body", (1.4, 1.3, 2.4), (0, 0.2, 0.3), H1)
c.box("Body", (1.1, 0.4, 2.0), (0, -0.4, 0.2), H2)
c.box("Body", (0.25, 1.1, 0.9), (0, 1.25, 0.4), H1, rot=(-25, 0, 0))
c.bone("Jaw", (0, -0.1, -0.7), anim="rot", axis="X", amp=8, speed=2,
       swim=dict(anim="rot", axis="X", amp=24, speed=4, phase=0))
c.box("Jaw", (1.2, 0.35, 0.8), (0, -0.3, -1.2), H2)
c.box("Body", (2.6, 0.6, 0.7), (0, 0.5, -1.2), H1)
for s in (-1, 1):
    c.box("Body", (0.3, 0.3, 0.1), (s * 1.15, 0.55, -1.57), (255, 70, 50), mat="n")
tail_chain(c, (0, 0.2, 1.5), [((0.9, 0.8, 0.8), H1, "p"), ((0.25, 1.4, 0.6), H1, "p")], amp=22)

c = creature("GhostCaptain", "Ghost Captain", "boss")
GH = (130, 255, 190)
c.bones[0]["amp"] = 0.25
c.box("Body", (1.5, 2.0, 1.2), (0, 0.6, 0), GH, mat="g")
c.box("Body", (1.9, 0.2, 1.6), (0, 1.75, 0), INK)
c.box("Body", (1.2, 0.7, 1.0), (0, 2.2, 0), INK)
c.box("Body", (0.4, 0.3, 0.05), (0, 2.2, -0.52), WHITE)
eyes(c, "Body", 1.15, -0.62, dx=0.32, s=0.3, glow=(255, 255, 255))
c.box("Body", (0.6, 0.2, 0.06), (0, 0.65, -0.62), INK)
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Arm" + tag, (s * 0.8, 1.0, 0), anim="rot", axis="Z", amp=16 * s, speed=1,
           swim=dict(anim="rot", axis="X", amp=40, speed=4, phase=0))
    c.box("Arm" + tag, (0.4, 1.2, 0.4), (s * 1.0, 0.5, 0), GH, mat="g")
c.box("ArmR", (0.12, 1.4, 0.12), (1.0, 0.0, -0.5), (200, 200, 210), rot=(70, 0, 0), mat="m")  # cutlass
tentacles(c, 3, 0.35, -0.4, GH, length=2, seg=(0.35, 0.4, 0.35), mat="g")

c = creature("Maw", "Maw, the Abyss King", "boss")
# The Abyss King: a huge, scarred deep-sea serpent-angler rearing out of the water. A spiked
# armoured neck with glowing veins, a massive horned skull with four red eyes, a gaping jaw
# full of jagged fangs and a glowing throat, a lure on a stalk, a beard of tentacles, torn
# side fins. Every jaw, fin, lure and tentacle is its own bone so it never stops moving.
SK, PL, PL2 = (30, 18, 44), (62, 32, 86), (88, 48, 110)       # skin, armour plates
VEIN, EYE, EYE2 = (90, 255, 220), (255, 40, 60), (255, 200, 90)
FANG, GUM, THROAT, SCAR = (240, 230, 200), (150, 20, 55), (255, 70, 120), (120, 90, 140)
c.bones[0].update(amp=0.2)
# coils at the waterline, spiked
c.box("Body", (3.6, 1.2, 3.4), (0, -0.6, 0.6), SK)
c.box("Body", (2.6, 1.0, 2.4), (2.0, -0.75, 1.9), PL, rot=(0, 30, 0))
c.box("Body", (2.2, 0.9, 2.2), (-1.9, -0.8, 1.6), PL, rot=(0, -25, 0))
for (x, z, r) in ((2.0, 1.9, 30), (-1.9, 1.6, -25), (0.2, 1.8, 0)):
    for k in range(3):
        c.box("Body", (0.22, 0.9 - k * 0.15, 0.5), (x - 0.6 + k * 0.6, -0.1, z), PL2, rot=(-25, r, 0))
c.box("Body", (3.0, 0.12, 0.25), (0, -0.3, -0.75), VEIN, mat="n")

# the neck: 6 armoured segments that sway, spikes on the back, glowing veins down the sides
prev, y, z = "Body", 0.0, 0.4
for i in range(6):
    name = "Neck%d" % (i + 1)
    c.bone(name, (0, y, z), parent=prev, anim="rot", axis="X" if i % 2 == 0 else "Z", amp=5 + i,
           speed=1, phase=-i * 0.6, swim=dict(anim="rot", axis="X", amp=9 + i, speed=2, phase=-i * 0.6))
    w = 2.4 - i * 0.14
    c.box(name, (w, 1.05, w * 0.95), (0, y + 0.5, z), SK, rot=(-10 - i * 3, 0, 0))
    c.box(name, (w * 1.05, 0.5, w * 0.7), (0, y + 0.75, z + 0.25), PL if i % 2 == 0 else PL2, rot=(-10 - i * 3, 0, 0))
    c.box(name, (w * 0.6, 0.9, 0.18), (0, y + 0.5, z - w * 0.5), SCAR, rot=(-10 - i * 3, 0, 0))   # belly
    for sx in (-1, 1):
        c.box(name, (0.1, 0.85, 0.12), (sx * (w / 2 + 0.03), y + 0.5, z - 0.1), VEIN, rot=(-10 - i * 3, 0, 0), mat="n")
        c.box(name, (0.2, 0.6 + i * 0.06, 0.45), (sx * (w / 2 + 0.3), y + 0.6, z + 0.35), PL2, rot=(-25, 0, sx * -(40 + i * 4)))
    c.box(name, (0.22, 1.1 - i * 0.05, 0.7), (0, y + 1.25, z + w * 0.45), FANG, rot=(-40, 0, 0))   # back spike
    prev = name
    y += 1.0
    z -= 0.28

# torn side fins at the neck base
for sx, tag in ((-1, "L"), (1, "R")):
    c.bone("Fin" + tag, (sx * 1.2, 1.2, 0.3), parent="Neck2", anim="rot", axis="Z", amp=22 * sx, speed=1,
           swim=dict(anim="rot", axis="Z", amp=40 * sx, speed=3, phase=0))
    for k in range(4):
        c.box("Fin" + tag, (1.4 - k * 0.15, 0.1, 0.5), (sx * (1.9 + k * 0.1), 1.5 + k * 0.32, 0.3 + k * 0.25), PL2 if k % 2 else SK,
              rot=(0, 0, sx * (20 + k * 8)))
    c.box("Fin" + tag, (0.12, 1.6, 0.1), (sx * 2.2, 1.9, 0.2), VEIN, rot=(0, 0, sx * 35), mat="n")

# the skull
c.bone("Head", (0, y, z), parent=prev, anim="rot", axis="Y", amp=12, speed=1,
       swim=dict(anim="rot", axis="X", amp=12, speed=2, phase=0))
hy = y + 0.7
c.box("Head", (3.0, 1.7, 2.4), (0, hy, z - 0.2), SK)
c.box("Head", (2.6, 0.7, 2.6), (0, hy - 0.1, z - 2.3), SK)                  # upper jaw (low, so the eyes show)
c.box("Head", (2.9, 0.5, 2.0), (0, hy + 0.95, z - 0.8), PL)                  # armoured brow plate
c.box("Head", (2.2, 0.3, 1.6), (0, hy + 0.38, z - 2.5), PL2)                 # snout plate
c.box("Head", (2.4, 0.2, 2.4), (0, hy - 0.4, z - 2.3), GUM)                 # upper gums
for (x, zz, rz) in ((-0.9, -0.5, 15), (0.5, -1.9, -20), (1.0, -0.2, 10)):    # scars
    c.box("Head", (0.08, 0.5, 0.06), (x, hy + 0.3, z + zz - 1.21), SCAR, rot=(0, 0, rz))
for sx in (-1, 1):
    # four eyes: two big glowing ones on the front of the snout (seen from below in the
    # cutscene), two small ones on the skull, all under angry brows
    c.box("Head", (0.75, 0.42, 0.14), (sx * 0.75, hy + 0.05, z - 3.64), EYE, mat="n")
    c.box("Head", (0.24, 0.24, 0.1), (sx * 0.72, hy + 0.05, z - 3.73), EYE2, mat="n")
    c.box("Head", (0.85, 0.2, 0.3), (sx * 0.75, hy + 0.36, z - 3.62), INK, rot=(0, 0, sx * -20))
    c.box("Head", (0.36, 0.26, 0.14), (sx * 1.3, hy + 0.5, z - 1.42), EYE, mat="n")
    # horns: three pairs sweeping back
    for k in range(3):
        hx = sx * (1.0 + k * 0.25)
        c.box("Head", (0.32 - k * 0.04, 1.6 - k * 0.3, 0.32 - k * 0.04), (hx, hy + 1.6 - k * 0.2, z + 0.3 + k * 0.5),
              FANG if k == 0 else PL2, rot=(-55 - k * 8, 0, sx * -(25 + k * 12)))
    # upper fangs: two jagged rows
    for k in range(5):
        L = 0.7 if k % 2 == 0 else 0.45
        c.box("Head", (0.18, L, 0.18), (sx * 1.0, hy - 0.45 - L / 2, z - 1.4 - k * 0.48), FANG, rot=(0, 0, sx * 6))
    for k in range(3):
        c.box("Head", (0.13, 0.35, 0.13), (sx * 0.55, hy - 0.55, z - 2.0 - k * 0.5), FANG)
    c.box("Head", (0.2, 0.9, 0.2), (sx * 0.7, hy - 0.8, z - 3.45), FANG, rot=(15, 0, sx * 8))   # front tusks
    c.box("Head", (0.16, 0.1, 0.16), (sx * 0.4, hy + 0.56, z - 3.2), INK)                    # nostrils

# the lure: a stalk off the brow ending in a glowing orb
c.bone("Lure1", (0, hy + 1.2, z - 1.0), parent="Head", anim="rot", axis="X", amp=14, speed=1,
       swim=dict(anim="rot", axis="X", amp=24, speed=2, phase=0))
c.box("Lure1", (0.16, 1.4, 0.16), (0, hy + 1.9, z - 1.2), PL2, rot=(25, 0, 0))
c.bone("Lure2", (0, hy + 2.5, z - 1.55), parent="Lure1", anim="rot", axis="X", amp=20, speed=2, phase=-0.8)
c.box("Lure2", (0.14, 1.0, 0.14), (0, hy + 2.6, z - 1.95), PL2, rot=(55, 0, 0))
c.ball("Lure2", 0.6, (0, hy + 2.35, z - 2.4), VEIN, mat="n")
c.ball("Lure2", 0.3, (0, hy + 2.35, z - 2.62), (255, 255, 255), mat="n")

# the lower jaw: hangs wide open, snaps in battle
c.bone("Jaw", (0, hy - 0.6, z - 0.4), parent="Head", anim="rot", axis="X", amp=10, speed=1,
       swim=dict(anim="rot", axis="X", amp=30, speed=3, phase=0))
c.box("Jaw", (2.4, 0.55, 2.8), (0, hy - 1.15, z - 2.0), SK, rot=(18, 0, 0))
c.box("Jaw", (2.0, 0.2, 2.5), (0, hy - 0.85, z - 2.0), GUM, rot=(18, 0, 0))
c.box("Jaw", (1.4, 0.3, 1.6), (0, hy - 0.95, z - 1.3), THROAT, rot=(18, 0, 0), mat="n")  # glowing throat
for sx in (-1, 1):
    for k in range(5):
        L = 0.6 if k % 2 else 0.4
        c.box("Jaw", (0.17, L, 0.17), (sx * 0.95, hy - 0.7 + L / 2 - k * 0.15, z - 1.2 - k * 0.48), FANG, rot=(18, 0, sx * -6))
    c.box("Jaw", (0.2, 0.8, 0.2), (sx * 0.65, hy - 0.1, z - 3.3), FANG, rot=(18, 0, 0))
c.bone("Tongue", (0, hy - 0.8, z - 1.0), parent="Jaw", anim="rot", axis="Y", amp=18, speed=2)
c.box("Tongue", (0.5, 0.18, 1.6), (0, hy - 0.75, z - 1.9), GUM, rot=(14, 0, 0))
c.box("Tongue", (0.25, 0.18, 0.4), (0.15, hy - 0.6, z - 2.75), GUM, rot=(14, 25, 0))
# a beard of tentacles under the jaw, glowing tips
for i in range(6):
    tx = -1.0 + i * 0.4
    prevT = "Jaw"
    yy = hy - 1.4
    tz = z - 1.4 - abs(i - 2.5) * 0.25
    for j in range(3):
        name = "Beard%d_%d" % (i, j)
        c.bone(name, (tx, yy, tz), parent=prevT, anim="rot", axis="X" if i % 2 == 0 else "Z", amp=18,
               speed=1, phase=i * 0.7 + j * 0.8)
        c.box(name, (0.22 - j * 0.04, 0.55, 0.22 - j * 0.04), (tx, yy - 0.27, tz), VEIN if j == 2 else SK,
              mat="n" if j == 2 else "p")
        yy -= 0.5
        prevT = name


# ===========================================================================
# SHIP FITTINGS (props, kind "prop"): the Ship Workshop's Cannons, Crow's Nest and Lucky
# Figurehead. Same pipeline as the monsters: bones + pieces here -> Blender rig + FBX, and the
# game builds them from the generated shapes. "swim" is the ACTION state: the cannon's recoil
# when it fires, the lookout's frantic scan, the figurehead's roar.
# ===========================================================================
IRON, IRON2, WOODC, WOODD, BRASS = (38, 40, 54), (66, 70, 90), (126, 80, 46), (92, 58, 34), (255, 205, 90)
FLAME = (255, 150, 40)

c = creature("Cannon", "Deck Cannon", "prop")
# barrel points -Z (the way it fires); carriage on two wheels, brass bands, a burning fuse
c.box("Body", (1.6, 0.5, 2.7), (0, 0.6, 0.2), WOODC)
for s in (-1, 1):
    c.box("Body", (0.32, 1.0, 2.3), (s * 0.66, 0.85, 0.15), WOODD)
    for z in (-0.5, 0.9):
        c.box("Body", (0.3, 1.15, 1.15), (s * 1.0, 0.6, z), WOODD)
        c.box("Body", (0.34, 0.45, 0.45), (s * 1.0, 0.6, z), BRASS)
for (x, z) in ((-1.2, 1.7), (-0.8, 1.9), (-1.0, 1.4)):
    c.ball("Body", 0.46, (x, 0.25, z), IRON)
c.bone("Barrel", (0, 1.15, 0.4), parent="Body", anim="move", axis="Z", amp=0.02, speed=1,
       swim=dict(anim="move", axis="Z", amp=0.85, speed=4, phase=0.0))
c.box("Barrel", (1.0, 1.0, 2.9), (0, 1.25, -0.25), IRON)
for z in (-1.45, -0.45, 0.65):
    c.box("Barrel", (1.12, 1.12, 0.2), (0, 1.25, z), BRASS, mat="m")
c.box("Barrel", (1.3, 1.3, 0.34), (0, 1.25, -1.78), IRON2)
c.box("Barrel", (0.6, 0.6, 0.06), (0, 1.25, -1.97), (8, 8, 12))
c.ball("Barrel", (0.55, 0.55, 0.55), (0, 1.25, 1.22), IRON2)
c.bone("Fuse", (0, 1.8, 0.8), parent="Barrel", anim="rot", axis="X", amp=14, speed=2,
       swim=dict(anim="rot", axis="X", amp=30, speed=6, phase=0))
c.box("Fuse", (0.1, 0.5, 0.1), (0, 2.05, 0.8), WOODD)
c.box("Fuse", (0.22, 0.22, 0.22), (0, 2.38, 0.8), FLAME, mat="n")

c = creature("CrowsNest", "Crow's Nest", "prop")
# a round lookout basket high on the mast, a lookout with a swinging spyglass, flag, lantern
c.box("Body", (0.7, 2.4, 0.7), (0, -1.1, 0), WOODD)
c.box("Body", (3.9, 0.4, 3.9), (0, 0.2, 0), WOODC)
for i in range(12):
    a = i / 12 * math.tau
    x, z = math.cos(a) * 1.85, math.sin(a) * 1.85
    c.box("Body", (1.3, 1.5, 0.35), (x, 1.05, z), WOODC if i % 2 == 0 else WOODD, rot=(0, -math.degrees(a) + 90, 0))
for i in range(12):
    a = (i + 0.5) / 12 * math.tau
    c.box("Body", (1.4, 0.2, 0.4), (math.cos(a) * 1.95, 1.85, math.sin(a) * 1.95), BRASS, rot=(0, -math.degrees(a) + 90, 0), mat="m")
c.box("Body", (0.14, 2.6, 0.14), (0, 2.1, 0), WOODD)       # the little flag mast
c.bone("Flag", (0, 3.3, 0), parent="Body", anim="rot", axis="Y", amp=16, speed=2,
       swim=dict(anim="rot", axis="Y", amp=30, speed=4, phase=0))
c.box("Flag", (1.7, 0.95, 0.08), (0.9, 3.3, 0), (230, 55, 60))
c.box("Flag", (0.4, 0.4, 0.1), (0.55, 3.3, 0), WHITE)
c.bone("Lookout", (0, 0.4, 0), parent="Body", anim="move", axis="Y", amp=0.06, speed=2,
       swim=dict(anim="move", axis="Y", amp=0.2, speed=4, phase=0))
c.box("Lookout", (0.8, 1.0, 0.55), (-0.2, 1.0, 0), (50, 110, 210))
c.box("Lookout", (0.62, 0.62, 0.62), (-0.2, 1.75, 0), (255, 215, 170))
c.box("Lookout", (0.95, 0.16, 0.95), (-0.2, 2.15, 0), (210, 50, 55))
c.box("Lookout", (0.6, 0.36, 0.6), (-0.2, 2.4, 0), (210, 50, 55))
c.box("Lookout", (0.12, 0.12, 0.06), (-0.37, 1.8, -0.33), INK)
c.box("Lookout", (0.12, 0.12, 0.06), (-0.03, 1.8, -0.33), INK)
c.bone("Spy", (0.15, 1.45, -0.25), parent="Lookout", anim="rot", axis="Y", amp=40, speed=1,
       swim=dict(anim="rot", axis="Y", amp=70, speed=3, phase=0))
c.box("Spy", (0.26, 0.26, 0.85), (0.15, 1.45, -0.65), (255, 215, 170))
c.box("Spy", (0.24, 0.24, 1.2), (0.15, 1.5, -1.4), BRASS, mat="m")
c.box("Spy", (0.3, 0.3, 0.1), (0.15, 1.5, -2.02), (130, 240, 255), mat="n")
c.bone("Lantern", (-1.55, 2.3, 0), parent="Body", anim="rot", axis="Z", amp=10, speed=1,
       swim=dict(anim="rot", axis="Z", amp=22, speed=3, phase=0))
c.box("Lantern", (0.1, 0.5, 0.1), (-1.55, 2.05, 0), WOODD)
c.box("Lantern", (0.5, 0.62, 0.5), (-1.55, 1.55, 0), (255, 225, 140), mat="n")
c.box("Lantern", (0.62, 0.12, 0.62), (-1.55, 1.9, 0), IRON)

c = creature("Figurehead", "Lucky Figurehead", "prop")
# a golden sea-dragon leaning out from the bow: jaw, whiskers, mane fins, a glowing pearl
GD, GD2, TEAL = (255, 205, 70), (232, 160, 40), (70, 235, 220)
c.box("Body", (1.5, 1.6, 1.6), (0, 0.5, 0.9), GD2)
c.box("Body", (1.35, 1.5, 1.5), (0, 1.3, 0.2), GD, rot=(-18, 0, 0))
c.box("Body", (1.8, 1.7, 2.0), (0, 2.05, -0.9), GD)                  # skull
c.box("Body", (1.25, 0.9, 1.6), (0, 1.85, -2.3), GD)                 # snout
c.box("Body", (1.5, 0.25, 1.3), (0, 2.45, -2.1), GD2)                # nose plate
for s in (-1, 1):
    c.box("Body", (0.34, 0.34, 0.1), (s * 0.55, 2.55, -1.95), TEAL, mat="n")      # eyes
    c.box("Body", (0.5, 0.14, 0.16), (s * 0.55, 2.8, -1.95), IRON, rot=(0, 0, s * -18))
    c.box("Body", (0.3, 1.5, 0.3), (s * 0.7, 3.2, -0.5), GD2, rot=(-35, 0, s * -14))  # horns
    c.box("Body", (0.1, 0.1, 0.1), (s * 0.3, 2.1, -3.12), INK)                        # nostrils
    c.bone("Whisk" + ("L" if s < 0 else "R"), (s * 0.5, 1.9, -2.9), parent="Body", anim="rot", axis="Y", amp=14 * s, speed=2,
           swim=dict(anim="rot", axis="Y", amp=30 * s, speed=4, phase=0))
    c.box("Whisk" + ("L" if s < 0 else "R"), (0.12, 0.12, 1.5), (s * 0.7, 1.8, -3.5), TEAL, rot=(0, s * 20, 0), mat="n")
for k in range(3):
    c.bone("Mane%d" % (k + 1), (0, 3.0 - k * 0.5, 0.2 + k * 0.3), parent="Body", anim="rot", axis="X", amp=8, speed=1,
           phase=-k * 0.9, swim=dict(anim="rot", axis="X", amp=18, speed=3, phase=-k * 0.9))
    c.box("Mane%d" % (k + 1), (0.2, 1.1 - k * 0.15, 0.7), (0, 3.2 - k * 0.5, 0.35 + k * 0.45), TEAL, rot=(-30, 0, 0), mat="n")
c.bone("Jaw", (0, 1.5, -1.8), parent="Body", anim="rot", axis="X", amp=5, speed=1,
       swim=dict(anim="rot", axis="X", amp=26, speed=3, phase=0))
c.box("Jaw", (1.0, 0.4, 1.7), (0, 1.35, -2.4), GD2)
c.box("Jaw", (0.8, 0.12, 1.4), (0, 1.58, -2.4), (190, 40, 60))
for k in range(3):
    for s in (-1, 1):
        c.box("Jaw", (0.12, 0.3, 0.12), (s * 0.4, 1.75, -1.9 - k * 0.4), WHITE)
c.ball("Jaw", (0.8, 0.8, 0.8), (0, 1.8, -2.45), (255, 235, 245), mat="n")           # the lucky pearl


# ---------------------------------------------------------------------------
# Swim cycle defaults: faster, bigger version of the idle unless a bone overrides it
# ---------------------------------------------------------------------------
def finish():
    for cr in CREATURES:
        for b in cr.bones:
            if b["swim"] is None:
                if b["anim"] == "move":
                    b["swim"] = dict(anim="move", axis=b["axis"], amp=b["amp"] * 1.4, speed=2, phase=b["phase"])
                elif b["anim"] == "rot":
                    b["swim"] = dict(anim="rot", axis=b["axis"], amp=b["amp"] * 1.7, speed=b["speed"] * 2,
                                     phase=b["phase"])
                elif b["anim"] == "spin":
                    b["swim"] = dict(anim="spin", axis=b["axis"], amp=0, speed=b["speed"] * 2, phase=0)
                else:
                    b["swim"] = dict(anim=None, axis="X", amp=0, speed=1, phase=0)


finish()


# ---------------------------------------------------------------------------
# Luau export
# ---------------------------------------------------------------------------
def f(v):
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def v3(t):
    return "Vector3.new(%s, %s, %s)" % (f(t[0]), f(t[1]), f(t[2]))


def write_luau(path=OUT_LUAU):
    axes = {"X": "Vector3.xAxis", "Y": "Vector3.yAxis", "Z": "Vector3.zAxis"}
    L = [
        "--!strict",
        "-- GENERATED by assets/monsters/spec.py. Do not edit by hand.",
        "-- Every monster, enemy and boss as voxel blocks: bones (pivot + idle motion + swim motion)",
        "-- and pieces. Piece kinds: B box, S ellipsoid. Materials: p plastic, n neon, g glass, m metal.",
        "-- Roblox space, face looks -Z. Bone anim: rot = sine swing of amp degrees about axis;",
        "-- spin = speed turns per loop; move = sine bob of amp studs. speed = cycles per LOOP seconds.",
        "",
        "export type Motion = { anim: string?, axis: Vector3, amp: number, speed: number, phase: number }",
        "export type Bone = { name: string, parent: number, pivot: Vector3, anim: string?, axis: Vector3, amp: number, speed: number, phase: number, swim: Motion }",
        "export type Piece = { b: number, k: string, s: Vector3, p: Vector3, r: Vector3, c: Color3, m: string }",
        "export type Shape = { name: string, kind: string, bones: { Bone }, pieces: { Piece } }",
        "",
        "local Shapes: { LOOP: number, all: { [string]: Shape } } = {",
        "\tLOOP = %s," % f(LOOP),
        "\tall = {",
    ]
    for cr in CREATURES:
        idx = {b["name"]: i + 1 for i, b in enumerate(cr.bones)}
        L.append("\t\t%s = {" % cr.id)
        L.append('\t\t\tname = "%s",' % cr.name)
        L.append('\t\t\tkind = "%s",' % cr.kind)
        L.append("\t\t\tbones = {")
        for b in cr.bones:
            w = b["swim"]
            swim = "{ anim = %s, axis = %s, amp = %s, speed = %s, phase = %s }" % (
                ('"%s"' % w["anim"]) if w["anim"] else "nil", axes[w["axis"]], f(w["amp"]), f(w["speed"]), f(w["phase"]))
            L.append('\t\t\t\t{ name = "%s", parent = %d, pivot = %s, anim = %s, axis = %s, amp = %s, speed = %s, phase = %s, swim = %s },' % (
                b["name"], idx[b["parent"]] if b["parent"] else 0, v3(b["pivot"]),
                ('"%s"' % b["anim"]) if b["anim"] else "nil", axes[b["axis"]], f(b["amp"]), f(b["speed"]),
                f(b["phase"]), swim))
        L.append("\t\t\t},")
        L.append("\t\t\tpieces = {")
        for pc in cr.pieces:
            L.append('\t\t\t\t{ b = %d, k = "%s", s = %s, p = %s, r = %s, c = Color3.fromRGB(%d, %d, %d), m = "%s" },' % (
                idx[pc["bone"]], pc["kind"], v3(pc["size"]), v3(pc["pos"]), v3(pc["rot"]),
                pc["color"][0], pc["color"][1], pc["color"][2], pc["mat"]))
        L.append("\t\t\t},")
        L.append("\t\t},")
    L += ["\t},", "}", "", "return Shapes", ""]
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(L))
    return path


if __name__ == "__main__":
    p = write_luau()
    print("wrote", p, "creatures:", len(CREATURES), "pieces:", sum(len(c.pieces) for c in CREATURES))
