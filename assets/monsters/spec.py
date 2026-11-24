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
            c.box(bone, (s * 1.1, 0.09, 0.08), (side * dx, y + s * 0.62, z - 0.05), INK, rot=(0, 0, side * 18))


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
# MONSTERS (player side). Every element line is its own kind of sea creature
# (see the roster below); sea_dragon stays for a few legendary true dragons.
# Rarity (stars) adds size and detail: glowing accents, 4* a spinning halo,
# 5* orbiting orbs as well.
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





# ---------------------------------------------------------------------------
# 6 STAR DIVINE: the Tide Sovereign (Abyss Rod only) and the Eternal Sovereign (two Tide
# Sovereigns fused). Its own build, nothing like the other dragons: a crouching beast on four
# wide-splayed clawed legs, a deep chest with a long plated belly running up an S-curved neck to a
# crowned head with an open, fanged jaw and glowing eyes, a spiked tail curling up behind, and
# giant bat wings sweeping up and out.
# ---------------------------------------------------------------------------
def sovereign(c, size, evolved=False):
    k = K(c, size)
    if evolved:
        body, plate, dark, horn = (24, 28, 82), (120, 80, 200), (14, 16, 50), (255, 200, 120)
        glow, mem, mem2, crownc, spike = (255, 150, 60), (60, 30, 110), (255, 90, 40), (255, 120, 40), (255, 110, 40)
    else:
        body, plate, dark, horn = (35, 95, 230), (120, 190, 255), (22, 60, 170), (215, 235, 255)
        glow, mem, mem2, crownc, spike = (190, 245, 255), (110, 175, 255), (70, 130, 240), (255, 205, 60), (25, 70, 200)
    cm = "n" if evolved else "p"
    first_piece = len(c.pieces)
    # it never touches down: the body bobs up on every downstroke of the wings (phase -pi/2 = highest
    # while the wings sweep down through level)
    c.bones[0].update(amp=0.22, speed=1, phase=-math.pi / 2,
                      swim=dict(anim="move", axis="Y", amp=0.3, speed=2, phase=-math.pi / 2))
    # body: a deep barrel with the chest raised at the front, the belly plate running up the chest
    k.box("Body", (2.0, 1.5, 2.5), (0, 0.9, 0.45), body)
    k.box("Body", (1.8, 1.9, 1.1), (0, 1.55, -0.65), body, rot=(-18, 0, 0))
    k.box("Body", (1.2, 0.3, 2.2), (0, 0.17, 0.4), plate)
    for i in range(4):
        k.box("Body", (1.15 - i * 0.06, 0.42, 0.14), (0, 0.85 + i * 0.42, -1.12 - i * 0.14), plate, rot=(-18, 0, 0))
    if evolved:
        for (x, y, r) in ((-0.4, 1.2, 30), (0.35, 1.8, -25)):
            k.box("Body", (0.08, 0.55, 0.06), (x, y, -1.3), glow, rot=(-18, 0, r), mat="n")
    # spine blades
    for i, z in enumerate((-0.6, -0.1, 0.4, 0.9, 1.4)):
        h = 0.7 - abs(i - 2) * 0.1
        k.box("Body", (0.2, h, 0.45), (0, 1.75 + h / 2 - 0.1 - i * 0.08, z), spike, rot=(-25, 0, 0))
    # S-curved neck in two bones, belly plates up the front, blades down the back
    k.bone("Neck1", (0, 2.2, -0.9), anim="rot", axis="X", amp=3, speed=1,
           swim=dict(anim="rot", axis="X", amp=7, speed=2, phase=0))
    k.box("Neck1", (1.0, 1.15, 0.95), (0, 2.65, -1.0), body, rot=(-15, 0, 0))
    k.box("Neck1", (0.7, 1.0, 0.1), (0, 2.62, -1.5), plate, rot=(-15, 0, 0))
    k.box("Neck1", (0.16, 0.5, 0.4), (0, 3.05, -0.55), spike, rot=(-30, 0, 0))
    k.bone("Neck2", (0, 3.1, -1.1), parent="Neck1", anim="rot", axis="X", amp=3, speed=1, phase=-0.6,
           swim=dict(anim="rot", axis="X", amp=7, speed=2, phase=-0.6))
    k.box("Neck2", (0.9, 1.0, 0.85), (0, 3.5, -1.05), body)
    k.box("Neck2", (0.62, 0.9, 0.1), (0, 3.5, -1.5), plate)
    k.box("Neck2", (0.15, 0.45, 0.4), (0, 3.9, -0.7), spike, rot=(-35, 0, 0))
    # head: long snout, open fanged jaw, glowing eyes under a scowl, cheek frills, horns, crown
    k.bone("Head", (0, 3.95, -1.1), parent="Neck2", anim="rot", axis="X", amp=4, speed=1, phase=-1.2,
           swim=dict(anim="rot", axis="X", amp=9, speed=2, phase=-1.2))
    k.box("Head", (1.25, 1.0, 1.2), (0, 4.35, -1.35), body)
    k.box("Head", (0.95, 0.55, 1.05), (0, 4.32, -2.35), body)
    k.box("Head", (0.85, 0.35, 0.75), (0, 3.92, -2.15), (40, 10, 30))
    for x in (-0.33, -0.11, 0.11, 0.33):
        k.box("Head", (0.13, 0.42, 0.13), (x, 3.9, -2.72), WHITE)
    for sx in (-1, 1):
        k.box("Head", (0.12, 0.1, 0.06), (sx * 0.22, 4.5, -2.88), (20, 20, 30))
        k.box("Head", (0.36, 0.22, 0.06), (sx * 0.4, 4.62, -1.97), glow, mat="n")
        k.box("Head", (0.52, 0.13, 0.12), (sx * 0.4, 4.79, -1.99), (16, 18, 40), rot=(0, 0, sx * 22))
        k.box("Head", (0.12, 0.6, 0.65), (sx * 0.68, 4.35, -1.1), spike, rot=(0, sx * 25, 0))
        for j in range(3):
            k.box("Head", (0.12, 0.42, 0.12), (sx * (0.72 + j * 0.08), 4.0 + j * 0.25, -0.75 + j * 0.1), spike,
                  rot=(0, 0, -sx * (40 + j * 10)))
        k.box("Head", (0.2, 0.75, 0.2), (sx * 0.42, 5.05, -0.75), horn, rot=(-45, 0, -sx * 18))
    k.bone("Jaw", (0, 4.0, -1.6), parent="Head", anim="rot", axis="X", amp=4, speed=1,
           swim=dict(anim="rot", axis="X", amp=16, speed=4, phase=0))
    k.box("Jaw", (0.85, 0.3, 1.05), (0, 3.55, -2.2), plate, rot=(18, 0, 0))
    for x in (-0.3, 0.3):
        k.box("Jaw", (0.12, 0.36, 0.12), (x, 3.78, -2.6), WHITE)
    k.box("Head", (1.05, 0.2, 0.9), (0, 4.95, -1.3), crownc, mat=cm)
    for i, x in enumerate((-0.42, -0.21, 0.0, 0.21, 0.42)):
        h = 0.62 if i == 2 else (0.5 if i in (1, 3) else 0.4)
        k.box("Head", (0.18, h, 0.18), (x, 5.05 + h / 2, -1.7), crownc, mat=cm)
        if evolved:
            k.box("Head", (0.13, 0.3, 0.13), (x, 5.15 + h, -1.7), (255, 230, 120), mat="n")
    k.box("Head", (0.24, 0.24, 0.08), (0, 4.95, -1.78), glow, rot=(0, 0, 45), mat="n")
    if evolved:
        k.box("Head", (0.18, 0.18, 0.45), (0, 4.45, -3.05), glow, mat="n")
    # four wide-splayed clawed legs: front legs bent outward, big haunches behind
    for sx, t in SIDES:
        ph = 0 if sx < 0 else math.pi
        n = "LegF" + t
        k.bone(n, (sx * 0.95, 1.2, -0.6), anim="rot", axis="X", amp=5, speed=1, phase=ph,
               swim=dict(anim="rot", axis="X", amp=16, speed=2, phase=ph))
        k.box(n, (0.62, 1.15, 0.65), (sx * 1.25, 0.75, -0.75), body, rot=(0, 0, sx * 22))
        k.box(n, (0.58, 0.8, 0.6), (sx * 1.5, 0.05, -0.95), body)
        k.box(n, (0.85, 0.3, 0.95), (sx * 1.55, -0.42, -1.15), dark)
        for cx in (-0.25, 0.0, 0.25):
            k.box(n, (0.13, 0.16, 0.3), (sx * 1.55 + cx, -0.48, -1.7), WHITE)
        n = "LegB" + t
        k.bone(n, (sx * 1.0, 1.0, 1.0), anim="rot", axis="X", amp=5, speed=1, phase=ph + math.pi,
               swim=dict(anim="rot", axis="X", amp=16, speed=2, phase=ph + math.pi))
        k.box(n, (0.9, 1.25, 1.25), (sx * 1.3, 0.62, 1.0), body)
        k.box(n, (0.56, 0.75, 0.6), (sx * 1.4, -0.05, 0.6), body)
        k.box(n, (0.9, 0.3, 1.1), (sx * 1.45, -0.42, 0.3), dark)
        for cx in (-0.25, 0.0, 0.25):
            k.box(n, (0.13, 0.16, 0.3), (sx * 1.45 + cx, -0.48, -0.3), WHITE)
    # the tail curls up behind, spiked all the way
    tail = [((0, 0.9, 1.6), (0.9, 0.8, 0.95), (0, 0.95, 2.0), 0), ((0, 1.0, 2.4), (0.7, 0.65, 0.85), (0, 1.2, 2.75), -15),
            ((0, 1.35, 3.1), (0.55, 0.5, 0.8), (0, 1.7, 3.35), -40), ((0, 2.0, 3.55), (0.4, 0.4, 0.7), (0, 2.4, 3.65), -65)]
    prev = "Body"
    for i, (piv, sz, pos, rx) in enumerate(tail):
        n = "Tail%d" % (i + 1)
        k.bone(n, piv, parent=prev, anim="rot", axis="Y", amp=8, speed=1, phase=-i * 0.8)
        k.box(n, sz, pos, body, rot=(rx, 0, 0))
        k.box(n, (0.14, 0.45, 0.35), (0, pos[1] + sz[1] / 2 + 0.12, pos[2] + 0.1), spike, rot=(rx + 30, 0, 0))
        if evolved:
            k.box(n, (0.18, 0.25, 0.2), (0, pos[1] + sz[1] / 2 + 0.38, pos[2] + 0.2), glow, mat="n")
        prev = n
    k.box("Tail4", (0.5, 0.12, 0.6), (0, 2.85, 3.7), spike, rot=(-65, 45, 0))
    # giant bat wings, one bone a side so the whole wing flaps as a piece. Drawn in the wing's plane
    # (x out from the body, y up): a thick stepped arm from the shoulder up to the wrist and on out to
    # a clawed tip, three finger bones fanning down from the wrist, and the membrane filled in voxel
    # rows between them, its trailing edge scalloped up between the finger tips.
    S, W, T = (0.8, 2.0), (3.3, 4.3), (6.7, 3.3)
    F = [(5.9, 1.5), (4.5, 0.55), (2.9, 0.45)]
    B = (1.0, 1.1)
    edge = [S, W, T, (6.0, 2.55), F[0], (5.05, 1.4), F[1], (3.65, 0.95), F[2], (2.0, 1.1), B]
    zm = 0.38
    rows = []
    ys = [y for _, y in edge]
    y = min(ys) + 0.15
    while y < max(ys):
        xs = []
        for i in range(len(edge)):
            (x1, y1), (x2, y2) = edge[i], edge[(i + 1) % len(edge)]
            if (y1 <= y < y2) or (y2 <= y < y1):
                xs.append(x1 + (y - y1) / (y2 - y1) * (x2 - x1))
        xs.sort()
        for j in range(0, len(xs) - 1, 2):
            if xs[j + 1] - xs[j] > 0.12:
                rows.append((xs[j], xs[j + 1], y))
        y += 0.3

    def spar(bone, p0, p1, thick, col, sx):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(dx, dy)
        ang = math.degrees(math.atan2(dy, dx))
        k.box(bone, (ln + thick * 0.6, thick, thick), (sx * (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0.25), col,
              rot=(0, 0, sx * ang))

    for sx, t in SIDES:
        n = "Wing" + t
        k.bone(n, (sx * S[0], S[1], 0.2), anim="rot", axis="Z", amp=16 * sx, speed=1,
               swim=dict(anim="rot", axis="Z", amp=24 * sx, speed=2, phase=0))
        for i, (x1, x2, yy) in enumerate(rows):
            col = mem if i % 2 == 0 else lighten(mem, 0.12)
            k.box(n, (x2 - x1, 0.32, 0.1), (sx * (x1 + x2) / 2, yy, zm), col)
        spar(n, S, W, 0.42, body, sx)
        spar(n, W, T, 0.34, body, sx)
        for f in F:
            spar(n, W, f, 0.16, dark, sx)
        k.box(n, (0.5, 0.5, 0.5), (sx * W[0], W[1], 0.25), dark, rot=(0, 0, 45))
        k.box(n, (0.2, 0.7, 0.2), (sx * (T[0] + 0.2), T[1] + 0.25, 0.25), horn, rot=(0, 0, sx * 70))
        k.box(n, (0.16, 0.45, 0.16), (sx * (W[0] - 0.05), W[1] + 0.4, 0.25), horn, rot=(0, 0, sx * -20))
        if evolved:
            for f in F:
                k.box(n, (0.2, 0.2, 0.2), (sx * f[0], f[1], zm), glow, mat="n")
            spar(n, W, T, 0.12, glow, sx)
    # hover: lift every piece and pivot so its lowest claw floats HOVER units above its origin (the
    # game stands a monster with its lowest piece on the nest / sea, so this keeps it in the air)
    HOVER = 2.2
    lift = HOVER * size
    for pc in c.pieces[first_piece:]:
        x, y, z = pc["pos"]
        pc["pos"] = (x, y + lift, z)
    for b in c.bones[1:]:
        x, y, z = b["pivot"]
        b["pivot"] = (x, y + lift, z)


# ---------------------------------------------------------------------------
# Creature kits. Every element line is a different kind of sea creature, so a
# deck full of monsters reads as a zoo, not a row of dragons. Each kit works in
# "units" (K scales every size / position / pivot by the creature's size) and
# leaves rarity to k_rarity: 4* gets a spinning halo, 5* orbiting orbs as well.
# ---------------------------------------------------------------------------
SIDES = ((-1, "L"), (1, "R"))
GOLDC = (255, 210, 70)
BLUSH = (255, 150, 180)
MOUTH = (190, 50, 80)


def lighten(col, t=0.35):
    return tuple(int(v + (255 - v) * t) for v in col)


def darken(col, t=0.3):
    return tuple(int(v * (1 - t)) for v in col)


class K:
    """Scaled builder: sizes, positions and pivots are in units of the creature's size."""

    def __init__(self, c, s):
        self.c, self.s = c, s

    def _m(self, v):
        return tuple(x * self.s for x in v)

    def box(self, bone, size, pos, color, rot=(0, 0, 0), mat="p"):
        self.c.box(bone, self._m(size), self._m(pos), color, rot=rot, mat=mat)

    def ball(self, bone, size, pos, color, mat="p"):
        if isinstance(size, (int, float)):
            size = (size, size, size)
        self.c.ball(bone, self._m(size), self._m(pos), color, mat=mat)

    def bone(self, name, pivot, **kw):
        self.c.bone(name, self._m(pivot), **kw)

    def bob(self, amp):
        self.c.bones[0]["amp"] = amp


def k_eyes(k, bone, y, z, dx, s=0.34, brow=INK, glow=None):
    """Mean toy eyes on a face plane at z (face looks -Z): a squinting white with a small hard pupil
    (or a glowing slit), and a thick scowling brow slanting down to the middle."""
    for sx in (-1, 1):
        x = sx * dx
        if glow:
            k.box(bone, (s, s * 0.6, 0.08), (x, y, z - 0.02), glow, mat="n")
        else:
            k.box(bone, (s, s * 0.8, 0.08), (x, y, z - 0.02), WHITE)
            k.box(bone, (s * 0.4, s * 0.55, 0.06), (x - sx * s * 0.12, y - s * 0.08, z - 0.07), INK)
            k.box(bone, (s * 0.16, s * 0.16, 0.05), (x - sx * s * 0.05, y + s * 0.06, z - 0.1), WHITE, mat="n")
        if brow:
            k.box(bone, (s * 1.35, 0.13, 0.1), (x, y + s * 0.42, z - 0.06), brow, rot=(0, 0, sx * 22))


def k_smile(k, bone, y, z, w, blush=None, bx=None):
    """A snarl: a hard mouth line with turned-down corners and fangs (blush is ignored: nothing cute)."""
    k.box(bone, (w, 0.08, 0.05), (0, y, z - 0.02), INK)
    for sx in (-1, 1):
        k.box(bone, (0.08, 0.14, 0.05), (sx * w / 2, y - 0.05, z - 0.02), INK)
        for f in ((0.28,) if w < 0.5 else (0.14, 0.34)):
            k.box(bone, (0.08, 0.15, 0.05), (sx * w * f, y - 0.1, z - 0.03), WHITE)


def k_spines(k, bone, zs, y, color, h=0.4, x=0.0, lean=-25, tip=None):
    """A row of sharp spines along a back (z positions), leaning back, optional glowing tips."""
    for i, z in enumerate(zs):
        hh = h * (0.75 + 0.25 * math.sin(i / max(1, len(zs) - 1) * math.pi))
        k.box(bone, (0.14, hh, 0.22), (x, y + hh / 2 - 0.05, z), color, rot=(lean, 0, 0))
        if tip:
            k.box(bone, (0.1, 0.12, 0.1), (x, y + hh - 0.05, z + 0.08), tip, mat="n")


def k_legs(k, spots, size, col, foot=None, amp=10, speed=1, prefix="Leg"):
    for i, (x, y, z) in enumerate(spots):
        n = "%s%d" % (prefix, i + 1)
        ph = 0 if i % 2 == 0 else math.pi
        k.bone(n, (x, y, z), anim="rot", axis="X", amp=amp, speed=speed, phase=ph,
               swim=dict(anim="rot", axis="X", amp=amp * 2.5, speed=speed * 2, phase=ph))
        k.box(n, size, (x, y - size[1] / 2, z), col)
        if foot:
            k.box(n, (size[0] + 0.08, 0.12, size[2] + 0.14), (x, y - size[1] - 0.03, z - 0.05), foot)


def k_tail(k, start, segs, axis="Y", amp=14, speed=1, parent="Body", prefix="Tail", lag=0.9):
    """Phase-lagged chain along +Z. segs: (size, color, mat). Returns [(bone, z centre, size)], end z."""
    x, y, z = start
    prev, out = parent, []
    for i, (size, col, mat) in enumerate(segs):
        n = "%s%d" % (prefix, i + 1)
        k.bone(n, (x, y, z), parent=prev, anim="rot", axis=axis, amp=amp, speed=speed, phase=-i * lag)
        k.box(n, size, (x, y, z + size[2] / 2), col, mat=mat)
        out.append((n, z + size[2] / 2, size))
        z += size[2] * 0.92
        prev = n
    return out, z


def k_arm(k, name, base, d, nseg, seg, col, tip=None, out=0.3, down=0.3, amp=14, phase=0.0, tipmat="p"):
    """A tentacle stepping out along d (x, z) and down, one bone per segment."""
    x, y, z = base
    prev = "Body"
    ax = "X" if abs(d[1]) > abs(d[0]) else "Z"
    for j in range(nseg):
        n = "%s_%d" % (name, j)
        k.bone(n, (x, y, z), parent=prev, anim="rot", axis=ax, amp=amp, speed=1, phase=phase + j * 0.8)
        nx, ny, nz = x + d[0] * out, y - down, z + d[1] * out
        last = j == nseg - 1
        k.box(n, seg, ((x + nx) / 2, (y + ny) / 2, (z + nz) / 2), tip if (tip and last) else col,
              mat=tipmat if (tip and last) else "p")
        x, y, z, prev = nx, ny, nz, n
    return (x, y, z), prev


def k_rarity(k, stars, glow, top, z=0.0, orbit_y=None, orbit_r=1.8):
    col = glow or GOLDC
    if stars >= 4:
        k.bone("Halo", (0, top + 0.4, z), anim="spin", axis="Y", amp=0, speed=1)
        for i in range(6):
            a = i / 6 * math.tau
            k.box("Halo", (0.22, 0.1, 0.22), (math.cos(a) * 0.55, top + 0.4, z + math.sin(a) * 0.55), col, mat="n")
    if stars >= 5:
        oy = orbit_y if orbit_y is not None else top * 0.45
        k.bone("Orbit", (0, oy, z), anim="spin", axis="Y", amp=0, speed=1)
        for i in range(3):
            a = i / 3 * math.tau
            k.ball("Orbit", 0.32, (math.cos(a) * orbit_r, oy, z + math.sin(a) * orbit_r), col, mat="n")


# --- the kits -------------------------------------------------------------------------
def axolotl(c, s, stars, body, gill, belly, accent, glow=None):
    """A wide-faced axolotl with three waving gill fronds a side and a finned tail."""
    k = K(c, s)
    k.box("Body", (1.4, 1.0, 2.0), (0, 0, 0.3), body)
    k.box("Body", (1.15, 0.22, 1.8), (0, -0.5, 0.3), belly)
    k_spines(k, "Body", (-0.35, 0.0, 0.35, 0.7, 1.05), 0.5, accent, h=0.45, tip=glow)
    for (x, z) in ((-0.4, 0.0), (0.45, 0.55), (-0.2, 0.95)):
        k.box("Body", (0.25, 0.06, 0.25), (x, 0.52, z), lighten(body, 0.3))
    k.bone("Head", (0, 0.1, -0.6), anim="rot", axis="X", amp=5, speed=1,
           swim=dict(anim="rot", axis="X", amp=10, speed=2, phase=0))
    k.box("Head", (1.9, 1.2, 1.3), (0, 0.35, -1.25), body)
    k.box("Head", (1.6, 0.25, 1.1), (0, -0.25, -1.3), belly)
    k_eyes(k, "Head", 0.55, -1.9, 0.5, 0.36)
    k_smile(k, "Head", 0.08, -1.9, 0.6, blush=BLUSH, bx=0.72)
    tipc = glow or lighten(gill, 0.35)
    for sx, t in SIDES:
        for g in range(3):
            n = "Gill%s%d" % (t, g + 1)
            th = -25 + g * 40
            r = math.radians(th)
            px, py, pz = sx * 0.92, 0.25 + g * 0.3, -1.05
            k.bone(n, (px, py, pz), parent="Head", anim="rot", axis="Z", amp=12 * sx, speed=1, phase=g * 0.8,
                   swim=dict(anim="rot", axis="Z", amp=26 * sx, speed=2, phase=g * 0.8))
            k.box(n, (0.75, 0.15, 0.15), (px + sx * math.cos(r) * 0.37, py + math.sin(r) * 0.37, pz), gill,
                  rot=(0, 0, sx * th))
            for f in (0.42, 0.68):
                k.box(n, (0.12, 0.28, 0.12), (px + sx * math.cos(r) * f, py + math.sin(r) * f + 0.12, pz), tipc,
                      rot=(0, 0, sx * th), mat="n" if glow else "p")
    k_legs(k, [(-0.6, -0.45, -0.15), (0.6, -0.45, -0.15), (-0.6, -0.45, 0.85), (0.6, -0.45, 0.85)],
           (0.3, 0.42, 0.3), body, foot=belly)
    segs = [((0.85, 0.8, 0.8), body, "p"), ((0.6, 0.65, 0.75), body, "p"), ((0.38, 0.5, 0.7), body, "p")]
    out, _ = k_tail(k, (0, 0.05, 1.25), segs, amp=16)
    for n, zc, sz in out:
        k.box(n, (0.08, sz[1] + 0.4, sz[2] * 0.95), (0, 0.05, zc), accent)
    k_rarity(k, stars, glow, 1.4, z=-1.0)


def starfish(c, s, stars, body, spot, accent, glow=None):
    """A five-armed star standing on two arms, waving the other three."""
    k = K(c, s)
    cy = 0.25
    k.box("Body", (1.2, 1.2, 0.6), (0, cy, 0), body)
    for i, a in enumerate((90, 18, 162, -54, 234)):
        r = math.radians(a)
        dx, dy = math.cos(r), math.sin(r)
        n = "Arm%d" % (i + 1)
        if i < 3:
            k.bone(n, (dx * 0.45, cy + dy * 0.45, 0), anim="rot", axis="Z", amp=6 if i == 0 else 12, speed=1,
                   phase=i * 1.1)
        else:
            ph = 0 if i == 3 else math.pi
            k.bone(n, (dx * 0.45, cy + dy * 0.45, 0), anim="rot", axis="X", amp=14, speed=1, phase=ph,
                   swim=dict(anim="rot", axis="X", amp=30, speed=2, phase=ph))
        k.box(n, (0.62, 0.8, 0.5), (dx * 0.85, cy + dy * 0.85, 0), body, rot=(0, 0, a - 90))
        k.box(n, (0.42, 0.45, 0.42), (dx * 1.35, cy + dy * 1.35, 0), lighten(body, 0.2), rot=(0, 0, a - 90))
        k.box(n, (0.16, 0.16, 0.06), (dx * 0.95, cy + dy * 0.95, -0.27), spot)
        k.box(n, (0.12, 0.12, 0.06), (dx * 1.3, cy + dy * 1.3, -0.23), spot)
        k.box(n, (0.1, 0.1, 0.3), (dx * 1.12, cy + dy * 1.12, -0.35), WHITE)
        k.box(n, (0.18, 0.18, 0.18), (dx * 1.62, cy + dy * 1.62, 0), darken(body, 0.25), rot=(0, 0, a - 45))
    k_eyes(k, "Body", 0.42, -0.3, 0.24, 0.3)
    k_smile(k, "Body", 0.06, -0.3, 0.32, blush=BLUSH, bx=0.42)
    # a little coral sprig growing on the top arm
    k.box("Arm1", (0.12, 0.4, 0.12), (0, cy + 1.75, 0), accent)
    k.box("Arm1", (0.1, 0.28, 0.1), (0.14, cy + 1.82, 0), accent, rot=(0, 0, -35))
    k.box("Arm1", (0.16, 0.16, 0.16), (0, cy + 1.98, 0), glow or lighten(accent, 0.4), mat="n" if glow else "p")
    k_rarity(k, stars, glow, 2.2)


def jellyfish(c, s, stars, bell, core, tent, glow):
    """A see-through bell with a glowing core and zig-zag lightning tentacles."""
    k = K(c, s)
    k.bob(0.18)
    k.box("Body", (1.9, 0.9, 1.9), (0, 0.85, 0), bell, mat="g")
    k.box("Body", (1.45, 0.4, 1.45), (0, 1.45, 0), bell, mat="g")
    k.box("Body", (0.85, 0.22, 0.85), (0, 1.73, 0), bell, mat="g")
    k.box("Body", (2.15, 0.2, 2.15), (0, 0.38, 0), lighten(bell, 0.3))
    k.ball("Body", 0.95, (0, 0.95, 0), core, mat="n")
    for i in range(10):
        a = i / 10 * math.tau
        k.box("Body", (0.12, 0.32, 0.12), (math.cos(a) * 1.0, 0.18, math.sin(a) * 1.0), darken(tent, 0.15))
    k_eyes(k, "Body", 0.85, -0.97, 0.42, 0.34)
    k_smile(k, "Body", 0.55, -0.97, 0.3, blush=BLUSH, bx=0.62)
    for i in range(6):
        a = i / 6 * math.tau + 0.5
        x, z = math.cos(a) * 0.65, math.sin(a) * 0.65
        prev, y = "Body", 0.3
        for j in range(3):
            n = "Ten%d_%d" % (i, j)
            k.bone(n, (x, y, z), parent=prev, anim="rot", axis="X" if i % 2 == 0 else "Z", amp=16, speed=1,
                   phase=i * 0.7 + j * 0.8)
            last = j == 2
            k.box(n, (0.16, 0.45, 0.16), (x, y - 0.22, z), glow if last else tent, rot=(0, 0, 20 if j % 2 == 0 else -20),
                  mat="n" if last else "p")
            y -= 0.4
            prev = n
    k.bone("Frill", (0, 0.3, 0), anim="rot", axis="Y", amp=20, speed=1)
    for i in range(4):
        a = i / 4 * math.tau
        k.box("Frill", (0.2, 0.8, 0.2), (math.cos(a) * 0.22, -0.05, math.sin(a) * 0.22), lighten(tent, 0.4))
    # a little lightning bolt on top of the bell
    k.box("Body", (0.15, 0.35, 0.12), (0.05, 1.98, 0), glow, rot=(0, 0, -25), mat="n")
    k.box("Body", (0.15, 0.35, 0.12), (-0.03, 2.25, 0), glow, rot=(0, 0, 25), mat="n")
    k_rarity(k, stars, glow, 2.4)


def anglerfish(c, s, stars, body, belly, fin, glow):
    """A round deep-sea angler: underbite full of fangs and a glowing lure."""
    k = K(c, s)
    k.bob(0.12)
    k.box("Body", (1.7, 1.5, 1.6), (0, 0.25, 0.25), body)
    k.box("Body", (1.6, 0.95, 0.6), (0, 0.55, -0.8), body)
    k.box("Body", (1.4, 0.3, 1.4), (0, -0.55, 0.3), belly)
    k_eyes(k, "Body", 0.78, -1.1, 0.42, 0.36, brow=darken(body, 0.45))
    for x in (-0.55, -0.2, 0.2, 0.55):
        k.box("Body", (0.12, 0.26, 0.12), (x, -0.02, -1.0), WHITE)
    for (x, y, z) in ((0.86, 0.5, 0.5), (-0.86, 0.3, 0.1), (0.86, 0.0, 0.0), (-0.86, 0.6, 0.6)):
        k.box("Body", (0.06, 0.12, 0.12), (x, y, z), glow, mat="n")
    k.bone("Jaw", (0, -0.2, -0.4), anim="rot", axis="X", amp=6, speed=1,
           swim=dict(anim="rot", axis="X", amp=22, speed=4, phase=0))
    k.box("Jaw", (1.75, 0.5, 1.05), (0, -0.4, -0.9), darken(body, 0.15))
    k.box("Jaw", (1.4, 0.08, 0.9), (0, -0.14, -0.9), MOUTH)
    for x in (-0.6, -0.3, 0, 0.3, 0.6):
        k.box("Jaw", (0.12, 0.3, 0.12), (x, -0.05, -1.33), WHITE)
    k.bone("Lure", (0, 1.0, -0.55), anim="rot", axis="X", amp=16, speed=1)
    k.box("Lure", (0.09, 0.9, 0.09), (0, 1.37, -0.81), darken(body, 0.2), rot=(-35, 0, 0))
    k.box("Lure", (0.08, 0.08, 0.45), (0, 1.76, -1.25), darken(body, 0.2))
    k.ball("Lure", 0.42, (0, 1.62, -1.5), glow, mat="n")
    for sx, t in SIDES:
        k.bone("Fin" + t, (sx * 0.85, 0.1, 0.3), anim="rot", axis="Z", amp=22 * sx, speed=2)
        k.box("Fin" + t, (0.5, 0.1, 0.45), (sx * 1.1, 0.1, 0.3), fin, rot=(0, 0, -sx * 15))
    for i, z in enumerate((-0.1, 0.3, 0.7)):
        k.box("Body", (0.1, 0.35, 0.25), (0, 1.1, z), fin, rot=(20, 0, 0))
    out, zend = k_tail(k, (0, 0.25, 1.05), [((0.7, 0.7, 0.6), body, "p")], amp=20)
    k.box("Tail1", (0.1, 1.0, 0.7), (0, 0.25, zend + 0.25), fin)
    k_rarity(k, stars, glow, 2.0)


def narwhal(c, s, stars, body, belly, spots, tusk, glow=None):
    """A chubby narwhal with a twisted tusk, a blowhole fountain and up-down flukes."""
    k = K(c, s)
    k.box("Body", (1.6, 1.35, 2.6), (0, 0.1, 0.2), body)
    k.box("Body", (1.4, 1.0, 0.5), (0, 0.15, -1.2), body)
    k.box("Body", (1.3, 0.3, 2.4), (0, -0.55, 0.1), belly)
    for (x, z) in ((-0.45, -0.2), (0.4, 0.3), (-0.2, 0.8), (0.5, 1.1), (0.05, -0.7)):
        k.box("Body", (0.24, 0.06, 0.24), (x, 0.78, z), spots)
    k_spines(k, "Body", (-0.5, -0.1, 0.3, 0.7, 1.1), 0.75, spots, h=0.45, tip=glow)
    k_eyes(k, "Body", 0.3, -1.45, 0.45, 0.3)
    k_smile(k, "Body", -0.15, -1.45, 0.45, blush=BLUSH, bx=0.62)
    k.bone("Tusk", (0, 0.3, -1.45), anim="rot", axis="Y", amp=4, speed=1)
    for i, (w, ln) in enumerate(((0.24, 0.6), (0.18, 0.55), (0.13, 0.5))):
        tip = glow and i == 2
        k.box("Tusk", (w, w, ln), (0, 0.3 + i * 0.07, -1.75 - i * 0.52), glow if tip else tusk,
              rot=(0, 0, 45 if i % 2 == 0 else 0), mat="n" if tip else "p")
    for sx, t in SIDES:
        k.bone("Flip" + t, (sx * 0.8, -0.25, -0.4), anim="rot", axis="Z", amp=18 * sx, speed=1)
        k.box("Flip" + t, (0.7, 0.12, 0.45), (sx * 1.1, -0.35, -0.35), body, rot=(0, 0, -sx * 20))
    out, zend = k_tail(k, (0, 0.15, 1.5), [((1.1, 0.9, 0.7), body, "p"), ((0.75, 0.65, 0.65), body, "p")],
                       axis="X", amp=14)
    for sx in (-1, 1):
        k.box(out[-1][0], (0.8, 0.12, 0.45), (sx * 0.42, 0.15, zend + 0.15), darken(body, 0.15), rot=(0, -sx * 20, 0))
    k.bone("Spout", (0, 0.8, -0.4), anim="move", axis="Y", amp=0.1, speed=2)
    water = (170, 225, 255)
    k.box("Spout", (0.18, 0.4, 0.18), (0, 1.0, -0.4), water, mat="g")
    for sx in (-1, 1):
        k.box("Spout", (0.14, 0.14, 0.14), (sx * 0.25, 1.28, -0.4), water, mat="g")
    k_rarity(k, stars, glow, 1.4)


def isopod(c, s, stars, shell, under, accent):
    """A giant armoured isopod: overlapping arched plates, feelers and lots of little legs."""
    k = K(c, s)
    k.box("Body", (1.5, 0.4, 2.6), (0, -0.25, 0.15), under)
    for i in range(6):
        z = -0.85 + i * 0.42
        w = 2.0 - abs(i - 2.5) * 0.16
        col = shell if i % 2 == 0 else lighten(shell, 0.15)
        k.box("Body", (w, 0.6, 0.48), (0, 0.4, z), col)
        k.box("Body", (w - 0.5, 0.2, 0.44), (0, 0.78, z), lighten(col, 0.12))
        k.box("Body", (w + 0.12, 0.32, 0.4), (0, 0.0, z), darken(col, 0.2))
        k.box("Body", (0.16, 0.42, 0.16), (0, 1.05, z), accent, rot=(-20, 0, 0))
        for sx in (-1, 1):
            k.box("Body", (0.3, 0.12, 0.12), (sx * (w / 2 + 0.12), 0.0, z), accent, rot=(0, 0, -sx * 25))
    k.bone("Head", (0, 0.2, -1.1), anim="rot", axis="X", amp=5, speed=1)
    k.box("Head", (1.4, 0.75, 0.55), (0, 0.3, -1.35), darken(shell, 0.1))
    k_eyes(k, "Head", 0.4, -1.63, 0.4, 0.3)
    k_smile(k, "Head", 0.08, -1.63, 0.3)
    for sx, t in SIDES:
        k.bone("Ant" + t, (sx * 0.35, 0.55, -1.5), parent="Head", anim="rot", axis="Y", amp=15 * sx, speed=1)
        k.box("Ant" + t, (0.08, 0.08, 0.9), (sx * 0.45, 0.74, -1.9), accent, rot=(25, 0, 0))
    spots = []
    for z in (-0.6, 0.15, 0.9):
        spots += [(-0.7, -0.3, z), (0.7, -0.3, z)]
    k_legs(k, spots, (0.16, 0.5, 0.16), darken(under, 0.1), amp=25, speed=2)
    k.box("Body", (1.1, 0.3, 0.4), (0, 0.25, 1.45), shell)
    for sx in (-1, 1):
        k.box("Body", (0.15, 0.15, 0.5), (sx * 0.35, 0.1, 1.6), accent)
    k_rarity(k, stars, None, 1.1)


def eel(c, s, stars, body, belly, fin, glow, serpent=False):
    """A long ribbon of a body. Eels ripple side to side; serpents arch up and down in coils."""
    k = K(c, s)
    k.box("Body", (1.0, 0.9, 1.0), (0, 0.35, -0.5), body)
    k.box("Body", (0.8, 0.25, 0.95), (0, -0.1, -0.5), belly)
    k.bone("Head", (0, 0.5, -0.95), anim="rot", axis="X", amp=7, speed=1,
           swim=dict(anim="rot", axis="X", amp=14, speed=2, phase=0))
    k.box("Head", (1.1, 0.95, 1.1), (0, 0.75, -1.45), body)
    k.box("Head", (0.85, 0.45, 0.6), (0, 0.5, -2.25), body)
    k_eyes(k, "Head", 0.98, -2.0, 0.33, 0.3, brow=INK if serpent else None)
    k.bone("Jaw", (0, 0.3, -1.9), parent="Head", anim="rot", axis="X", amp=4, speed=1,
           swim=dict(anim="rot", axis="X", amp=18, speed=4, phase=0))
    k.box("Jaw", (0.8, 0.22, 0.6), (0, 0.18, -2.2), belly)
    for x in (-0.3, -0.1, 0.1, 0.3):
        k.box("Head", (0.09, 0.2, 0.09), (x, 0.22, -2.5), WHITE)
    for sx, t in SIDES:
        k.box("Head", (0.1, 0.45, 0.5), (sx * 0.6, 0.95, -1.4), fin, rot=(0, sx * 25, 0))
        if serpent:
            k.box("Head", (0.18, 0.7, 0.18), (sx * 0.35, 1.45, -1.1), lighten(fin, 0.5), rot=(35, 0, -sx * 15))
            k.bone("Whisk" + t, (sx * 0.4, 0.5, -2.4), parent="Head", anim="rot", axis="Y", amp=18 * sx, speed=1)
            k.box("Whisk" + t, (0.07, 0.07, 0.9), (sx * 0.7, 0.5, -2.75), glow, rot=(0, -sx * 40, 0), mat="n")
    widths = (0.95, 0.85, 0.75, 0.62, 0.5, 0.38)
    segs = [((w, w * 0.95, 0.85), body, "p") for w in widths]
    out, zend = k_tail(k, (0, 0.35, 0.0), segs, axis="X" if serpent else "Y", amp=12 if serpent else 18, lag=0.8)
    for i, (n, zc, sz) in enumerate(out):
        top = 0.35 + sz[1] / 2
        if serpent:
            k.box(n, (0.16, 0.4, 0.3), (0, top + 0.12, zc), fin, rot=(-20, 0, 0))
        else:
            k.box(n, (0.07, 0.3, sz[2] * 0.9), (0, top + 0.1, zc), glow, mat="n")
        k.box(n, (sz[0] * 0.8, 0.12, sz[2]), (0, 0.35 - sz[1] / 2, zc), belly)
        if i % 2 == 0 and not serpent:
            for sx in (-1, 1):
                k.box(n, (0.05, 0.14, 0.3), (sx * sz[0] / 2, 0.4, zc), glow, mat="n")
    k.box(out[-1][0], (0.08, 0.6, 0.5), (0, 0.35, zend + 0.15), glow if not serpent else fin,
          mat="n" if not serpent else "p")
    k_rarity(k, stars, glow, 1.6, z=-1.3)


def octopus(c, s, stars, body, belly, spot, glow=None, king=False):
    """A big-headed octopus on eight curling arms. The king wears a crown and scowls."""
    k = K(c, s)
    k.box("Body", (1.7, 1.6, 1.6), (0, 1.0, 0.15), body)
    k.box("Body", (1.3, 0.45, 1.3), (0, 1.95, 0.25), body)
    k.box("Body", (1.9, 0.4, 1.8), (0, 0.15, 0.05), lighten(body, 0.1))
    for (x, z) in ((-0.4, 0.0), (0.35, 0.5), (0.0, 0.2)):
        k.box("Body", (0.25, 0.06, 0.25), (x, 2.19, z), spot)
    for (y, z) in ((1.2, 0.3), (0.8, 0.6)):
        for sx in (-1, 1):
            k.box("Body", (0.06, 0.22, 0.22), (sx * 0.86, y, z), spot)
    k_eyes(k, "Body", 0.95, -0.65, 0.42, 0.42, brow=INK if king else None)
    k_smile(k, "Body", 0.52, -0.65, 0.3, blush=None if king else BLUSH, bx=0.62)
    nseg = 4 if king else 3
    seg = (0.36, 0.36, 0.36) if king else (0.32, 0.34, 0.32)
    for i in range(8):
        a = i / 8 * math.tau + math.tau / 16
        d = (math.cos(a), math.sin(a))
        k_arm(k, "Arm%d" % i, (d[0] * 0.6, -0.05, d[1] * 0.6), d, nseg, seg, body, tip=glow or belly,
              out=0.3, down=0.26 if king else 0.3, amp=14, phase=i * 0.7, tipmat="n" if glow else "p")
    if king:
        k.box("Body", (1.4, 0.16, 1.4), (0, 2.25, 0.25), GOLDC, mat="m")
        for i in range(6):
            a = i / 6 * math.tau
            k.box("Body", (0.18, 0.5, 0.18), (math.cos(a) * 0.55, 2.55, 0.25 + math.sin(a) * 0.55), GOLDC, mat="m")
        k.box("Body", (0.24, 0.24, 0.08), (0, 2.25, -0.47), glow or (255, 80, 120), mat="n")
    k_rarity(k, stars, glow, 2.9 if king else 2.2, z=0.25, orbit_y=1.2, orbit_r=2.4)


def seahorse(c, s, stars, body, belly, leaf, glow=None, king=False):
    """An upright leafy seahorse: long snout, curled tail, kelp fronds waving off its back."""
    k = K(c, s * 0.9)
    k.bob(0.15)
    k.box("Body", (1.0, 1.5, 0.95), (0, 0.35, 0.05), body)
    k.box("Body", (0.75, 1.3, 0.12), (0, 0.3, -0.45), belly)
    for y in (-0.15, 0.2, 0.55, 0.9):
        k.box("Body", (0.8, 0.06, 0.14), (0, y, -0.5), darken(belly, 0.15))
    k.bone("Head", (0, 1.05, 0), anim="rot", axis="X", amp=6, speed=1)
    k.box("Head", (0.95, 0.85, 1.0), (0, 1.5, -0.05), body)
    k.box("Head", (0.36, 0.34, 0.8), (0, 1.3, -0.9), body)
    k.box("Head", (0.46, 0.42, 0.22), (0, 1.3, -1.38), lighten(body, 0.15))
    k_eyes(k, "Head", 1.68, -0.56, 0.3, 0.3)
    if king:
        k.box("Head", (0.9, 0.14, 0.9), (0, 1.98, -0.05), GOLDC, mat="m")
        for x in (-0.3, 0, 0.3):
            k.box("Head", (0.14, 0.4 if x == 0 else 0.3, 0.14), (x, 2.2, -0.35), GOLDC, mat="m")
        k.box("Head", (0.14, 0.14, 0.06), (0, 2.0, -0.52), glow or (255, 90, 120), mat="n")
    else:
        for x in (-0.22, 0, 0.22):
            k.box("Head", (0.14, 0.35, 0.14), (x, 2.05, 0.05), leaf)
    lc = glow or lighten(leaf, 0.3)
    leaves = [(-1, 0.6, 0.2), (1, 0.6, 0.2), (-1, 1.0, 0.35), (1, 1.0, 0.35)]
    if king:
        leaves += [(-1, 0.2, 0.3), (1, 0.2, 0.3)]
    for i, (sx, y, z) in enumerate(leaves):
        n = "Leaf%d" % (i + 1)
        k.bone(n, (sx * 0.5, y, z), anim="rot", axis="Z", amp=14 * sx, speed=1, phase=i * 0.7)
        k.box(n, (0.55, 0.14, 0.35), (sx * 0.8, y + 0.12, z), leaf, rot=(0, 0, sx * 30))
        k.box(n, (0.22, 0.12, 0.22), (sx * 1.1, y + 0.33, z), lc, rot=(0, 0, sx * 30), mat="n" if glow else "p")
    k_spines(k, "Body", (-0.2, 0.15, 0.5, 0.85), 0.6, darken(body, 0.3), h=0.3, lean=-70)
    k.bone("Dorsal", (0, 0.4, 0.5), anim="rot", axis="Y", amp=25, speed=2)
    k.box("Dorsal", (0.08, 0.5, 0.45), (0, 0.45, 0.72), lighten(leaf, 0.2), mat="g")
    k.bone("Mane", (0, 1.7, 0.4), parent="Head", anim="rot", axis="X", amp=10, speed=1)
    k.box("Mane", (0.12, 0.5, 0.4), (0, 1.8, 0.6), leaf, rot=(30, 0, 0))
    k.box("Mane", (0.18, 0.18, 0.18), (0, 2.05, 0.75), lc, mat="n" if glow else "p")
    k.bone("T1", (0, -0.35, 0.05), anim="rot", axis="X", amp=8, speed=1)
    k.box("T1", (0.7, 0.55, 0.7), (0, -0.6, 0.1), body)
    k.bone("T2", (0, -0.85, 0.1), parent="T1", anim="rot", axis="X", amp=8, speed=1, phase=-0.8)
    k.box("T2", (0.52, 0.45, 0.55), (0, -1.05, 0.1), body)
    k.bone("T3", (0, -1.25, 0.1), parent="T2", anim="rot", axis="X", amp=10, speed=1, phase=-1.6)
    k.box("T3", (0.4, 0.36, 0.5), (0, -1.35, -0.2), body)
    k.box("T3", (0.3, 0.4, 0.3), (0, -1.18, -0.5), lighten(body, 0.15))
    k_rarity(k, stars, glow, 2.3)


def whale(c, s, stars, body, belly, accent, glow, tempest=False):
    """A round, smiling whale with a spout. The tempest whale carries its own storm cloud."""
    k = K(c, s)
    k.box("Body", (2.0, 1.7, 3.0), (0, 0.25, 0.3), body)
    k.box("Body", (1.8, 1.3, 0.5), (0, 0.35, -1.4), body)
    k.box("Body", (1.7, 0.35, 2.8), (0, -0.65, 0.1), belly)
    for x in (-0.5, -0.17, 0.17, 0.5):
        k.box("Body", (0.08, 0.06, 2.4), (x, -0.83, 0.1), darken(belly, 0.15))
    k_eyes(k, "Body", 0.15, -1.67, 0.6, 0.32)
    k_smile(k, "Body", -0.25, -1.67, 0.9, blush=BLUSH, bx=0.75)
    for i, z in enumerate((-0.3, 0.4, 1.1)):
        k.box("Body", (0.14, 0.07, 0.55), (0.1 if i % 2 else -0.1, 1.12, z), glow, rot=(0, 30 if i % 2 else -30, 0), mat="n")
    k_spines(k, "Body", (-0.9, -0.5, 0.0, 0.5, 1.0, 1.5), 1.1, darken(body, 0.35), h=0.45)
    for sx, t in SIDES:
        k.bone("Flip" + t, (sx * 1.0, -0.3, -0.3), anim="rot", axis="Z", amp=18 * sx, speed=1)
        k.box("Flip" + t, (0.9, 0.15, 0.55), (sx * 1.4, -0.45, -0.25), body, rot=(0, 0, -sx * 25))
    segs = [((1.3, 1.1, 0.8), body, "p"), ((0.9, 0.8, 0.7), body, "p"), ((0.55, 0.55, 0.6), body, "p")]
    out, zend = k_tail(k, (0, 0.3, 1.8), segs, axis="X", amp=12)
    for sx in (-1, 1):
        k.box(out[-1][0], (1.0, 0.14, 0.6), (sx * 0.5, 0.3, zend + 0.2), accent if tempest else darken(body, 0.15),
              rot=(0, -sx * 25, 0))
    water = (170, 225, 255)
    k.bone("Spout", (0, 1.1, -0.6), anim="move", axis="Y", amp=0.1, speed=2)
    k.box("Spout", (0.25, 0.5, 0.25), (0, 1.35, -0.6), water, mat="g")
    for sx in (-1, 1):
        k.box("Spout", (0.16, 0.16, 0.16), (sx * 0.3, 1.65, -0.6), water, mat="g")
    if tempest:
        grey, dark = (150, 160, 185), (110, 118, 145)
        k.bone("Cloud", (0, 2.3, 0.4), anim="move", axis="Y", amp=0.12, speed=1)
        k.box("Cloud", (1.4, 0.5, 0.9), (0, 2.3, 0.4), grey)
        k.box("Cloud", (0.9, 0.45, 0.7), (-0.45, 2.6, 0.35), lighten(grey, 0.2))
        k.box("Cloud", (0.75, 0.45, 0.7), (0.45, 2.55, 0.45), dark)
        k.box("Cloud", (0.14, 0.4, 0.1), (0.1, 1.9, 0.4), glow, rot=(0, 0, -25), mat="n")
        k.box("Cloud", (0.14, 0.35, 0.1), (0.02, 1.62, 0.4), glow, rot=(0, 0, 25), mat="n")
    k_rarity(k, stars, glow, 2.9 if tempest else 1.8)


def shark(c, s, stars, body, belly, accent, glow=None, abyss=False):
    """A torpedo shark with a toothy grin, a tall dorsal fin and a crescent tail."""
    k = K(c, s)
    k.box("Body", (1.3, 1.2, 2.4), (0, 0.25, 0.2), body)
    k.box("Body", (1.1, 0.35, 2.2), (0, -0.35, 0.1), belly)
    for sx in (-1, 1):
        for g in range(3):
            k.box("Body", (0.05, 0.4, 0.07), (sx * 0.66, 0.3, -0.6 + g * 0.16), darken(body, 0.3))
        if abyss:
            k.box("Body", (0.05, 0.12, 1.6), (sx * 0.66, 0.05, 0.4), glow, mat="n")
    for z in (-0.3, 0.3, 0.9):
        k.box("Body", (0.5, 0.06, 0.18), (0, 0.86, z), accent)
    k.bone("Head", (0, 0.25, -0.9), anim="rot", axis="Y", amp=5, speed=1)
    k.box("Head", (1.15, 0.95, 0.9), (0, 0.35, -1.35), body)
    k.box("Head", (0.6, 0.4, 0.5), (0, 0.33, -1.95), body)
    k.box("Head", (1.0, 0.2, 0.75), (0, -0.05, -1.45), belly)
    for x in (-0.36, -0.12, 0.12, 0.36):
        k.box("Head", (0.12, 0.18, 0.1), (x, -0.2, -1.78), WHITE, rot=(0, 0, 45))
    k_eyes(k, "Head", 0.64, -1.8, 0.42, 0.26, brow=INK, glow=glow if abyss else None)
    k.bone("Jaw", (0, -0.1, -0.9), parent="Head", anim="rot", axis="X", amp=5, speed=1,
           swim=dict(anim="rot", axis="X", amp=22, speed=4, phase=0))
    k.box("Jaw", (1.0, 0.3, 0.85), (0, -0.3, -1.35), belly)
    k.box("Jaw", (0.9, 0.06, 0.7), (0, -0.13, -1.35), MOUTH)
    for x in (-0.3, -0.1, 0.1, 0.3):
        k.box("Jaw", (0.11, 0.18, 0.1), (x, -0.08, -1.72), WHITE, rot=(0, 0, 45))
    k.box("Body", (0.16, 1.0, 0.8), (0, 1.15, 0.25), body, rot=(25, 0, 0))
    k.box("Body", (0.17, 0.35, 0.4), (0, 1.62, 0.55), glow if abyss else accent, rot=(35, 0, 0), mat="n" if abyss else "p")
    for sx, t in SIDES:
        k.bone("Fin" + t, (sx * 0.6, -0.2, -0.3), anim="rot", axis="Z", amp=12 * sx, speed=1)
        k.box("Fin" + t, (0.9, 0.12, 0.5), (sx * 1.0, -0.4, -0.2), body, rot=(0, 0, -sx * 30))
    out, zend = k_tail(k, (0, 0.3, 1.4), [((0.9, 0.85, 0.8), body, "p"), ((0.55, 0.55, 0.7), body, "p")], amp=18)
    k.box(out[-1][0], (0.15, 1.1, 0.4), (0, 0.75, zend + 0.05), body, rot=(35, 0, 0))
    k.box(out[-1][0], (0.15, 0.6, 0.35), (0, -0.1, zend), body, rot=(-30, 0, 0))
    k_rarity(k, stars, glow, 1.9)


def crab(c, s, stars, shell, belly, claw, glow=None, big=False):
    """A wide crab with eyes on stalks and snapping pincers. The big one carries lightning rods."""
    k = K(c, s)
    cm = 1.3 if big else 1.0
    k.box("Body", (2.0, 0.9, 1.5), (0, 0.15, 0.1), shell)
    k.box("Body", (1.7, 0.25, 1.25), (0, 0.7, 0.15), lighten(shell, 0.12))
    k.box("Body", (1.8, 0.2, 1.3), (0, -0.38, 0.1), belly)
    for sx in (-1, 1):
        for z in (-0.2, 0.35):
            k.box("Body", (0.2, 0.3, 0.2), (sx * 1.02, 0.45, z), shell, rot=(0, 0, -sx * 35))
    for (x, z) in ((-0.45, 0.4), (0.5, 0.0), (0.1, 0.55)):
        k.box("Body", (0.22, 0.06, 0.22), (x, 0.85, z), lighten(shell, 0.35))
    k_smile(k, "Body", 0.0, -0.66, 0.4, blush=BLUSH, bx=0.6)
    for sx, t in SIDES:
        k.bone("Stalk" + t, (sx * 0.38, 0.6, -0.5), anim="rot", axis="Z", amp=10 * sx, speed=1, phase=1 if sx > 0 else 0)
        k.box("Stalk" + t, (0.14, 0.55, 0.14), (sx * 0.38, 0.95, -0.5), shell)
        k.box("Stalk" + t, (0.36, 0.38, 0.3), (sx * 0.38, 1.35, -0.5), WHITE)
        k.box("Stalk" + t, (0.18, 0.22, 0.06), (sx * 0.35, 1.32, -0.67), INK)
        k.box("Stalk" + t, (0.07, 0.07, 0.04), (sx * 0.44, 1.42, -0.69), WHITE, mat="n")
        k.box("Stalk" + t, (0.46, 0.12, 0.1), (sx * 0.38, 1.52, -0.66), INK, rot=(0, 0, sx * 22))
        k.bone("Claw" + t, (sx * 0.95, 0.1, -0.35), anim="rot", axis="Y", amp=12 * sx, speed=2,
               swim=dict(anim="rot", axis="Y", amp=30 * sx, speed=4, phase=0))
        k.box("Claw" + t, (0.4, 0.35, 0.6), (sx * 1.15, 0.1, -0.6), shell)
        k.box("Claw" + t, (0.8 * cm, 0.7 * cm, 0.65 * cm), (sx * 1.3, 0.2, -1.05), claw)
        k.box("Claw" + t, (0.3 * cm, 0.25 * cm, 0.6 * cm), (sx * 1.4, 0.2 + 0.25 * cm, -1.05 - 0.55 * cm), claw)
        k.box("Claw" + t, (0.2 * cm, 0.2 * cm, 0.2 * cm), (sx * 1.4, 0.2 + 0.25 * cm, -1.05 - 0.9 * cm),
              glow or lighten(claw, 0.3), mat="n" if glow else "p")
        k.bone("Pinch" + t, (sx * 1.3, 0.0, -1.0 - 0.25 * cm), parent="Claw" + t, anim="rot", axis="X", amp=10, speed=2,
               swim=dict(anim="rot", axis="X", amp=30, speed=4, phase=0))
        k.box("Pinch" + t, (0.3 * cm, 0.2 * cm, 0.55 * cm), (sx * 1.3, -0.05, -1.05 - 0.5 * cm), darken(claw, 0.1))
    spots = []
    for z in (-0.1, 0.3, 0.7):
        spots += [(-0.9, -0.25, z), (0.9, -0.25, z)]
    k_legs(k, spots, (0.18, 0.5, 0.18), darken(shell, 0.15), amp=22, speed=2)
    if big and glow:
        for sx in (-1, 1):
            k.box("Body", (0.12, 0.45, 0.12), (sx * 0.4, 1.05, 0.4), glow, rot=(0, 0, 20), mat="n")
            k.box("Body", (0.12, 0.4, 0.12), (sx * 0.45, 1.4, 0.4), glow, rot=(0, 0, -20), mat="n")
    k_rarity(k, stars, glow, 1.8)


def skull_hermit(c, s, stars, bonec, body, glow, lord=False):
    """A hermit crab living in a giant skull: the skull's sockets glow, the crab peeks out under the teeth."""
    k = K(c, s)
    k.box("Body", (1.3, 0.7, 1.2), (0, -0.35, -0.15), body)
    k.box("Body", (1.9, 1.4, 1.7), (0, 0.8, 0.35), bonec)
    k.box("Body", (1.6, 0.4, 1.4), (0, 1.6, 0.4), bonec)
    k.box("Body", (1.5, 0.35, 0.5), (0, 0.15, -0.4), darken(bonec, 0.08))
    for sx in (-1, 1):
        k.box("Body", (0.5, 0.48, 0.08), (sx * 0.45, 1.0, -0.52), INK)
        k.box("Body", (0.2, 0.2, 0.06), (sx * 0.45, 0.98, -0.57), glow, mat="n")
    k.box("Body", (0.18, 0.22, 0.06), (0, 0.62, -0.52), INK, rot=(0, 0, 45))
    for x in (-0.5, -0.25, 0, 0.25, 0.5):
        k.box("Body", (0.18, 0.22, 0.12), (x, -0.08, -0.66), WHITE)
    k.box("Body", (0.06, 0.4, 0.05), (0.55, 1.45, -0.5), darken(bonec, 0.3), rot=(0, 0, 20))
    k_eyes(k, "Body", -0.35, -0.75, 0.28, 0.28)
    for sx, t in SIDES:
        k.bone("Claw" + t, (sx * 0.55, -0.4, -0.6), anim="rot", axis="Y", amp=14 * sx, speed=2,
               swim=dict(anim="rot", axis="Y", amp=30 * sx, speed=4, phase=0))
        k.box("Claw" + t, (0.3, 0.25, 0.35), (sx * 0.68, -0.45, -0.85), body)
        k.box("Claw" + t, (0.26, 0.2, 0.24), (sx * 0.68, -0.42, -1.1), lighten(body, 0.3))
    k_legs(k, [(-0.6, -0.55, -0.1), (0.6, -0.55, -0.1), (-0.6, -0.55, 0.35), (0.6, -0.55, 0.35)],
           (0.16, 0.4, 0.16), darken(body, 0.1), amp=20, speed=2)
    if lord:
        for sx in (-1, 1):
            k.box("Body", (0.3, 0.7, 0.3), (sx * 1.05, 1.5, 0.3), bonec, rot=(0, 0, sx * 30))
            k.box("Body", (0.22, 0.45, 0.22), (sx * 1.32, 1.92, 0.4), lighten(bonec, 0.4), rot=(0, 0, -sx * 10))
            for y in (0.5, 0.9):
                k.box("Body", (0.06, 0.12, 0.3), (sx * 0.96, y, 0.5), glow, mat="n")
        k.box("Body", (1.3, 0.15, 1.2), (0, 1.88, 0.4), GOLDC, mat="m")
        for x in (-0.45, 0, 0.45):
            k.box("Body", (0.16, 0.42 if x == 0 else 0.32, 0.16), (x, 2.12, -0.15), GOLDC, mat="m")
    k_rarity(k, stars, glow, 2.3 if lord else 1.9, z=0.35)


def manta(c, s, stars, top, belly, accent, glow, night=False):
    """A devil ray: a thick armoured body, glowing eyes over a fanged maw, curled horns, spined
    back, huge hooked wings with glowing spots, and a barbed tail ending in a glowing stinger."""
    k = K(c, s * 1.1)
    k.bob(0.22)
    k.box("Body", (1.8, 0.8, 2.2), (0, 0.5, 0.2), top)
    k.box("Body", (1.6, 0.15, 2.0), (0, 0.05, 0.2), belly)
    k.box("Body", (1.5, 0.6, 0.6), (0, 0.55, -1.05), top)
    k.box("Body", (1.2, 0.18, 1.6), (0, 0.95, 0.3), darken(top, 0.25))
    k_spines(k, "Body", (-0.5, -0.1, 0.3, 0.7, 1.1), 1.0, accent, h=0.8 if night else 0.5, tip=glow)
    k_eyes(k, "Body", 0.68, -1.35, 0.45, 0.3, glow=glow)
    k.box("Body", (1.0, 0.22, 0.05), (0, 0.36, -1.37), (40, 10, 30))
    for x in (-0.4, -0.2, 0, 0.2, 0.4):
        k.box("Body", (0.09, 0.16, 0.05), (x, 0.42, -1.4), WHITE)
    for x in (-0.3, -0.1, 0.1, 0.3):
        k.box("Body", (0.09, 0.14, 0.05), (x, 0.29, -1.4), WHITE)
    for sx in (-1, 1):
        k.box("Body", (0.26, 0.26, 0.7), (sx * 0.62, 0.5, -1.55), accent, rot=(-15, 0, 0))
        k.box("Body", (0.2, 0.5, 0.2), (sx * 0.62, 0.85, -1.85), accent, rot=(25, 0, -sx * 10))
        k.box("Body", (0.13, 0.13, 0.13), (sx * 0.6, 1.12, -1.95), glow, mat="n")
    if night:
        for sx in (-1, 1):  # a second, swept-back pair of horns
            k.box("Body", (0.18, 0.7, 0.18), (sx * 0.55, 1.15, -0.75), accent, rot=(-35, 0, -sx * 20))
            k.box("Body", (0.12, 0.12, 0.12), (sx * 0.66, 1.45, -0.55), glow, mat="n")
        k.box("Body", (0.4, 0.08, 0.14), (-0.08, 1.06, -0.3), glow, rot=(0, 30, 0), mat="n")
        k.box("Body", (0.4, 0.08, 0.14), (0.1, 1.06, -0.05), glow, rot=(0, -30, 0), mat="n")
        for (x, z) in ((-0.4, 0.6), (0.35, 0.9), (0.1, 0.4)):
            k.box("Body", (0.1, 0.06, 0.1), (x, 1.06, z), WHITE, mat="n")
    for sx, t in SIDES:
        k.bone("Wing" + t, (sx * 0.85, 0.5, 0.2), anim="rot", axis="Z", amp=22 * sx, speed=1,
               swim=dict(anim="rot", axis="Z", amp=40 * sx, speed=2, phase=0))
        k.box("Wing" + t, (2.0, 0.24, 2.0), (sx * 1.6, 0.5, 0.25), top, rot=(0, 45, 0))
        k.box("Wing" + t, (1.8, 0.1, 1.8), (sx * 1.6, 0.36, 0.25), belly, rot=(0, 45, 0))
        for (x, z) in ((1.3, -0.1), (1.75, 0.45), (2.15, 0.1)):
            k.box("Wing" + t, (0.2, 0.06, 0.2), (sx * x, 0.64, z), glow, mat="n")
        for i in range(3):
            k.box("Wing" + t, (0.12, 0.12, 0.32), (sx * (1.15 + i * 0.45), 0.55, -0.55 + i * 0.42), WHITE,
                  rot=(0, sx * 40, 0))
        k.bone("WingTip" + t, (sx * 2.35, 0.5, 0.25), parent="Wing" + t, anim="rot", axis="Z", amp=18 * sx, speed=1,
               phase=-0.8)
        k.box("WingTip" + t, (1.1, 0.18, 1.0), (sx * 2.85, 0.6, 0.35), top, rot=(0, 45, 0))
        k.box("WingTip" + t, (0.15, 0.15, 0.55), (sx * 3.35, 0.62, 0.05), WHITE, rot=(0, sx * 35, 0))
    segs = [((0.24, 0.24, 0.6), top, "p"), ((0.2, 0.2, 0.6), top, "p"), ((0.16, 0.16, 0.6), top, "p"),
            ((0.13, 0.13, 0.6), top, "p")]
    out, zend = k_tail(k, (0, 0.45, 1.3), segs, amp=20, lag=0.7)
    for n, zc, sz in out:
        k.box(n, (0.42, 0.07, 0.09), (0, 0.5, zc), WHITE, rot=(0, 45, 0))
    k.box(out[-1][0], (0.22, 0.22, 0.6), (0, 0.45, zend + 0.25), glow, rot=(0, 0, 45), mat="n")
    for sx in (-1, 1):
        k.box(out[-1][0], (0.3, 0.08, 0.1), (sx * 0.15, 0.45, zend + 0.05), glow, rot=(0, -sx * 40, 0), mat="n")
    k_rarity(k, stars, glow, 1.3)


def sea_toad(c, s, stars, body, belly, accent, glow):
    """A huge-mouthed sea toad with bulging eyes and a curling wave crest down its back."""
    k = K(c, s)
    k.box("Body", (2.0, 1.2, 1.9), (0, 0.0, 0.35), body)
    k.box("Body", (1.7, 0.3, 1.7), (0, -0.55, 0.3), belly)
    for (x, z) in ((-0.55, 0.6), (0.6, 0.9), (0.2, 0.3), (-0.3, 1.1)):
        k.box("Body", (0.22, 0.08, 0.22), (x, 0.62, z), lighten(body, 0.3))
    k.bone("Head", (0, 0.2, -0.4), anim="rot", axis="X", amp=4, speed=1)
    k.box("Head", (2.2, 0.9, 1.4), (0, 0.55, -0.85), body)
    for sx in (-1, 1):
        k.box("Head", (0.65, 0.55, 0.65), (sx * 0.62, 1.15, -0.95), body)
        k.box("Head", (0.46, 0.46, 0.08), (sx * 0.62, 1.2, -1.29), WHITE)
        k.box("Head", (0.32, 0.14, 0.06), (sx * 0.62, 1.17, -1.34), INK)
        k.box("Head", (0.1, 0.1, 0.05), (sx * 0.72, 1.32, -1.36), WHITE, mat="n")
        k.box("Head", (0.72, 0.16, 0.2), (sx * 0.6, 1.46, -1.3), darken(body, 0.35), rot=(0, 0, sx * 20))
        k.box("Head", (0.12, 0.28, 0.12), (sx * 0.55, 0.0, -1.45), WHITE)
    k.box("Head", (2.0, 0.07, 0.05), (0, 0.13, -1.56), INK)
    k.bone("Jaw", (0, 0.15, -0.3), parent="Head", anim="rot", axis="X", amp=4, speed=1,
           swim=dict(anim="rot", axis="X", amp=24, speed=4, phase=0))
    k.box("Jaw", (2.1, 0.45, 1.4), (0, -0.05, -0.85), belly)
    k.box("Jaw", (1.8, 0.08, 1.1), (0, 0.18, -0.9), MOUTH)
    k.box("Jaw", (0.4, 0.08, 0.7), (0, 0.23, -1.0), BLUSH)
    k.bone("Crest", (0, 0.6, 0.0), anim="rot", axis="X", amp=6, speed=1)
    for i, (h, z) in enumerate(((0.6, 0.0), (0.8, 0.45), (0.65, 0.9))):
        k.box("Crest", (0.3, h, 0.45), (0, 0.6 + h / 2, z), accent, rot=(-20, 0, 0), mat="g")
        k.box("Crest", (0.32, 0.14, 0.3), (0, 0.6 + h, z - 0.15), WHITE)
    if glow:
        k.box("Crest", (0.18, 0.18, 0.18), (0, 0.85, 0.45), glow, mat="n")
    for sx in (-1, 1):
        k.box("Body", (0.35, 0.55, 0.35), (sx * 0.75, -0.65, -0.5), body)
        k.box("Body", (0.6, 0.1, 0.55), (sx * 0.8, -0.95, -0.6), accent)
    for sx, t in SIDES:
        k.bone("Hop" + t, (sx * 1.0, -0.1, 0.6), anim="rot", axis="X", amp=8, speed=1, phase=0 if sx < 0 else math.pi)
        k.box("Hop" + t, (0.6, 0.7, 1.1), (sx * 1.1, -0.3, 0.75), body)
        k.box("Hop" + t, (0.7, 0.12, 0.8), (sx * 1.15, -0.92, 0.55), accent)
    k_rarity(k, stars, glow, 1.6, z=-0.6)


def lionfish(c, s, stars, body, stripe, fin, glow):
    """A striped lionfish: a mane of venom spines and two huge feathery fans."""
    k = K(c, s)
    k.bob(0.12)
    k.box("Body", (1.2, 1.4, 2.0), (0, 0.35, 0.25), body)
    for z in (-0.35, 0.25, 0.85):
        k.box("Body", (1.24, 1.44, 0.2), (0, 0.35, z), stripe)
    k.box("Body", (1.1, 1.2, 0.6), (0, 0.4, -0.95), body)
    k.box("Body", (1.14, 0.2, 0.62), (0, 0.78, -0.95), stripe)
    k_eyes(k, "Body", 0.45, -1.25, 0.3, 0.3, brow=INK)
    k.box("Body", (0.4, 0.15, 0.1), (0, 0.08, -1.28), lighten(body, 0.4))
    for sx in (-1, 1):
        k.box("Body", (0.08, 0.32, 0.08), (sx * 0.25, -0.2, -1.15), stripe)
    k.box("Body", (0.04, 0.8, 1.6), (0, 1.45, 0.15), fin, mat="g")
    for i in range(6):
        z = -0.6 + i * 0.3
        h = 1.25 - abs(i - 1.5) * 0.12
        k.box("Body", (0.08, h, 0.08), (0, 1.05 + h / 2, z), stripe, rot=(-15, 0, 0))
        k.box("Body", (0.14, 0.14, 0.14), (0, 1.05 + h, z - h * 0.13), glow, mat="n")
    for sx, t in SIDES:
        k.bone("Fan" + t, (sx * 0.6, 0.2, -0.3), anim="rot", axis="Y", amp=15 * sx, speed=1,
               swim=dict(anim="rot", axis="Y", amp=30 * sx, speed=2, phase=0))
        for j in range(4):
            a = -20 + j * 28
            r = math.radians(a)
            k.box("Fan" + t, (1.3, 0.06, 0.2), (sx * (0.6 + math.cos(r) * 0.65), 0.2 - j * 0.12, -0.3 + math.sin(r) * 0.65),
                  stripe if j % 2 == 0 else fin, rot=(0, -sx * a, 0))
    for sx in (-1, 1):
        k.box("Body", (0.14, 0.45, 0.14), (sx * 0.3, 1.15, -1.0), fin, rot=(0, 0, -sx * 15))
        k.box("Body", (0.16, 0.16, 0.16), (sx * 0.38, 1.42, -1.0), glow, mat="n")
    out, zend = k_tail(k, (0, 0.35, 1.25), [((0.7, 0.8, 0.5), body, "p")], amp=16)
    k.box("Tail1", (0.06, 1.2, 0.8), (0, 0.35, zend + 0.35), fin, mat="g")
    k_rarity(k, stars, glow, 2.4)


def mantis_shrimp(c, s, stars, body, belly, accent, glow):
    """A mantis shrimp: striped stalk eyes, a curled armoured tail and two glowing punching clubs."""
    k = K(c, s)
    k.box("Body", (1.2, 0.9, 1.0), (0, 0.35, -0.3), body)
    k.box("Body", (1.0, 0.25, 0.95), (0, -0.18, -0.3), belly)
    k.bone("Head", (0, 0.55, -0.75), anim="rot", axis="Y", amp=6, speed=1)
    k.box("Head", (0.9, 0.6, 0.6), (0, 0.7, -1.05), body)
    k_smile(k, "Head", 0.6, -1.35, 0.3)
    for sx, t in SIDES:
        k.bone("Eye" + t, (sx * 0.25, 1.0, -1.1), parent="Head", anim="rot", axis="Z", amp=12 * sx, speed=1,
               phase=0 if sx < 0 else 1.5)
        k.box("Eye" + t, (0.12, 0.4, 0.12), (sx * 0.27, 1.2, -1.1), body)
        k.box("Eye" + t, (0.36, 0.22, 0.36), (sx * 0.3, 1.66, -1.12), accent)
        k.box("Eye" + t, (0.36, 0.22, 0.36), (sx * 0.3, 1.44, -1.12), lighten(accent, 0.5))
        k.box("Eye" + t, (0.38, 0.06, 0.38), (sx * 0.3, 1.55, -1.12), INK)
        k.box("Eye" + t, (0.1, 0.1, 0.04), (sx * 0.3, 1.6, -1.32), WHITE, mat="n")
        k.bone("Ant" + t, (sx * 0.3, 0.8, -1.3), parent="Head", anim="rot", axis="Y", amp=14 * sx, speed=2)
        k.box("Ant" + t, (0.35, 0.08, 0.6), (sx * 0.55, 0.85, -1.55), accent, rot=(0, -sx * 30, 0))
        k.bone("Punch" + t, (sx * 0.45, 0.2, -1.0), anim="rot", axis="X", amp=10, speed=1,
               swim=dict(anim="rot", axis="X", amp=45, speed=4, phase=0 if sx < 0 else math.pi))
        k.box("Punch" + t, (0.25, 0.6, 0.25), (sx * 0.5, 0.0, -1.15), body)
        k.box("Punch" + t, (0.42, 0.42, 0.48), (sx * 0.5, -0.25, -1.45), glow, mat="n")
    spots = []
    for z in (-0.55, -0.1):
        spots += [(-0.5, -0.25, z), (0.5, -0.25, z)]
    k_legs(k, spots, (0.14, 0.5, 0.14), accent, amp=20, speed=2)
    segs = [((1.15, 0.85, 0.55), body, "p"), ((1.05, 0.78, 0.55), body, "p"), ((0.95, 0.7, 0.5), body, "p"),
            ((0.8, 0.6, 0.5), body, "p")]
    out, zend = k_tail(k, (0, 0.25, 0.2), segs, axis="X", amp=8, lag=0.6)
    for n, zc, sz in out:
        k.box(n, (sz[0] * 0.9, 0.08, sz[2] * 0.5), (0, 0.25 + sz[1] / 2 + 0.02, zc), accent)
    k.box(out[-1][0], (1.3, 0.12, 0.5), (0, 0.25, zend + 0.2), accent)
    for sx in (-1, 1):
        k.box(out[-1][0], (0.14, 0.06, 0.14), (sx * 0.4, 0.32, zend + 0.2), glow, mat="n")
    k_rarity(k, stars, glow, 1.9, z=-1.0)


def vampire_squid(c, s, stars, body, cape, glow):
    """A vampire squid: glowing eyes, little fangs and an umbrella cape fringed with spikes."""
    k = K(c, s)
    k.bob(0.15)
    k.box("Body", (1.3, 1.5, 1.3), (0, 1.2, 0.1), body)
    k.box("Body", (0.9, 0.4, 0.9), (0, 2.1, 0.15), body)
    k_eyes(k, "Body", 1.25, -0.55, 0.32, 0.36, brow=INK, glow=glow)
    k.box("Body", (0.45, 0.06, 0.05), (0, 0.88, -0.57), INK)
    for sx in (-1, 1):
        k.box("Body", (0.1, 0.25, 0.1), (sx * 0.15, 0.75, -0.6), WHITE)
    for sx, t in SIDES:
        k.bone("Ear" + t, (sx * 0.6, 1.8, 0.2), anim="rot", axis="Z", amp=20 * sx, speed=2)
        k.box("Ear" + t, (0.7, 0.12, 0.5), (sx * 0.95, 1.9, 0.2), darken(body, 0.2), rot=(0, 0, sx * 25))
    k.bone("Cape", (0, 0.5, 0.1), anim="rot", axis="Y", amp=10, speed=1)
    k.box("Cape", (1.6, 0.45, 1.6), (0, 0.35, 0.1), cape)
    k.box("Cape", (2.1, 0.4, 2.1), (0, -0.05, 0.1), cape, rot=(0, 45, 0))
    k.box("Cape", (2.5, 0.25, 2.5), (0, -0.4, 0.1), darken(cape, 0.25))
    for i in range(8):
        a = i / 8 * math.tau
        k.box("Cape", (0.12, 0.4, 0.12), (math.cos(a) * 1.2, -0.65, 0.1 + math.sin(a) * 1.2), WHITE)
        if i % 2 == 0:
            k.box("Cape", (0.12, 0.08, 0.12), (math.cos(a) * 0.75, 0.6, 0.1 + math.sin(a) * 0.75), glow, mat="n")
    k_rarity(k, stars, glow, 2.3)


def coral_golem(c, s, stars, rock, coral, glow):
    """A walking coral reef: boulder body, glowing heart, barnacled fists, coral growing out of it."""
    k = K(c, s * 0.9)
    k.box("Body", (2.0, 1.5, 1.3), (0, 0.9, 0.1), rock)
    k.box("Body", (1.6, 0.6, 1.1), (0, 0.0, 0.1), darken(rock, 0.1))
    k.box("Body", (0.7, 0.7, 0.08), (0, 1.0, -0.56), darken(rock, 0.3))
    k.box("Body", (0.45, 0.45, 0.08), (0, 1.0, -0.6), glow, mat="n")
    for sx in (-1, 1):
        k.box("Body", (0.8, 0.7, 0.8), (sx * 1.2, 1.5, 0.1), lighten(rock, 0.1))
        k.box("Body", (0.14, 0.55, 0.14), (sx * 1.3, 2.05, 0.1), coral, rot=(0, 0, -sx * 15))
        k.box("Body", (0.12, 0.35, 0.12), (sx * 1.48, 2.2, 0.1), coral, rot=(0, 0, sx * 30))
        k.box("Body", (0.16, 0.16, 0.16), (sx * 1.35, 2.38, 0.1), glow, mat="n")
    for (x, y) in ((-0.6, 0.5), (0.65, 1.35), (-0.5, 1.4)):
        k.box("Body", (0.22, 0.18, 0.1), (x, y, -0.58), lighten(rock, 0.45))
    k.box("Body", (0.1, 0.55, 0.06), (0.4, 0.45, -0.58), (90, 170, 90))
    k.bone("Head", (0, 1.65, 0), anim="rot", axis="Y", amp=6, speed=1)
    k.box("Head", (1.1, 0.85, 1.0), (0, 2.05, -0.05), rock)
    k.box("Head", (1.15, 0.2, 0.3), (0, 2.28, -0.45), darken(rock, 0.25))
    k_eyes(k, "Head", 2.05, -0.55, 0.27, 0.24, glow=glow)
    k.box("Head", (0.4, 0.06, 0.05), (0, 1.8, -0.57), INK)
    for (x, h, r) in ((0.3, 0.5, -15), (-0.25, 0.4, 20)):
        k.box("Head", (0.14, h, 0.14), (x, 2.47 + h / 2, 0), coral, rot=(0, 0, r))
        k.box("Head", (0.16, 0.16, 0.16), (x * 1.3, 2.5 + h, 0), glow, mat="n")
    for sx, t in SIDES:
        ph = 0 if sx < 0 else math.pi
        k.bone("Arm" + t, (sx * 1.2, 1.35, 0.1), anim="rot", axis="X", amp=10, speed=1, phase=ph,
               swim=dict(anim="rot", axis="X", amp=32, speed=2, phase=ph))
        k.box("Arm" + t, (0.65, 1.0, 0.65), (sx * 1.35, 0.75, 0.1), rock)
        k.box("Arm" + t, (0.95, 0.8, 0.95), (sx * 1.4, 0.0, 0.0), darken(rock, 0.15))
        k.box("Arm" + t, (0.2, 0.2, 0.2), (sx * 1.4, 0.25, -0.5), lighten(rock, 0.45))
    k_legs(k, [(-0.5, -0.3, 0.1), (0.5, -0.3, 0.1)], (0.7, 0.65, 0.8), rock, foot=darken(rock, 0.2), amp=10)
    k_rarity(k, stars, glow, 3.0)


def tide_king(c, s, stars, water, tail, gold, glow):
    """A living-water merking: see-through body with a glowing heart, foam beard, crown and trident."""
    k = K(c, s * 0.9)
    k.bob(0.12)
    k.box("Body", (1.1, 0.7, 0.9), (0, 0.35, 0.05), tail)
    k.box("Body", (1.3, 0.15, 1.0), (0, 0.72, 0.05), gold, mat="m")
    k.box("Body", (1.4, 1.1, 0.85), (0, 1.3, 0), water, mat="g")
    k.box("Body", (0.45, 0.45, 0.45), (0, 1.35, 0), glow, mat="n")
    for sx in (-1, 1):
        k.box("Body", (0.55, 0.3, 0.6), (sx * 0.8, 1.85, 0), gold, mat="m")
    k.bone("Head", (0, 1.85, 0), anim="rot", axis="Y", amp=6, speed=1)
    k.box("Head", (0.95, 0.95, 0.9), (0, 2.35, -0.05), water, mat="g")
    k_eyes(k, "Head", 2.42, -0.5, 0.22, 0.22, glow=glow, brow=WHITE)
    k.box("Head", (0.8, 0.35, 0.3), (0, 1.95, -0.45), WHITE)
    k.box("Head", (0.5, 0.3, 0.25), (0, 1.7, -0.45), WHITE)
    k.box("Head", (1.0, 0.18, 0.95), (0, 2.9, -0.05), gold, mat="m")
    for x in (-0.36, -0.18, 0, 0.18, 0.36):
        k.box("Head", (0.12, 0.45 if x == 0 else 0.3, 0.12), (x, 3.1, -0.45), gold, mat="m")
    k.box("Head", (0.16, 0.16, 0.06), (0, 2.9, -0.54), glow, mat="n")
    k.bone("ArmR", (0.85, 1.75, 0), anim="rot", axis="Z", amp=6, speed=1)
    k.box("ArmR", (0.38, 0.95, 0.38), (1.0, 1.25, 0), water, mat="g")
    k.box("ArmR", (0.4, 0.35, 0.4), (1.0, 0.7, -0.1), water, mat="g")
    k.box("ArmR", (0.12, 2.8, 0.12), (1.0, 1.2, -0.35), gold, mat="m")
    k.box("ArmR", (0.55, 0.1, 0.12), (1.0, 2.55, -0.35), gold, mat="m")
    for x in (0.78, 1.0, 1.22):
        k.box("ArmR", (0.1, 0.5 if x == 1.0 else 0.4, 0.1), (x, 2.82, -0.35), gold, mat="m")
        k.box("ArmR", (0.12, 0.12, 0.12), (x, 3.1 if x == 1.0 else 3.05, -0.35), glow, mat="n")
    k.bone("ArmL", (-0.85, 1.75, 0), anim="rot", axis="X", amp=15, speed=1)
    k.box("ArmL", (0.38, 0.9, 0.38), (-1.0, 1.3, 0), water, mat="g")
    k.ball("ArmL", 0.45, (-1.05, 0.75, -0.3), glow, mat="n")
    k.bone("T1", (0, 0.1, 0.1), anim="rot", axis="X", amp=10, speed=1)
    k.box("T1", (0.9, 0.6, 0.85), (0, -0.15, 0.25), tail)
    k.bone("T2", (0, -0.4, 0.45), parent="T1", anim="rot", axis="X", amp=10, speed=1, phase=-0.8)
    k.box("T2", (0.7, 0.5, 0.75), (0, -0.55, 0.75), darken(tail, 0.1))
    k.bone("T3", (0, -0.7, 1.05), parent="T2", anim="rot", axis="X", amp=12, speed=1, phase=-1.6)
    k.box("T3", (0.5, 0.4, 0.6), (0, -0.75, 1.3), tail)
    for sx in (-1, 1):
        k.box("T3", (0.75, 0.1, 0.45), (sx * 0.35, -0.75, 1.7), lighten(water, 0.2), rot=(0, -sx * 25, 0), mat="g")
    k.bone("Swirl", (0, 0.4, 0.1), anim="spin", axis="Y", amp=0, speed=1)
    for i in range(6):
        a = i / 6 * math.tau
        k.box("Swirl", (0.35, 0.12, 0.2), (math.cos(a) * 1.0, 0.4 + (i % 2) * 0.15, 0.1 + math.sin(a) * 1.0),
              lighten(water, 0.3), rot=(0, -math.degrees(a) - 90, 0), mat="g")
    k_rarity(k, stars, glow, 3.4)


def thunderbird(c, s, stars, body, belly, accent, glow):
    """A storm bird: hooked gold beak, lightning crest, huge two-jointed wings and a fan tail."""
    k = K(c, s * 0.9)
    k.bob(0.25)
    k.box("Body", (1.4, 1.4, 1.6), (0, 0.6, 0.2), body)
    k.box("Body", (1.0, 0.9, 0.3), (0, 0.5, -0.62), belly)
    k.box("Body", (0.12, 0.45, 0.06), (0.05, 0.62, -0.79), glow, rot=(0, 0, -25), mat="n")
    k.box("Body", (0.12, 0.35, 0.06), (-0.02, 0.3, -0.79), glow, rot=(0, 0, 25), mat="n")
    k.bone("Head", (0, 1.15, -0.3), anim="rot", axis="X", amp=6, speed=1,
           swim=dict(anim="rot", axis="X", amp=12, speed=2, phase=0))
    k.box("Head", (1.05, 1.0, 1.0), (0, 1.75, -0.55), body)
    k.box("Head", (0.5, 0.35, 0.65), (0, 1.6, -1.3), GOLDC)
    k.box("Head", (0.3, 0.3, 0.2), (0, 1.48, -1.65), darken(GOLDC, 0.15))
    k_eyes(k, "Head", 1.97, -1.06, 0.32, 0.26, brow=INK)
    k.bone("Beak", (0, 1.45, -1.0), parent="Head", anim="rot", axis="X", amp=4, speed=1,
           swim=dict(anim="rot", axis="X", amp=16, speed=4, phase=0))
    k.box("Beak", (0.4, 0.18, 0.5), (0, 1.38, -1.3), darken(GOLDC, 0.2))
    for i, a in enumerate((20, 40, 60)):
        r = math.radians(a)
        h = 0.7 + i * 0.1
        k.box("Head", (0.15, h, 0.3), (0, 2.2 + math.cos(r) * h / 2, -0.55 + math.sin(r) * h / 2), glow,
              rot=(a, 0, 0), mat="n")
    for sx, t in SIDES:
        k.bone("Wing" + t, (sx * 0.65, 1.0, 0.1), anim="rot", axis="Z", amp=25 * sx, speed=1,
               swim=dict(anim="rot", axis="Z", amp=40 * sx, speed=2, phase=0))
        k.box("Wing" + t, (1.4, 0.22, 0.6), (sx * 1.35, 1.25, 0.1), body, rot=(0, 0, sx * 20))
        for j in range(3):
            x = sx * (0.9 + j * 0.45)
            ln = 1.1 + j * 0.15
            k.box("Wing" + t, (0.32, 0.1, ln), (x, 1.1 + j * 0.17, 0.1 + ln / 2), accent if j % 2 else body)
            k.box("Wing" + t, (0.3, 0.11, 0.25), (x, 1.1 + j * 0.17, 0.15 + ln), glow, mat="n")
        k.bone("WingTip" + t, (sx * 2.0, 1.45, 0.1), parent="Wing" + t, anim="rot", axis="Z", amp=15 * sx, speed=1,
               phase=-0.7)
        k.box("WingTip" + t, (0.9, 0.18, 0.5), (sx * 2.4, 1.6, 0.1), body, rot=(0, 0, sx * 12))
        k.box("WingTip" + t, (0.35, 0.1, 1.6), (sx * 2.6, 1.62, 0.8), accent)
        k.box("WingTip" + t, (0.33, 0.11, 0.3), (sx * 2.6, 1.62, 1.6), glow, mat="n")
    k.bone("TailF", (0, 0.4, 0.95), anim="rot", axis="X", amp=8, speed=1)
    for j in range(5):
        a = (j - 2) * 20
        r = math.radians(a)
        k.box("TailF", (0.22, 0.08, 1.4), (math.sin(r) * 0.7, 0.35, 1.0 + math.cos(r) * 0.7),
              accent if j % 2 else body, rot=(0, a, 0))
        k.box("TailF", (0.24, 0.09, 0.22), (math.sin(r) * 1.4, 0.35, 1.0 + math.cos(r) * 1.4), glow, rot=(0, a, 0), mat="n")
    k_legs(k, [(-0.35, -0.1, 0.2), (0.35, -0.1, 0.2)], (0.2, 0.55, 0.2), GOLDC, foot=darken(GOLDC, 0.2), amp=8)
    k_rarity(k, stars, glow, 3.0, z=-0.4, orbit_y=1.0, orbit_r=2.6)


def island_turtle(c, s, stars, shell, skin, coral, glow):
    """An ancient turtle with a little island on its back: sand, a palm, coral spires, a treasure chest."""
    k = K(c, s)
    k.box("Body", (2.6, 0.8, 3.0), (0, 0.3, 0.3), shell)
    k.box("Body", (2.9, 0.25, 3.3), (0, -0.05, 0.3), darken(shell, 0.2))
    k.box("Body", (2.3, 0.2, 2.6), (0, -0.25, 0.3), (250, 235, 180))
    k.box("Body", (2.2, 0.55, 2.5), (0, 0.95, 0.3), lighten(shell, 0.1))
    k.box("Body", (1.6, 0.3, 1.8), (0, 1.3, 0.35), (240, 215, 150))
    for sx in (-1, 1):
        for z in (-0.5, 0.3, 1.1):
            k.box("Body", (0.06, 0.4, 0.6), (sx * 1.32, 0.35, z), darken(shell, 0.25))
    brown, green = (130, 85, 45), (70, 190, 80)
    k.bone("Palm", (0.3, 1.45, 0.6), anim="rot", axis="Z", amp=5, speed=1)
    k.box("Palm", (0.2, 0.5, 0.2), (0.3, 1.7, 0.6), brown)
    k.box("Palm", (0.18, 0.5, 0.18), (0.38, 2.15, 0.6), brown, rot=(0, 0, -10))
    k.box("Palm", (0.16, 0.45, 0.16), (0.5, 2.55, 0.6), brown, rot=(0, 0, -20))
    for sx in (-1, 1):
        k.box("Palm", (0.9, 0.08, 0.3), (0.55 + sx * 0.45, 2.75, 0.6), green, rot=(0, 0, -sx * 25))
        k.box("Palm", (0.3, 0.08, 0.9), (0.55, 2.75, 0.6 + sx * 0.45), green, rot=(sx * 25, 0, 0))
    k.ball("Palm", 0.18, (0.48, 2.68, 0.5), brown)
    for (x, z, h) in ((-0.45, 0.0, 0.6), (-0.65, 0.7, 0.45), (-0.2, -0.3, 0.35)):
        k.box("Body", (0.2, h, 0.2), (x, 1.45 + h / 2, z), coral)
        k.box("Body", (0.22, 0.22, 0.22), (x, 1.5 + h, z), glow, mat="n")
    k.box("Body", (0.45, 0.3, 0.32), (-0.2, 1.6, 1.0), brown)
    k.box("Body", (0.47, 0.08, 0.34), (-0.2, 1.77, 1.0), GOLDC, mat="m")
    k.ball("Body", 0.14, (0.05, 1.5, 1.1), GOLDC, mat="n")
    k.box("Body", (0.5, 0.9, 0.12), (0.6, 0.8, 1.62), (160, 220, 255), mat="g")
    k.bone("Head", (0, 0.2, -1.1), anim="rot", axis="X", amp=6, speed=1)
    k.box("Head", (0.8, 0.6, 0.7), (0, 0.25, -1.35), skin)
    k.box("Head", (1.2, 0.95, 1.1), (0, 0.5, -1.95), skin)
    k_eyes(k, "Head", 0.7, -2.5, 0.33, 0.3)
    for sx in (-1, 1):
        k.box("Head", (0.4, 0.12, 0.1), (sx * 0.33, 0.95, -2.52), WHITE, rot=(0, 0, -sx * 10))
    k_smile(k, "Head", 0.3, -2.5, 0.45)
    for sx, t in SIDES:
        k.bone("FlipF" + t, (sx * 1.2, 0.0, -0.6), anim="rot", axis="Y", amp=20 * sx, speed=1,
               swim=dict(anim="rot", axis="Y", amp=35 * sx, speed=2, phase=0))
        k.box("FlipF" + t, (1.5, 0.18, 0.7), (sx * 1.85, -0.1, -0.75), skin, rot=(0, sx * 20, 0))
        k.bone("FlipB" + t, (sx * 1.1, 0.0, 1.3), anim="rot", axis="Y", amp=14 * sx, speed=1, phase=math.pi)
        k.box("FlipB" + t, (0.9, 0.15, 0.6), (sx * 1.45, -0.1, 1.5), skin, rot=(0, -sx * 25, 0))
    k.box("Body", (0.4, 0.3, 0.5), (0, 0.0, 2.0), skin)
    k_rarity(k, stars, glow, 2.9, z=0.3, orbit_y=1.0, orbit_r=2.6)


def celestial_koi(c, s, stars, body, patch, fin, glow):
    """A heavenly koi: patched scales, glowing whiskers, veil fins and six angel wings."""
    k = K(c, s * 0.9)
    k.bob(0.25)
    k.box("Body", (1.3, 1.3, 2.0), (0, 0.7, 0.2), body)
    k.box("Body", (0.9, 0.08, 0.8), (0.1, 1.36, 0.0), patch)
    k.box("Body", (0.6, 0.08, 0.6), (-0.2, 1.36, 0.8), patch)
    k.box("Body", (0.06, 0.6, 0.7), (0.66, 0.8, 0.5), patch)
    k.box("Body", (0.06, 0.5, 0.6), (-0.66, 0.6, -0.2), patch)
    k.box("Body", (1.15, 1.1, 0.8), (0, 0.7, -1.15), body)
    k.box("Body", (0.8, 0.08, 0.5), (0, 1.26, -1.0), patch)
    k.box("Body", (0.45, 0.3, 0.15), (0, 0.45, -1.6), BLUSH)
    k_eyes(k, "Body", 0.88, -1.56, 0.38, 0.28)
    for sx, t in SIDES:
        k.bone("Whisk" + t, (sx * 0.25, 0.45, -1.6), anim="rot", axis="Y", amp=18 * sx, speed=1)
        k.box("Whisk" + t, (0.06, 0.06, 0.9), (sx * 0.475, 0.45, -1.99), glow, rot=(0, -sx * 30, 0), mat="n")
        k.bone("Fin" + t, (sx * 0.6, 0.3, -0.5), anim="rot", axis="Z", amp=15 * sx, speed=1)
        k.box("Fin" + t, (0.9, 0.06, 0.7), (sx * 1.0, 0.15, -0.4), fin, rot=(0, 0, -sx * 30), mat="g")
    k.box("Body", (0.08, 0.6, 1.4), (0, 1.6, 0.3), fin, mat="g")
    out, zend = k_tail(k, (0, 0.7, 1.2), [((1.0, 1.0, 0.7), body, "p"), ((0.7, 0.75, 0.6), patch, "p")], amp=18)
    k.box(out[-1][0], (0.08, 1.4, 1.3), (0, 1.15, zend + 0.45), fin, rot=(35, 0, 0), mat="g")
    k.box(out[-1][0], (0.08, 1.2, 1.1), (0, 0.25, zend + 0.35), fin, rot=(-35, 0, 0), mat="g")
    for p, (y, z, ang, ln) in enumerate(((1.25, -0.2, 35, 1.9), (0.95, 0.5, 10, 1.6), (0.6, 1.0, -20, 1.3))):
        r = math.radians(ang)
        for sx, t in SIDES:
            n = "Wing%d%s" % (p + 1, t)
            k.bone(n, (sx * 0.6, y, z), anim="rot", axis="Z", amp=20 * sx, speed=1, phase=p * 0.9,
                   swim=dict(anim="rot", axis="Z", amp=36 * sx, speed=2, phase=p * 0.9))
            k.box(n, (ln, 0.1, 0.55), (sx * (0.6 + math.cos(r) * ln / 2), y + math.sin(r) * ln / 2, z), glow,
                  rot=(0, 0, sx * ang), mat="n")
            k.box(n, (ln * 0.7, 0.08, 0.45), (sx * (0.6 + math.cos(r) * ln * 0.35), y + math.sin(r) * ln * 0.35 - 0.08,
                                              z + 0.4), fin, rot=(0, 0, sx * ang), mat="g")
    k_rarity(k, stars, glow, 2.4, z=-0.2, orbit_y=0.8, orbit_r=2.6)


# ---------------------------------------------------------------------------
# The roster. 1-3 stars are sea creatures, each element line its own family, all mean-looking;
# every 4 and 5 star is a true sea dragon (the prize you work toward).
#   Tide:  axolotl -> narwhal -> sea toad
#   Coral: starfish -> isopod -> lionfish
#   Storm: jellyfish -> electric eel -> mantis shrimp
#   Abyss: anglerfish -> octopus -> vampire squid
# Hybrids: leafy seahorse, whale, shark, crab, skull hermit, manta (each with a 3* evolution).
# Kits not in the roster right now (tide_king, coral_golem, thunderbird, island_turtle,
# celestial_koi, eel(serpent=True), octopus(king=True)) are kept for events or future species.
# ---------------------------------------------------------------------------
# --- 1 star (commons: the winch eggs) -------------------------------------------------
c = creature("Splashfin", "Splashfin")
axolotl(c, 1.05, 1, (95, 180, 255), (255, 140, 190), (205, 238, 255), (40, 120, 220))

c = creature("Reefback", "Reefling")
starfish(c, 1.05, 1, (255, 120, 150), (255, 225, 200), (120, 210, 160))

c = creature("Zapjelly", "Zappy")
jellyfish(c, 1.05, 1, (255, 225, 90), (255, 255, 170), (255, 170, 40), (255, 250, 140))

c = creature("Gloomeel", "Gloomy")
anglerfish(c, 1.05, 1, (95, 60, 170), (185, 155, 230), (60, 35, 120), (160, 255, 220))

# --- 2 stars (rares + hybrids) -----------------------------------------------------
c = creature("Wavecrest", "Wavecrest")
narwhal(c, 1.25, 2, (70, 140, 230), (210, 240, 255), (40, 100, 200), (240, 235, 215), glow=(150, 240, 255))

c = creature("Shellguard", "Shellguard")
isopod(c, 1.25, 2, (240, 110, 100), (255, 215, 190), (255, 240, 220))

c = creature("Voltfin", "Voltfin")
eel(c, 1.25, 2, (50, 70, 190), (200, 210, 255), (255, 225, 40), (255, 240, 90))

c = creature("Inkling", "Inkling")
octopus(c, 1.25, 2, (140, 70, 210), (210, 170, 240), (230, 90, 200), glow=(255, 120, 230))

c = creature("Kelpdrake", "Kelpdrake")
seahorse(c, 1.25, 2, (60, 180, 150), (220, 245, 210), (110, 210, 80))

c = creature("Thunderwhale", "Thunderwhale")
whale(c, 1.25, 2, (60, 115, 220), (225, 240, 255), (255, 230, 40), (255, 240, 120))

c = creature("Inkshark", "Inkshark")
shark(c, 1.25, 2, (70, 80, 150), (225, 225, 240), (140, 90, 220))

c = creature("Sparkcrab", "Sparkcrab")
crab(c, 1.25, 2, (255, 125, 80), (255, 230, 200), (255, 160, 90), glow=(255, 240, 90))

c = creature("Bonereef", "Bonereef")
skull_hermit(c, 1.25, 2, (240, 235, 215), (150, 90, 210), (190, 120, 255))

c = creature("Voidray", "Voidray")
manta(c, 1.25, 2, (60, 30, 110), (220, 210, 245), (255, 220, 60), (255, 230, 90))

# --- 3 stars (epics) ---------------------------------------------------------------
c = creature("Tsunamaw", "Tsunamaw")
sea_toad(c, 1.45, 3, (40, 110, 220), (190, 230, 255), (120, 220, 255), (150, 240, 255))

c = creature("Coralord", "Coralord")
lionfish(c, 1.45, 3, (235, 80, 120), (255, 235, 225), (255, 160, 190), (255, 170, 215))

c = creature("Thunderjaw", "Thunderjaw")
mantis_shrimp(c, 1.45, 3, (255, 200, 40), (255, 240, 190), (60, 90, 220), (130, 220, 255))

c = creature("Nightfang", "Nightfang")
vampire_squid(c, 1.45, 3, (60, 25, 90), (120, 30, 90), (220, 90, 255))

# --- 3 star hybrid evolutions (two of the same hybrid fused) -------------------------
c = creature("Kelpking", "Kelp King")
seahorse(c, 1.45, 3, (30, 150, 130), (210, 250, 220), (120, 230, 90), glow=(170, 255, 140), king=True)

c = creature("TempestWhale", "Tempest Whale")
whale(c, 1.45, 3, (45, 70, 170), (220, 235, 255), (255, 230, 60), (255, 245, 120), tempest=True)

c = creature("AbyssShark", "Abyss Shark")
shark(c, 1.45, 3, (40, 40, 100), (200, 200, 230), (150, 90, 255), glow=(170, 110, 255), abyss=True)

c = creature("Voltclaw", "Voltclaw")
crab(c, 1.45, 3, (230, 90, 60), (255, 225, 190), (255, 140, 80), glow=(255, 245, 110), big=True)

c = creature("Bonelord", "Bonelord")
skull_hermit(c, 1.45, 3, (240, 235, 215), (120, 60, 180), (210, 130, 255), lord=True)

c = creature("Nightray", "Nightray")
manta(c, 1.45, 3, (30, 15, 70), (190, 170, 240), (255, 220, 60), (255, 235, 90), night=True)

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

# --- 6 star Divine: Abyss Rod only, and they only fuse with their own kind -------------
c = creature("TideSovereign", "Tide Sovereign")
sovereign(c, 1.05)

c = creature("EternalSovereign", "Eternal Sovereign")
sovereign(c, 1.2, evolved=True)

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
GOLD = (255, 200, 60)
GOLD2 = (220, 160, 40)
IRONB, RIVET = (70, 72, 86), (160, 162, 176)
WOODB = (140, 90, 50)

c = creature("Clawbeard", "Captain Clawbeard", "boss")
# A crab pirate captain: a ridged, spotted red shell, a bushy white beard with gold-beaded braids
# and a curled moustache, one angry eye and an eyepatch, a black tricorn with gold trim, a skull
# and crossbones and a feather, gold epaulettes, huge snapping pincers with gold cuffs, five legs
# and a wooden peg leg.
CB_BELLY, CB_SPOT, BEARD = (250, 150, 110), (255, 190, 160), (245, 245, 245)
c.box("Body", (1.9, 1.0, 1.5), (0, 0.1, 0), R1)
c.box("Body", (1.6, 0.22, 1.25), (0, 0.66, 0.05), R2)                      # top shell plate
for x in (-0.45, 0, 0.45):
    c.box("Body", (0.16, 0.1, 1.1), (x, 0.8, 0.1), R1)                     # shell ridges
for (x, z) in ((-0.7, 0.45), (0.65, 0.5), (-0.25, 0.6), (0.8, -0.05)):
    c.box("Body", (0.22, 0.06, 0.22), (x, 0.79, z), CB_SPOT)               # spots
c.box("Body", (1.7, 0.18, 1.3), (0, -0.42, 0), CB_BELLY)                   # belly
for s in (-1, 1):
    for z in (-0.25, 0.35):
        c.box("Body", (0.18, 0.3, 0.18), (s * 1.0, 0.4, z), R2, rot=(0, 0, -s * 30))   # rim spikes
# face: one angry eye, one eyepatch with its strap
c.box("Body", (0.28, 0.31, 0.08), (-0.4, 0.45, -0.79), WHITE)
c.box("Body", (0.14, 0.17, 0.06), (-0.36, 0.42, -0.84), INK)
c.box("Body", (0.31, 0.09, 0.08), (-0.4, 0.63, -0.82), INK, rot=(0, 0, -18))
c.box("Body", (0.34, 0.3, 0.08), (0.4, 0.45, -0.8), INK)
c.box("Body", (0.6, 0.06, 0.05), (0.68, 0.56, -0.79), INK, rot=(0, 0, 20))
# moustache, curled up at the ends
for s in (-1, 1):
    c.box("Body", (0.45, 0.14, 0.12), (s * 0.27, 0.22, -0.88), (215, 215, 225), rot=(0, 0, s * 15))
    c.box("Body", (0.12, 0.18, 0.1), (s * 0.52, 0.32, -0.88), (215, 215, 225))
# a short bushy beard that sways on its own bone, two little braids with gold beads
c.bone("Beard", (0, 0.1, -0.8), anim="rot", axis="X", amp=6, speed=1,
       swim=dict(anim="rot", axis="X", amp=12, speed=2, phase=0))
c.box("Beard", (1.2, 0.32, 0.15), (0, -0.0, -0.82), BEARD)
c.box("Beard", (0.75, 0.22, 0.15), (0, -0.25, -0.84), BEARD, rot=(10, 0, 0))
for s in (-1, 1):
    c.box("Beard", (0.11, 0.18, 0.11), (s * 0.22, -0.38, -0.86), (225, 225, 232))
    c.box("Beard", (0.14, 0.09, 0.14), (s * 0.22, -0.5, -0.86), GOLD)      # braid beads
# tricorn hat: brim, turned-up sides and back, crown, gold band, skull badge, a feather
c.box("Body", (2.1, 0.2, 1.7), (0, 0.9, 0), INK)
for s in (-1, 1):
    c.box("Body", (0.15, 0.55, 1.5), (s * 1.0, 1.12, 0), INK, rot=(0, 0, -s * 20))
    c.box("Body", (0.17, 0.08, 1.52), (s * 1.08, 1.38, 0), GOLD, rot=(0, 0, -s * 20))
c.box("Body", (1.9, 0.55, 0.15), (0, 1.12, 0.85), INK, rot=(20, 0, 0))
c.box("Body", (1.3, 0.6, 1.1), (0, 1.3, 0), INK)
c.box("Body", (1.34, 0.12, 1.14), (0, 1.06, 0), GOLD)
c.box("Body", (0.36, 0.3, 0.06), (0, 1.32, -0.58), WHITE)                  # skull
for s in (-1, 1):
    c.box("Body", (0.08, 0.08, 0.04), (s * 0.08, 1.35, -0.615), INK)
    c.box("Body", (0.55, 0.08, 0.05), (0, 1.32, -0.59), WHITE, rot=(0, 0, s * 35))   # crossbones
c.bone("Plume", (0.45, 1.55, 0.3), anim="rot", axis="X", amp=12, speed=1,
       swim=dict(anim="rot", axis="X", amp=24, speed=3, phase=0))
c.box("Plume", (0.12, 0.9, 0.3), (0.55, 1.95, 0.45), (235, 240, 255), rot=(-20, 0, -15))
c.box("Plume", (0.1, 0.3, 0.22), (0.68, 2.35, 0.62), (255, 90, 90), rot=(-30, 0, -15))
# gold epaulettes
for s in (-1, 1):
    c.box("Body", (0.45, 0.12, 0.4), (s * 0.8, 0.64, -0.35), GOLD)
    c.box("Body", (0.5, 0.14, 0.08), (s * 0.8, 0.53, -0.56), GOLD2)
# pincers: arm, gold cuff, palm with spikes, a fixed top finger and a snapping lower one
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Claw" + tag, (s * 0.9, 0.1, -0.4), anim="rot", axis="Y", amp=14 * s, speed=2,
           swim=dict(anim="rot", axis="Y", amp=35 * s, speed=4, phase=0))
    c.box("Claw" + tag, (0.45, 0.35, 0.35), (s * 1.1, 0.12, -0.5), R2)
    c.box("Claw" + tag, (0.5, 0.5, 0.15), (s * 1.3, 0.15, -0.55), GOLD, mat="m")
    c.box("Claw" + tag, (0.75, 0.7, 0.6), (s * 1.35, 0.2, -0.9), R2)
    c.box("Claw" + tag, (0.3, 0.25, 0.75), (s * 1.45, 0.42, -1.45), R2)
    c.box("Claw" + tag, (0.22, 0.22, 0.22), (s * 1.45, 0.38, -1.85), (255, 120, 100))
    for k in range(2):
        c.box("Claw" + tag, (0.12, 0.25, 0.12), (s * (1.55 + k * 0.12), 0.62, -0.75 - k * 0.25), (255, 120, 100),
              rot=(0, 0, -s * 25))
    c.bone("Pinch" + tag, (s * 1.35, 0.05, -1.1), parent="Claw" + tag, anim="rot", axis="X", amp=10, speed=2,
           swim=dict(anim="rot", axis="X", amp=30, speed=4, phase=0))
    c.box("Pinch" + tag, (0.3, 0.22, 0.7), (s * 1.35, 0.0, -1.45), R1)
