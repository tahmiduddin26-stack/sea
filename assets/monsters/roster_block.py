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
        c.box("Head", (0.5 * s, 0.12 * s, 0.14 * s), (ex, 1.5 * s, -1.92 * s), accent, rot=(0, 0, sx * -12))
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
            c.box(name, (1.4 * s, 0.14 * s, 0.22 * s), (sx * 1.45 * s, 0.85 * s, -0.05 * s), body, rot=(0, 0, sx * 18))
            c.box(name, (1.3 * s, 0.1 * s, 1.1 * s), (sx * 1.45 * s, 0.72 * s, 0.55 * s), mem,
                  mat="n" if wing == "glow" else "p", rot=(0, sx * 8, sx * 14))
            c.box(name, (0.7 * s, 0.1 * s, 0.7 * s), (sx * 2.1 * s, 0.95 * s, 0.35 * s), mem,
                  mat="n" if wing == "glow" else "p", rot=(0, sx * 25, sx * 22))
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

