# CASE STUDIES (not part of the workflow). Step 3: a draft deck (3 slides per case) from the figures and numbers of make_case_study_figures.R.
#   python case_studies/make_case_study_slides.py [--figs <folder>] [--out <pptx>]
# Every number on a slide is read from the csv files that the figure script wrote, so deck and figures cannot disagree. Needs python-pptx.
import csv, os, sys
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

args = sys.argv[1:]
def arg(flag, default):
    return args[args.index(flag) + 1] if flag in args else default
FIGS = arg("--figs", "outputs_downloaded/v3_2026-11-14/case_study_figures")
OUT = arg("--out", os.path.join(FIGS, "case_studies_draft_slides.pptx"))

def rows(name):
    with open(os.path.join(FIGS, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))
def slope10(xs, ys):
    n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
    return 10 * sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
def fmt(v, d=1):
    return ("%+." + str(d) + "f") % v

HOPE, WORK = RGBColor(0x1B, 0x78, 0x37), RGBColor(0xB2, 0x18, 0x2B)
INK, GREY, SOFT = RGBColor(0x22, 0x31, 0x3F), RGBColor(0x5F, 0x6B, 0x76), RGBColor(0xF2, 0xF4, 0xF3)
prs = Presentation(); prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
blank = prs.slide_layouts[6]

def text(slide, x, y, w, h, paras, size=14, color=INK, bold=False, font="Calibri", anchor=MSO_ANCHOR.TOP, name=None):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h)); tf = tb.text_frame; tf.word_wrap = True; tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = Inches(0.05); tf.margin_top = tf.margin_bottom = Inches(0.03)
    if name: tb.name = name
    first = True
    for p in (paras if isinstance(paras, list) else [paras]):
        if isinstance(p, str): p = {"t": p}
        par = tf.paragraphs[0] if first else tf.add_paragraph(); first = False
        par.space_after = Pt(p.get("after", 6)); par.alignment = PP_ALIGN.LEFT
        runs = p["t"] if isinstance(p["t"], list) else [(p["t"], {})]
        for t, o in runs:
            r = par.add_run(); r.text = t; f = r.font; f.name = o.get("font", p.get("font", font)); f.size = Pt(o.get("size", p.get("size", size)))
            f.bold = o.get("bold", p.get("bold", bold)); f.color.rgb = o.get("color", p.get("color", color))
    return tb

def title(slide, t, color, kicker):
    text(slide, 0.5, 0.28, 12.3, 0.32, kicker, size=14, color=color, bold=True, name="Kicker")
    text(slide, 0.5, 0.58, 12.3, 0.95, t, size=30, color=INK, bold=True, font="Cambria", anchor=MSO_ANCHOR.TOP, name="Title")

def picture(slide, key, x, y, w):
    p = os.path.join(FIGS, key); slide.shapes.add_picture(p, Inches(x), Inches(y), width=Inches(w)).name = key[:-4]

def stat(slide, x, y, w, big, label, color):
    box = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(1.5)); box.adjustments[0] = 0.08
    box.fill.solid(); box.fill.fore_color.rgb = SOFT; box.line.fill.background(); box.shadow.inherit = False; box.name = "StatCard"
    text(slide, x + 0.1, y + 0.1, w - 0.2, 0.6, big, size=28, color=color, bold=True, font="Cambria", name="StatNumber")
    text(slide, x + 0.1, y + 0.78, w - 0.2, 0.7, label, size=14, color=INK, name="StatLabel")

def foot(slide, s):
    text(slide, 0.5, 6.98, 12.3, 0.4, s, size=10, color=GREY, name="Footer")

def notes(slide, s):
    slide.notes_slide.notes_text_frame.text = s

def case(key, label, kicker, color, ctl, ctlShort, stories):
    cells = {r["group"]: r for r in rows(f"{key}_numbers_cells.csv")}; ts = {}
    for r in rows(f"{key}_numbers_index_series.csv"): ts.setdefault(r["group"], []).append(r)
    def sl(g, col):
        d = [r for r in ts[g] if int(r["year"]) <= 2023]; return slope10([int(r["year"]) for r in d], [float(r[col]) for r in d])
    spp = rows(f"{key}_numbers_species_slopes.csv"); n = len(spp); betterC = sum(r["betterControl"] == "TRUE" for r in spp); betterG = sum(r["betterGermany"] == "TRUE" for r in spp)
    lu = {r["class"]: r for r in rows(f"{key}_numbers_landuse.csv")}
    a = cells["all"]; up, down, nc, nb = int(a["clearUp"]), int(a["clearDown"]), int(a["notClear"]), int(a["cellsInArea"])
    return dict(cells=cells, sl=sl, n=n, betterC=betterC, betterG=betterG, lu=lu, up=up, down=down, nc=nc, nb=nb, spp=spp, ts=ts)