# five crab legs and a wooden peg leg with an iron band
for i, (x, z) in enumerate(((-0.85, -0.1), (0.85, -0.1), (-0.85, 0.3), (0.85, 0.3), (-0.8, 0.65), (0.8, 0.65))):
    name = "Leg%d" % (i + 1)
    s = 1 if x > 0 else -1
    c.bone(name, (x, -0.3, z), anim="rot", axis="X", amp=22, speed=2, phase=0 if i % 2 == 0 else math.pi)
    if i == 5:
        c.box(name, (0.2, 0.5, 0.2), (x * 1.1, -0.55, z), WOODB)
        c.box(name, (0.26, 0.1, 0.26), (x * 1.1, -0.45, z), IRONB, mat="m")
    else:
        c.box(name, (0.22, 0.3, 0.22), (x * 1.12, -0.4, z), R2)
        c.box(name, (0.17, 0.35, 0.17), (x * 1.22, -0.62, z), R1, rot=(0, 0, s * 12))

c = creature("Hammerjaw", "Hammerjaw", "boss")
# A battle-scarred hammerhead: a striped back, pale belly, gill slits and claw scars, a layered
# hammer with glowing red eyes under angry brows, a toothy mouth and a riveted iron lower jaw,
# flapping side fins, two dorsal fins and a long tail ending in a crescent fin.
H1, H2, H3 = (110, 130, 150), (220, 225, 235), (78, 94, 115)   # back, belly, stripes
HSCAR, HGUM = (205, 214, 224), (175, 45, 65)
c.box("Body", (1.4, 1.3, 2.4), (0, 0.2, 0.3), H1)
c.box("Body", (1.2, 0.45, 2.1), (0, -0.35, 0.2), H2)
for z in (-0.25, 0.35, 0.95):
    c.box("Body", (1.42, 0.12, 0.25), (0, 0.8, z), H3)                     # back stripes
for s in (-1, 1):
    for k in range(3):
        c.box("Body", (0.06, 0.5, 0.08), (s * 0.71, 0.25, -0.6 + k * 0.18), H3)   # gills
c.box("Body", (0.05, 0.45, 0.06), (0.71, 0.45, 0.3), HSCAR, rot=(35, 0, 0))       # claw scars
c.box("Body", (0.05, 0.4, 0.06), (0.71, 0.42, 0.5), HSCAR, rot=(35, 0, 0))
c.box("Body", (0.05, 0.5, 0.06), (-0.71, 0.4, 0.8), HSCAR, rot=(-30, 0, 0))
# dorsal fin with a darker tip
c.box("Body", (0.25, 1.1, 0.9), (0, 1.25, 0.4), H1, rot=(25, 0, 0))     # swept back
c.box("Body", (0.22, 0.4, 0.4), (0, 1.8, 0.7), H3, rot=(40, 0, 0))
# the hammer: a layered bar with eye housings at the ends
c.box("Body", (2.6, 0.55, 0.75), (0, 0.5, -1.2), H1)
c.box("Body", (2.4, 0.12, 0.6), (0, 0.82, -1.2), H3)
c.box("Body", (2.4, 0.15, 0.6), (0, 0.18, -1.2), H2)
c.box("Body", (0.06, 0.4, 0.06), (-0.8, 0.55, -1.58), HSCAR, rot=(0, 0, 30))
for s in (-1, 1):
    c.box("Body", (0.35, 0.65, 0.65), (s * 1.35, 0.5, -1.2), H1)
    c.box("Body", (0.34, 0.32, 0.1), (s * 1.15, 0.55, -1.6), (255, 70, 50), mat="n")
    c.box("Body", (0.12, 0.12, 0.06), (s * 1.15, 0.55, -1.66), (255, 220, 90), mat="n")
    c.box("Body", (0.48, 0.1, 0.12), (s * 1.12, 0.77, -1.6), INK, rot=(0, 0, s * 15))
    c.box("Body", (0.1, 0.08, 0.06), (s * 0.25, 0.62, -1.6), INK)            # nostrils