H = case("Schorfheide", "Schorfheide-Chorin Biosphere Reserve", "HOPE", HOPE, "control_Schorfheide", "Brandenburg", None)
M = case("Muensterland", "Muensterland", "WORK TO DO", WORK, "control_Muensterland", "North Rhine-Westphalia", None)
def lu(c, cl, k): return float(c["lu"][cl][k])

# ============================== HOPE ======================================================================================================================================
s = prs.slides.add_slide(blank); title(s, "The Schorfheide-Chorin Biosphere Reserve stands out on the national map", HOPE, "HOPE")
picture(s, "Schorfheide_1_location_trend.png", 0.4, 1.6, 9.5)
stat(s, 10.15, 1.7, 2.7, f"{H['up']} of {H['nb']}", f"cells inside the reserve show a clear increase; {H['down']} a clear decline", HOPE)
stat(s, 10.15, 3.4, 2.7, f"{fmt(H['sl']('all', 'area'))} vs {fmt(H['sl']('all', 'control'))}", "points per decade: reserve vs rest of Brandenburg (2005-2023)", HOPE)
stat(s, 10.15, 5.1, 2.7, f"{H['betterC']} of {H['n']}", "species do better in the reserve than in the rest of Brandenburg", HOPE)
foot(s, "Trend of the regional bird index (all 14 species), 2005-2025; coloured = clear trend (90% interval of 25 replicate slopes excludes zero). Base map and reserve outline: (c) OpenStreetMap contributors (ODbL).")
notes(s, "Figure: Schorfheide_1_location_trend.png. Left: all of Germany, only cells where the trend is clear; black outline = the reserve. Right: zoom on the reserve; numbers = slope of the 10 km cells whose centre lies inside the official outline (OpenStreetMap relation 215277, 1,291.8 km2 = published 1,292 km2); brackets/grey = not clear.\n"
      f"Cells inside: {H['nb']} ({H['up']} clear increase, {H['down']} clear decline, {H['nc']} not clear). Farmland set: {H['cells']['farmland']['clearUp']} of {H['cells']['farmland']['cellsInArea']} clearly increasing.\n"
      f"Comparison: rest of Brandenburg {fmt(H['sl']('all', 'control'))} and Germany {fmt(H['sl']('all', 'germany'))} points per decade, 2005-2023 (index 2005 = 100). Slopes of the map are 2005-2025 (pipeline product); the series and species slopes leave out 2024-2025 (new crop map).\n"
      "The model shows direction and relative contrast, not the size of real population change.")

s = prs.slides.add_slide(blank); title(s, "While Brandenburg and Germany decline, the reserve holds up", HOPE, "HOPE")
picture(s, "Schorfheide_2_index_vs_control.png", 0.4, 1.55, 6.15); picture(s, "Schorfheide_3_species_vs_control.png", 6.8, 1.55, 6.15)
text(s, 0.5, 5.15, 12.3, 1.75, [
    {"t": [(f"{fmt(H['sl']('all', 'area'))} points per decade ", {"bold": True, "color": HOPE}), (f"in the reserve, against {fmt(H['sl']('all', 'control'))} in the rest of Brandenburg and {fmt(H['sl']('all', 'germany'))} in Germany (2005-2023, all 14 species).", {})]},
    {"t": [(f"{H['betterC']} of {H['n']} species ", {"bold": True, "color": HOPE}), ("do better in the reserve than in the rest of the state, among them typical farmland birds: Whinchat, Corn Bunting, Red-backed Shrike, Meadow Pipit, Skylark.", {})]},
    {"t": "The comparison is with the state, not with Germany: declines are stronger in the west than in the east, so a national comparison would flatter any eastern area.", "color": GREY, "size": 14}], size=16, name="Takeaways")