# the mouth: a red gum line and a row of upper teeth under the hammer
c.box("Body", (1.0, 0.1, 0.5), (0, 0.11, -1.3), HGUM)
for k in range(6):
    c.box("Body", (0.12, 0.22, 0.12), (-0.45 + k * 0.18, 0.05, -1.5), WHITE)
# the iron jaw: snaps in battle
c.bone("Jaw", (0, -0.1, -0.7), anim="rot", axis="X", amp=8, speed=2,
       swim=dict(anim="rot", axis="X", amp=24, speed=4, phase=0))
c.box("Jaw", (1.2, 0.35, 0.8), (0, -0.3, -1.2), H2)
c.box("Jaw", (1.0, 0.08, 0.6), (0, -0.1, -1.2), HGUM)
for k in range(5):
    c.box("Jaw", (0.12, 0.2, 0.12), (-0.4 + k * 0.2, 0.0, -1.52), WHITE)
c.box("Jaw", (1.26, 0.14, 0.86), (0, -0.47, -1.2), IRONB, mat="m")
for x in (-0.45, -0.15, 0.15, 0.45):
    c.box("Jaw", (0.1, 0.1, 0.06), (x, -0.3, -1.62), RIVET, mat="m")
# side fins and small rear fins
fin_pair(c, (1.0, 0.12, 0.6), 0.7, -0.2, -0.1, H1, amp=18, speed=1, rot=(0, -20, -15))
fin_pair(c, (0.5, 0.1, 0.35), 0.5, -0.45, 0.9, H1, amp=14, speed=1, rot=(0, 0, -25), name="Pelvic")
# a long tail: three segments, a second dorsal fin and a crescent tail fin
last, zend = tail_chain(c, (0, 0.25, 1.5), [((1.0, 0.9, 0.8), H1, "p"), ((0.7, 0.65, 0.7), H1, "p"),
                                             ((0.4, 0.45, 0.5), H1, "p")], amp=18)