foot(s, "Regional index = mean over 10 km cells, relative to each cell's own 2005 level. 2024-2025 (orange) use a different crop map and are left out of the slopes. The state is not matched for soil or climate.")
notes(s, "Figures: Schorfheide_2_index_vs_control.png and Schorfheide_3_species_vs_control.png.\n"
      f"Index slopes 2005-2023, all species: area {fmt(H['sl']('all','area'))}, rest of Brandenburg {fmt(H['sl']('all','control'))}, Germany {fmt(H['sl']('all','germany'))}. Farmland set: {fmt(H['sl']('farmland','area'))}, {fmt(H['sl']('farmland','control'))}, {fmt(H['sl']('farmland','germany'))}.\n"
      f"Species: {H['betterC']} of {H['n']} better than the rest of Brandenburg, {H['betterG']} of {H['n']} better than Germany (Northern Lapwing is the exception).\n"
      "The reserve series is noisy from year to year (peak 2017, dips 2018 and 2020), so the slope, not single years, is the message.\n"
      "Not matched for soil or climate; a matched control (similar land-use mix in 2005 within eastern Germany) would be a next step.")

s = prs.slides.add_slide(blank); title(s, "What we see in the data, and what we can and cannot say", HOPE, "HOPE")
picture(s, "Schorfheide_4a_crops_over_time.png", 0.4, 1.6, 7.4)
gr = lu(H, "grassland", "areaSlope10_0523"); grC = lu(H, "grassland", "controlSlope10_0523"); grG = lu(H, "grassland", "germanySlope10_0523"); fa = lu(H, "fallow", "area2023")
mz = lu(H, "maize", "areaSlope10_0523"); mzC = lu(H, "maize", "controlSlope10_0523"); mzG = lu(H, "maize", "germanySlope10_0523")
text(s, 8.0, 1.55, 4.9, 5.3, [
    {"t": "In our data", "bold": True, "color": HOPE, "size": 16, "after": 3},
    {"t": f"Grassland holds steady ({gr:+.1f} points per decade) while it falls in the rest of Brandenburg ({grC:+.1f}) and in Germany ({grG:+.1f}). Maize does not expand ({mz:+.1f}; Brandenburg {mzC:+.1f}, Germany {mzG:+.1f}). Fallow rises. The models respond positively to grassland and fallow.", "after": 10},
    {"t": "Independent evidence", "bold": True, "color": HOPE, "size": 16, "after": 3},
    {"t": "DDA monitoring in the reserve: organic farms had higher densities of Skylark, Red-backed Shrike, Corn Bunting and Yellowhammer than conventional farms in the same reserve. Organic farmland grew from about 14,000 ha to about 25,000 ha (62%, 2021).", "after": 10},
    {"t": "What we cannot show", "bold": True, "color": HOPE, "size": 16, "after": 3},
    {"t": "Our model has no layer for organic farming. It shows where birds do better, not why.", "after": 4}], size=14, name="ThreeParts")
foot(s, "Sources: Flade & Schwarz (DDA), talk 'Haben unsere Feldvoegel noch eine Chance?' (hs-nb.de, 2012); Werner, Nordkurier, 17.03.2021 (62% organic, about 25,000 ha); reserve established 1990, 1,292 km2. Details in the notes.")
notes(s, "Figure: Schorfheide_4a_crops_over_time.png (green = reserve, dashed black = rest of Brandenburg, grey = Germany; orange = 2024-2025, new crop map).\n"
      "Independent evidence (DDA talk by Martin Flade and Johannes Schwarz, slides 54-68): reserve established 1990, 1,292 km2; reference area Choriner Endmoraene / Brodowin 13,000 ha with more than 95% organic farming in the open land; densities of Skylark, Red-backed Shrike, Corn Bunting and Yellowhammer on arable land are clearly higher on the organic farm (Brodowin, 1997-2004) than on conventional farms in the same reserve (Gross Ziethen, 1999-2006); of the farmland species of the Brodowin area compared with East Germany, 8 were more favourable, 6 similar, 3 less favourable (2 of them declining). "
      "CAUTION: this is a conference talk, not a peer-reviewed paper; the densities are read off its charts and are not reproduced on the slide. Take numbers from the primary source (Flade et al. 2003, 2006, Schorfheide-Chorin research project; not opened by us) before quoting.\n"
      "Organic share: talk (about 2012) 33% organic farming = 14,000 ha; Nordkurier 17.03.2021 (Sigrid Werner): 62% of the farmland, about 25,000 ha. A figure of 70% appears only in the preamble of a parliamentary question (Bundestag Drucksache 21/7892), citing a press article; the federal government gave no view. Not used.\n"
      "Why this is not proof: the reserve is also on particular soils and in the east; organic farming is not in our layers; the control (rest of Brandenburg) is not matched. An effect already underway before 2005 would show as a modest trend, so a modest increase can mean continued benefit.\n"
      "URLs: https://www.hs-nb.de/storages/hs-neubrandenburg/studiengaenge-fachbereiche/SG_NLP/Naturschutztage_Vortraege/2012/FladeSchwarz_Neubrandenburg_Agrarvoegel.pdf ; https://www.nordkurier.de/regional/uckermark/prufer-nehmen-biospharenreservat-unter-die-lupe-1157940 ; OpenStreetMap relation 215277.")