c.box("Tail1", (1.02, 0.1, 0.2), (0, 0.66, 1.9), H3)
c.box("Tail2", (0.15, 0.4, 0.35), (0, 0.72, 2.6), H1, rot=(30, 0, 0))
c.box(last, (0.2, 1.3, 0.5), (0, 0.85, zend + 0.1), H1, rot=(35, 0, 0))   # crescent, swept back
c.box(last, (0.2, 0.8, 0.4), (0, -0.15, zend), H1, rot=(-30, 0, 0))

c = creature("GhostCaptain", "Ghost Captain", "boss")
# A drowned pirate captain's ghost: a see-through body in a ragged coat with gold buttons, belt
# and epaulettes, glowing eyes in dark sockets, a jagged grin and a wispy beard, a tricorn with
# a skull badge and a glowing plume, a cutlass in one hand and a swinging lantern in the other,
# broken shackles, a trailing tail of wisps, and spirit orbs circling him.
GH, GH2, GLOW = (130, 255, 190), (60, 170, 130), (170, 255, 215)
c.bones[0]["amp"] = 0.25
c.box("Body", (1.5, 2.0, 1.2), (0, 0.6, 0), GH, mat="g")
# coat: front panels, a high collar, gold buttons, belt and buckle, epaulettes
for s in (-1, 1):
    c.box("Body", (0.5, 1.6, 0.1), (s * 0.45, 0.55, -0.64), GH2, mat="g")
    for y in (1.0, 0.7, 0.4):
        c.box("Body", (0.12, 0.12, 0.06), (s * 0.27, y, -0.71), GOLD)
    c.box("Body", (0.5, 0.12, 0.45), (s * 0.85, 1.6, 0), GOLD)
    c.box("Body", (0.5, 0.12, 0.08), (s * 0.85, 1.5, -0.24), GOLD2)
c.box("Body", (1.6, 0.35, 1.3), (0, 1.45, 0), GH2, mat="g")
c.box("Body", (1.56, 0.18, 1.26), (0, 0.2, 0), INK)
c.box("Body", (0.3, 0.24, 0.06), (0, 0.2, -0.65), GOLD)
# ragged coat tails at the back
c.bone("Coat", (0, 0.1, 0.62), anim="rot", axis="X", amp=10, speed=1,
       swim=dict(anim="rot", axis="X", amp=22, speed=3, phase=0))
for (x, h) in ((-0.45, 0.9), (0, 1.1), (0.45, 0.8)):
    c.box("Coat", (0.4, h, 0.1), (x, 0.1 - h / 2, 0.64), GH2, rot=(15, 0, 0), mat="g")
# face: glowing eyes in dark sockets, a jagged grin, a wispy beard
for s in (-1, 1):
    c.box("Body", (0.42, 0.42, 0.04), (s * 0.32, 1.15, -0.615), INK)
eyes(c, "Body", 1.15, -0.62, dx=0.32, s=0.3, glow=(255, 255, 255))
c.box("Body", (0.7, 0.22, 0.06), (0, 0.85, -0.62), INK)
for x in (-0.2, 0, 0.2):
    c.box("Body", (0.1, 0.1, 0.04), (x, 0.92, -0.655), WHITE)