# ============================== WORK TO DO ================================================================================================================================
s = prs.slides.add_slide(blank); title(s, "In the Münsterland the decline is clear in every cell", WORK, "WORK TO DO")
picture(s, "Muensterland_1_location_trend.png", 0.4, 1.6, 9.5)
stat(s, 10.15, 1.7, 2.7, f"{M['down']} of {M['nb']}", "cells in the area show a clear decline", WORK)
stat(s, 10.15, 3.4, 2.7, f"{fmt(M['sl']('all', 'area'))} vs {fmt(M['sl']('all', 'control'))}", "points per decade: area vs rest of North Rhine-Westphalia (2005-2023)", WORK)
stat(s, 10.15, 5.1, 2.7, f"{M['n'] - M['betterC']} of {M['n']}", "species do worse in the area than in the rest of the state", WORK)
foot(s, "Trend of the regional bird index (all 14 species), 2005-2025; analysed area = 3 x 3 cells of the 10 km grid (900 km2, aligned with the cells). Base map: (c) OpenStreetMap contributors.")
notes(s, "Figure: Muensterland_1_location_trend.png. The area is a block of 3 x 3 cells of the 10 km regional grid around 7.70 E, 52.05 N (Muensterland has no official outline); numbers = slope of each cell.\n"
      f"Cells: {M['nb']} ({M['down']} clear decline, {M['up']} clear increase, {M['nc']} not clear). Share of NRW cells (outside the block) with a lower slope than the block mean: all species {float(M['cells']['all']['shareControlCellsWorseThanAreaMean'])*100:.0f}%.\n"
      f"Index slope 2005-2023: area {fmt(M['sl']('all','area'))}, NRW without the area {fmt(M['sl']('all','control'))}, Germany {fmt(M['sl']('all','germany'))}. Map slopes are 2005-2025 (pipeline product).")

s = prs.slides.add_slide(blank); title(s, "Declining faster than North Rhine-Westphalia and Germany", WORK, "WORK TO DO")
picture(s, "Muensterland_2_index_vs_control.png", 0.4, 1.55, 6.15); picture(s, "Muensterland_3_species_vs_control.png", 6.8, 1.55, 6.15)
sp = {r["english"]: r for r in M["spp"]}
text(s, 0.5, 5.15, 12.3, 1.75, [
    {"t": [(f"{fmt(M['sl']('all', 'area'))} points per decade ", {"bold": True, "color": WORK}), (f"in the area, against {fmt(M['sl']('all', 'control'))} in the rest of North Rhine-Westphalia and {fmt(M['sl']('all', 'germany'))} in Germany (2005-2023, all 14 species).", {})]},
    {"t": [(f"Northern Lapwing {fmt(float(sp['Northern Lapwing']['area']))} ", {"bold": True, "color": WORK}), (f"points per decade against {fmt(float(sp['Northern Lapwing']['control']))} in the rest of the state. Whinchat falls steeply everywhere ({fmt(float(sp['Whinchat']['area']))} against {fmt(float(sp['Whinchat']['control']))}). In all, {M['n'] - M['betterC']} of {M['n']} species do worse than in the rest of the state.", {})]},
    {"t": "Index shown to 2023; 2024-2025 (orange) are marked because the crop map changes in 2024.", "color": GREY, "size": 14}], size=16, name="Takeaways")