c.bone("Beard", (0, 0.75, -0.64), anim="rot", axis="X", amp=8, speed=1,
       swim=dict(anim="rot", axis="X", amp=16, speed=3, phase=0))
for (x, h) in ((-0.3, 0.5), (0, 0.7), (0.3, 0.5)):
    c.box("Beard", (0.25, h, 0.12), (x, 0.72 - h / 2, -0.68), GH, mat="g")
# tricorn: brim, turned-up sides and back, crown, gold band, skull and crossbones, glowing plume
c.box("Body", (1.9, 0.2, 1.6), (0, 1.75, 0), INK)
for s in (-1, 1):
    c.box("Body", (0.12, 0.5, 1.4), (s * 0.95, 2.0, 0), INK, rot=(0, 0, -s * 20))
c.box("Body", (1.8, 0.5, 0.12), (0, 2.0, 0.8), INK, rot=(20, 0, 0))
c.box("Body", (1.2, 0.7, 1.0), (0, 2.2, 0), INK)
c.box("Body", (1.24, 0.1, 1.04), (0, 1.9, 0), GOLD)
c.box("Body", (0.34, 0.3, 0.06), (0, 2.25, -0.53), WHITE)
for s in (-1, 1):
    c.box("Body", (0.07, 0.07, 0.04), (s * 0.07, 2.28, -0.565), INK)
    c.box("Body", (0.55, 0.08, 0.05), (0, 2.25, -0.54), WHITE, rot=(0, 0, s * 35))
c.bone("Plume", (0.4, 2.5, 0.2), anim="rot", axis="X", amp=14, speed=1,
       swim=dict(anim="rot", axis="X", amp=26, speed=3, phase=0))
c.box("Plume", (0.14, 1.0, 0.35), (0.45, 2.95, 0.35), GLOW, rot=(-25, 0, -10), mat="n")
# arms with gold cuffs, ghostly hands and broken shackles
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Arm" + tag, (s * 0.8, 1.0, 0), anim="rot", axis="Z", amp=16 * s, speed=1,
           swim=dict(anim="rot", axis="X", amp=40, speed=4, phase=0))
    c.box("Arm" + tag, (0.4, 1.2, 0.4), (s * 1.0, 0.5, 0), GH2, mat="g")
    c.box("Arm" + tag, (0.48, 0.2, 0.48), (s * 1.0, 0.0, 0), GOLD)
    c.box("Arm" + tag, (0.5, 0.12, 0.5), (s * 1.0, 0.2, 0), IRONB, mat="m")
    c.box("Arm" + tag, (0.12, 0.22, 0.06), (s * 1.27, 0.05, 0), IRONB, mat="m")
    c.box("Arm" + tag, (0.35, 0.3, 0.35), (s * 1.0, -0.22, 0), GH, mat="g")
# the cutlass: blade, gold guard, dark grip
c.box("ArmR", (0.08, 1.5, 0.22), (1.0, -0.05, -0.55), (210, 215, 225), rot=(70, 0, 0), mat="m")
c.box("ArmR", (0.4, 0.12, 0.3), (1.0, -0.25, -0.08), GOLD)
c.box("ArmR", (0.12, 0.3, 0.12), (1.0, -0.22, 0.08), INK)
# a lantern swinging from the other hand
c.bone("Lantern", (-1.0, -0.35, 0), parent="ArmL", anim="rot", axis="Z", amp=15, speed=1,
       swim=dict(anim="rot", axis="Z", amp=30, speed=3, phase=0))
c.box("Lantern", (0.06, 0.3, 0.06), (-1.0, -0.5, 0), IRONB, mat="m")
c.box("Lantern", (0.42, 0.08, 0.42), (-1.0, -0.66, 0), INK)
c.box("Lantern", (0.34, 0.4, 0.34), (-1.0, -0.9, 0), (120, 255, 170), mat="n")
c.box("Lantern", (0.42, 0.08, 0.42), (-1.0, -1.14, 0), INK)
# a trailing tail of wisps, fading out at the tips
tentacles(c, 5, 0.4, -0.4, GH, length=3, seg=(0.3, 0.35, 0.3), mat="g", tip=(210, 255, 235))
# spirit orbs circling him
c.bone("Orbit", (0, 0.8, 0), anim="spin", axis="Y", amp=0, speed=1)
for i in range(3):
    a = i / 3 * math.tau
    c.ball("Orbit", 0.3, (math.cos(a) * 1.5, 0.8 + (i - 1) * 0.35, math.sin(a) * 1.5), GLOW, mat="n")

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
    c.box("Head", (0.85, 0.2, 0.3), (sx * 0.75, hy + 0.36, z - 3.62), INK, rot=(0, 0, sx * 20))
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
# MINI BOSSES (kind "enemy"): a beefed-up, dressed-up version of each stage's mini-boss mob,
# so depth 8 of a stage looks like a real fight and not just a bigger copy of the wave mobs.
# Same footprint as the mob they replace (the game scales them up by 1.7).
# ===========================================================================
def angry_eye(c, bone, x, y, z, s=0.3, glow=None):
    if glow:
        c.box(bone, (s, s, 0.08), (x, y, z), glow, mat="n")
    else:
        c.box(bone, (s, s * 1.1, 0.08), (x, y, z), WHITE)
        c.box(bone, (s * 0.5, s * 0.6, 0.06), (x - (0.04 if x > 0 else -0.04), y - 0.03, z - 0.05), INK)
    side = 1 if x > 0 else -1
    c.box(bone, (s * 1.15, 0.09, 0.08), (x, y + s * 0.62, z - 0.03), INK, rot=(0, 0, side * 18))


def ring_spikes(c, bone, n, radius, y, length, color, tip=None, skip_front=False, offset=0.0):
    """Horizontal spikes pointing straight out, with optional glowing tips."""
    for i in range(n):
        a = (i + offset) / n * math.tau
        if skip_front and abs(math.sin(a) + 1) < 0.2:   # -Z (the face)
            continue
        x, z = math.cos(a), math.sin(a)
        c.box(bone, (length, 0.16, 0.16), (x * (radius + length / 2), y, z * (radius + length / 2)), color,
              rot=(0, -math.degrees(a), 0))
        if tip:
            c.box(bone, (0.14, 0.14, 0.14), (x * (radius + length + 0.05), y, z * (radius + length + 0.05)), tip, mat="n")


# Ironshell Crab: an armoured crab with a riveted iron helmet, barnacles, eyes on stalks, a scar,
# and one huge claw
c = creature("CrabMini", "Ironshell Crab", "enemy")
c.box("Body", (1.9, 0.9, 1.4), (0, 0.1, 0), R1)
c.box("Body", (1.7, 0.25, 1.2), (0, 0.65, 0.05), IRONB, mat="m")
for x in (-0.6, 0, 0.6):
    c.box("Body", (0.1, 0.1, 0.1), (x, 0.7, -0.57), RIVET, mat="m")
c.box("Body", (0.25, 0.45, 0.25), (0, 0.95, 0.15), RIVET, rot=(0, 45, 0), mat="m")
for (x, z) in ((-0.6, 0.45), (0.5, 0.5), (0.72, 0.1)):
    c.ball("Body", 0.22, (x, 0.82, z), (225, 215, 190))                    # barnacles
c.box("Body", (0.06, 0.4, 0.05), (0.55, 0.2, -0.71), (255, 180, 170), rot=(0, 0, 25))   # scar
c.box("Body", (0.6, 0.1, 0.06), (0, 0.12, -0.72), INK)
for x in (-0.15, 0.15):
    c.box("Body", (0.1, 0.12, 0.05), (x, 0.2, -0.75), WHITE)
for s in (-1, 1):
    c.box("Body", (0.1, 0.35, 0.1), (s * 0.35, 0.95, -0.45), R2)
    c.box("Body", (0.3, 0.3, 0.3), (s * 0.35, 1.2, -0.45), WHITE)
    c.box("Body", (0.16, 0.18, 0.08), (s * 0.33, 1.18, -0.63), INK)
    c.box("Body", (0.34, 0.08, 0.08), (s * 0.35, 1.4, -0.6), INK, rot=(0, 0, s * 18))
for s, tag, k in ((-1, "L", 0.8), (1, "R", 1.25)):
    cx = s * (1.15 + 0.3 * k)
    c.bone("Claw" + tag, (s * 0.9, 0.1, -0.4), anim="rot", axis="Y", amp=14 * s, speed=2,
           swim=dict(anim="rot", axis="Y", amp=30 * s, speed=4, phase=0))
    c.box("Claw" + tag, (0.4, 0.3, 0.3), (s * 1.1, 0.12, -0.5), R2)
    c.box("Claw" + tag, (0.42, 0.42, 0.12), (s * 1.25, 0.15, -0.55), IRONB, mat="m")
    c.box("Claw" + tag, (0.6 * k, 0.55 * k, 0.7 * k), (cx, 0.2, -0.85), R2)
    c.box("Claw" + tag, (0.25 * k, 0.2 * k, 0.55 * k), (cx, 0.2 + 0.3 * k, -0.85 - 0.55 * k), R2)
    c.bone("Pinch" + tag, (cx, 0.0, -0.85 - 0.3 * k), parent="Claw" + tag, anim="rot", axis="X", amp=10, speed=2,
           swim=dict(anim="rot", axis="X", amp=28, speed=4, phase=0))
    c.box("Pinch" + tag, (0.25 * k, 0.18 * k, 0.5 * k), (cx, -0.05, -0.85 - 0.55 * k), R1)
for i, (x, z) in enumerate(((-0.85, -0.1), (0.85, -0.1), (-0.85, 0.3), (0.85, 0.3), (-0.8, 0.6), (0.8, 0.6))):
    name = "Leg%d" % (i + 1)
    s = 1 if x > 0 else -1
    c.bone(name, (x, -0.3, z), anim="rot", axis="X", amp=22, speed=2, phase=0 if i % 2 == 0 else math.pi)
    c.box(name, (0.22, 0.3, 0.22), (x * 1.12, -0.4, z), R2)
    c.box(name, (0.17, 0.35, 0.17), (x * 1.22, -0.62, z), R1, rot=(0, 0, s * 12))

# King Puff: a crowned pufferfish with two rings of glowing-tipped spikes and a royal cape
c = creature("PufferMini", "King Puff", "enemy")
c.bone("Puff", (0, 0, 0), anim="rot", axis="Y", amp=10, speed=1)
c.box("Puff", (1.8, 1.7, 1.8), (0, 0.2, 0), PF)
c.box("Puff", (1.5, 0.5, 1.5), (0, -0.55, 0), PF2)
for (s, y, z) in ((-1, 0.4, 0.3), (1, 0.2, 0.4), (-1, 0.0, -0.3), (1, 0.5, -0.2)):
    c.box("Puff", (0.06, 0.3, 0.3), (s * 0.92, y, z), (230, 160, 40))      # spots on the sides
angry_eye(c, "Puff", -0.42, 0.45, -0.94, s=0.4)
angry_eye(c, "Puff", 0.42, 0.45, -0.94, s=0.4)
c.box("Puff", (0.5, 0.18, 0.1), (0, 0.0, -0.93), (255, 120, 120))       # pouty lips
ring_spikes(c, "Puff", 8, 0.9, 0.75, 0.45, (200, 140, 40), tip=(255, 150, 60), skip_front=True, offset=0.5)
ring_spikes(c, "Puff", 8, 0.9, -0.15, 0.45, (200, 140, 40), tip=(255, 150, 60))
c.box("Puff", (1.0, 0.3, 1.0), (0, 1.2, 0), GOLD, mat="m")               # crown
for (x, z) in ((-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)):
    c.box("Puff", (0.18, 0.35, 0.18), (x, 1.5, z), GOLD, mat="m")
c.box("Puff", (0.18, 0.18, 0.06), (0, 1.2, -0.52), (255, 60, 80), mat="n")
for s in (-1, 1):
    c.box("Puff", (0.14, 0.14, 0.06), (s * 0.3, 1.2, -0.52), (90, 200, 255), mat="n")
c.bone("Cape", (0, 0.9, 0.92), parent="Puff", anim="rot", axis="X", amp=8, speed=1,
       swim=dict(anim="rot", axis="X", amp=18, speed=3, phase=0))
c.box("Cape", (1.4, 1.3, 0.1), (0, 0.25, 0.98), (200, 30, 60))
c.box("Cape", (1.44, 0.14, 0.12), (0, 0.9, 0.98), GOLD)
fin_pair(c, (0.35, 0.12, 0.35), 0.9, 0.0, 0.0, (255, 160, 40), amp=30, speed=4, parent="Puff")

# Urchin Overlord: a spinning urchin with long spikes and a glowing ring of spikes around it,
# one big glaring cyclops eye and a jagged grin
c = creature("UrchinMini", "Urchin Overlord", "enemy")
UG = (220, 120, 255)
# the body only rocks (a spinning cube would sweep its corners through the face); the glowing
# spike ring below the eye is what spins
c.bone("Core", (0, 0, 0), anim="rot", axis="Y", amp=8, speed=1,
       swim=dict(anim="rot", axis="Y", amp=14, speed=2, phase=0))
c.bone("Ring", (0, 0, 0), anim="spin", axis="Y", amp=0, speed=1)
c.box("Core", (1.5, 1.5, 1.5), (0, 0.3, 0), U1)
c.box("Core", (1.56, 0.3, 1.56), (0, 0.3, 0), (50, 28, 80))               # armoured belt
for (x, y, z, rx, rz) in ((0, 1.35, 0, 0, 0), (0.65, 1.0, 0.65, 35, -35), (-0.65, 1.0, -0.65, -35, 35),
                          (0.65, 1.0, -0.65, -35, -35), (-0.65, 1.0, 0.65, 35, 35),
                          (0.65, -0.4, 0.65, -35, 35), (-0.65, -0.4, -0.65, 35, -35)):
    c.box("Core", (0.2, 0.9, 0.2), (x, y, z), (140, 90, 200), rot=(rx, 0, rz))
ring_spikes(c, "Ring", 8, 0.8, -0.25, 0.75, (140, 90, 200), tip=UG)     # below the eye, so it never crosses it
c.box("Body", (0.7, 0.7, 0.08), (0, 0.45, -0.9), WHITE)                 # the cyclops eye
c.box("Body", (0.4, 0.4, 0.06), (0, 0.42, -0.95), (255, 60, 200), mat="n")
c.box("Body", (0.18, 0.18, 0.05), (0, 0.42, -0.98), INK)
for s in (-1, 1):
    c.box("Body", (0.5, 0.12, 0.1), (s * 0.22, 0.88, -0.94), INK, rot=(0, 0, s * 18))
c.box("Body", (0.6, 0.12, 0.06), (0, -0.05, -0.82), INK)
for x in (-0.18, 0, 0.18):
    c.box("Body", (0.1, 0.12, 0.05), (x, 0.03, -0.85), WHITE)

# Ink Baron: a squid gentleman in a top hat, a gold monocle and a curled moustache, glowing
# ink sacs, and eight long tentacles
c = creature("SquidMini", "Ink Baron", "enemy")
Q2 = (220, 80, 150)
c.bones[0]["amp"] = 0.2
c.box("Body", (1.3, 1.8, 1.3), (0, 1.0, 0), Q1)
c.box("Body", (1.5, 0.5, 0.2), (0, 1.9, 0), Q1)
for (x, y) in ((-0.66, 1.3), (0.66, 0.9), (-0.66, 0.7), (0.66, 1.5)):
    c.box("Body", (0.06, 0.25, 0.25), (x, y, 0.1), Q2)                    # spots
angry_eye(c, "Body", -0.3, 0.65, -0.69, s=0.32)
angry_eye(c, "Body", 0.3, 0.65, -0.69, s=0.32)
c.box("Body", (0.44, 0.46, 0.06), (0.3, 0.65, -0.67), GOLD, mat="m")       # monocle rim
c.box("Body", (0.05, 0.5, 0.05), (0.48, 0.3, -0.68), GOLD)                # monocle chain
for s in (-1, 1):
    c.box("Body", (0.4, 0.1, 0.08), (s * 0.2, 0.3, -0.69), INK, rot=(0, 0, s * 15))
    c.box("Body", (0.1, 0.14, 0.08), (s * 0.42, 0.37, -0.69), INK)
    c.ball("Body", 0.3, (s * 0.35, 1.2, 0.66), (140, 70, 220), mat="n")   # ink sacs
c.box("Body", (1.2, 0.12, 1.0), (0.05, 2.22, 0), INK, rot=(0, 0, 8))      # top hat
c.box("Body", (0.8, 0.7, 0.7), (0.1, 2.62, 0), INK, rot=(0, 0, 8))
c.box("Body", (0.82, 0.14, 0.72), (0.07, 2.36, 0), (200, 40, 80), rot=(0, 0, 8))
tentacles(c, 8, 0.45, 0.1, Q2, length=4, seg=(0.2, 0.38, 0.2), amp=22, tip=(255, 160, 210))

# Storm Gull: a storm-grey gull with a spiky crest, a hooked beak, talons and wings streaked
# with glowing lightning
c = creature("GullMini", "Storm Gull", "enemy")
SG1, SG2, BOLT = (120, 128, 150), (70, 76, 98), (255, 230, 80)
c.bones[0].update(anim="move", amp=0.35, speed=1)
c.box("Body", (1.0, 0.9, 1.6), (0, 0.4, 0.1), SG1)
c.box("Body", (0.8, 0.4, 1.3), (0, 0.05, 0.1), (200, 205, 215))          # pale belly
c.box("Body", (0.9, 0.8, 0.8), (0, 0.85, -0.7), SG1)
c.box("Body", (0.35, 0.25, 0.55), (0, 0.75, -1.33), (255, 190, 40))       # beak
c.box("Body", (0.3, 0.2, 0.15), (0, 0.6, -1.55), (220, 150, 30), rot=(30, 0, 0))   # hooked tip
angry_eye(c, "Body", -0.25, 1.0, -1.12, s=0.22)
angry_eye(c, "Body", 0.25, 1.0, -1.12, s=0.22)
for k in range(3):
    c.box("Body", (0.12, 0.45 - k * 0.08, 0.15), (0, 1.35 - k * 0.05, -0.85 + k * 0.25), SG2, rot=(30, 0, 0))   # crest
for z in (0.25, 0.65):
    c.box("Body", (0.2, 0.1, 0.55), (0, 0.5, z + 0.55), SG2, rot=(-10, 0, 0))   # tail feathers
for s in (-1, 1):
    for k in range(3):
        c.box("Body", (0.06, 0.25, 0.06), (s * 0.25 + (k - 1) * 0.08, -0.32, -0.1), (255, 190, 40))   # talons
for s, tag in ((-1, "L"), (1, "R")):
    c.bone("Wing" + tag, (s * 0.5, 0.6, 0.1), anim="rot", axis="Z", amp=35 * s, speed=3)
    c.box("Wing" + tag, (1.5, 0.15, 0.85), (s * 1.25, 0.6, 0.1), SG1)
    c.box("Wing" + tag, (1.2, 0.17, 0.25), (s * 1.4, 0.6, 0.45), SG2)       # dark flight feathers
    c.box("Wing" + tag, (0.8, 0.18, 0.08), (s * 1.2, 0.6, -0.05), BOLT, rot=(0, s * 25, 0), mat="n")
    c.box("Wing" + tag, (0.5, 0.18, 0.08), (s * 1.6, 0.6, 0.12), BOLT, rot=(0, s * -25, 0), mat="n")

# Bone Reaper: a skeleton fish with a big cracked skull and snapping jaw, glowing eyes in deep
# sockets, a ribcage around a glowing soul, spine spikes and a bony tail
c = creature("SkelefishMini", "Bone Reaper", "enemy")
SOUL, CRACK = (120, 255, 160), (150, 140, 120)
c.box("Body", (1.2, 1.0, 1.1), (0, 0.45, -0.75), BONE)
for s in (-1, 1):
    c.box("Body", (0.36, 0.36, 0.06), (s * 0.27, 0.55, -1.31), INK)
    c.box("Body", (0.2, 0.2, 0.06), (s * 0.27, 0.55, -1.34), SOUL, mat="n")
c.box("Body", (0.14, 0.12, 0.05), (0, 0.3, -1.32), INK)
c.box("Body", (0.05, 0.35, 0.05), (0.32, 0.82, -1.31), CRACK, rot=(0, 0, 20))
c.box("Body", (0.05, 0.25, 0.05), (-0.4, 0.2, -1.31), CRACK, rot=(0, 0, -15))
for k in range(5):
    c.box("Body", (0.1, 0.16, 0.1), (-0.4 + k * 0.2, -0.0, -1.25), WHITE)
c.bone("Jaw", (0, 0.0, -0.4), anim="rot", axis="X", amp=10, speed=1,
       swim=dict(anim="rot", axis="X", amp=26, speed=3, phase=0))
c.box("Jaw", (1.0, 0.25, 0.9), (0, -0.2, -0.8), BONE)
for k in range(4):
    c.box("Jaw", (0.1, 0.16, 0.1), (-0.3 + k * 0.2, -0.02, -1.18), WHITE)
c.box("Body", (0.2, 0.2, 2.0), (0, 0.4, 0.5), BONE)                      # spine
for k in range(5):
    z = -0.05 + k * 0.25
    c.box("Body", (1.0 - k * 0.1, 0.12, 0.1), (0, 0.4 - (0.45 - k * 0.04), z), BONE)   # rib bottoms
    for s in (-1, 1):
        c.box("Body", (0.1, 0.95 - k * 0.08, 0.1), (s * (0.5 - k * 0.05), 0.4 - 0.05, z), BONE, rot=(0, 0, s * 8))
    c.box("Body", (0.1, 0.35, 0.1), (0, 0.65, z), BONE, rot=(30, 0, 0))   # spine spikes
c.ball("Body", 0.5, (0, 0.3, 0.4), SOUL, mat="n")                         # the glowing soul
fin_pair(c, (0.5, 0.08, 0.3), 0.55, 0.0, -0.4, BONE, amp=20, speed=2)
tail_chain(c, (0, 0.4, 1.5), [((0.2, 0.8, 0.5), BONE, "p"), ((0.15, 1.2, 0.5), BONE, "p")], amp=24)


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