foot(s, "Regional index = mean over 10 km cells, relative to each cell's own 2005 level. Species trend = probability of occurrence in the area, 2005-2023, index points per decade. The model shows direction and relative contrast, not the size of real population change.")
notes(s, "Figures: Muensterland_2_index_vs_control.png and Muensterland_3_species_vs_control.png.\n"
      f"Species better than the rest of NRW: {M['betterC']} of {M['n']}; better than Germany: {M['betterG']} of {M['n']}.\n"
      "Lapwing and Whinchat are robust to the time window; Corn Bunting and Red-backed Shrike are not (their values change a lot when 2024-2025 are included), so do not headline those two.\n"
      "The model understates declines: the literature reports Kiebitz pairs in Muenster down about 60% in 2003-2014 (NRW press release), the model's index changes far less. Nationally the model's slope has the same sign as the observed one for 11 of 14 species and captures about 13% of its size (not an independent test).")

s = prs.slides.add_slide(blank); title(s, "What the data show: grassland is lost, and 2024 needs care", WORK, "WORK TO DO")
picture(s, "Muensterland_4a_crops_over_time.png", 0.4, 1.6, 7.4)
g05, g23 = lu(M, "grassland", "area2005") * 100, lu(M, "grassland", "area2023") * 100; gs, gc = lu(M, "grassland", "areaSlope10_0523"), lu(M, "grassland", "controlSlope10_0523")
w05, w23 = lu(M, "winter_cereals", "area2005") * 100, lu(M, "winter_cereals", "area2023") * 100; s05, s23 = lu(M, "summer_cereals", "area2005") * 100, lu(M, "summer_cereals", "area2023") * 100
wc = float(M["lu"]["winter_cereals"]["change2023to24Area"])
text(s, 8.0, 1.55, 4.9, 5.3, [
    {"t": "In our data", "bold": True, "color": WORK, "size": 16, "after": 3},
    {"t": f"Grassland falls from {g05:.1f}% to {g23:.1f}% of the land ({gs:+.1f} points per decade; rest of the state {gc:+.1f}). Winter cereals stay near {w05:.0f}-{w23:.0f}%. The models respond positively to grassland (Lapwing, Whinchat).", "after": 10},
    {"t": "In the literature", "bold": True, "color": WORK, "size": 16, "after": 3},
    {"t": "Loss of wet grassland is named as the first cause of the Lapwing decline (Thünen); in Münster the species fell by about 60% in 2003-2014.", "after": 10},
    {"t": "Take care with 2024-25", "bold": True, "color": WORK, "size": 16, "after": 3},
    {"t": f"The new crop map changes winter cereals by {wc:+.0f}% in one year. The index jumps in the same year, so we show it only to 2023.", "after": 4}], size=14, name="ThreeParts")
foot(s, "Sources: Thünen-Institut, Project brief 2023/35 (thuenen.de); press release of the State of NRW on the NABU station Münsterland (land.nrw; Münster figure to be re-checked). Details in the notes.")
notes(s, "Figure: Muensterland_4a_crops_over_time.png (red = area, dashed black = rest of NRW, grey = Germany; orange = 2024-2025).\n"
      f"Land-use layers (1 km, what the landscape models are given): grassland {g05:.1f}% (2005) -> {g23:.1f}% (2023); winter cereals {w05:.1f}% -> {w23:.1f}%; summer cereals {s05:.2f}% -> {s23:.2f}%. A cereal switch from summer to winter crops is NOT visible as an increase of winter cereals since 2005; the reported shift may predate 2005.\n"
      "Model response (Muensterland_4b_model_response_to_crops.png): the Lapwing model responds positively to maize, summer cereals and grassland and only weakly (hump-shaped) to winter cereals; so the area's modelled decline follows its grassland loss, not a cereal switch.\n"
      "2024-2025: CTM v302 (2024, and a preliminary August 2025 version) recoded to HCTM classes with a matrix fitted on CTM v202 vs HCTM in 2017-2021; there is no year where v302 and HCTM overlap. In this area winter cereals change by " + f"{wc:+.0f}% from 2023 to 2024, grassland by {float(M['lu']['grassland']['change2023to24Area']):+.0f}%, while the area index rises in the same year. Probably an artefact; not yet tested (DECISIONS.md, improvements.md item 28e).\n"
      "Not in the model: nest losses from tillage, predation, insect decline.\n"
      "URLs: https://www.thuenen.de/media/publikationen/project_brief/Project_brief_2023_35.pdf ; https://www.land.nrw/pressemitteilung/ministerin-christina-schulze-foecking-besucht-die-nabu-naturschutzstation")
prs.save(OUT); print("saved", OUT)
