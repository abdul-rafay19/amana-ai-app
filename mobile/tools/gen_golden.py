"""Writes test/golden.json from the TESTED Python code. The Dart engine must reproduce these answers.
Run from the repo root:  python mobile/tools/gen_golden.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("AMANA_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, ROOT)
os.environ["AMANA_SKIP_DOTENV"] = "1"
import calc, offline

deal = [(30, 250, None, None), (30, 250, 1200, 20), (100, 80, 1500, 90), (12, 333.5, 0, 7), (7, 45.25, 100.5, 3.5), (500, 12, 4000, 120)]
req = [(30, 1200, 20, 150, 250), (100, 1500, 90, 300, 80), (10, 0, 5, 100, 500), (7, 100, 3.5, 250, 45.25)]
cmp_ = [(7500, 6500, 0, 0, False), (7500, 7500, 0, 0, False), (7500, 6500, 500, 500, False), (7500, 6500, 0, 0, True),
        (7500, 8000, 0, 0, False), (8000, 6500, 0, 0, False), (1234.5, 1000, 100, 50.25, False)]
orders = [
    ({"quantity": 30, "rate_per_piece": 250}, 'deal(30,250)', None),
    ({"quantity": 100, "rate_per_piece": 80, "material_expenses": 4500, "estimated_hours": 90, "deadline_days": 5,
      "payment_terms": "after delivery cutting"}, None, None),
    ({"quantity": 100, "rate_per_piece": 80, "material_expenses": 1500, "estimated_hours": 90, "deadline_days": 10,
      "payment_terms": "on delivery"}, None, 100),
]
phrases = [
    ("Mujhe 30 frock ka order mila hai, 250 rupay per piece, 5 din mein dena hai.", None),
    ("I got an order for 30 dresses, Rs 250 each, deadline 5 days", None),
    ("100 suits 80 rupees per piece, material 1500, 90 hours, 10 days, payment on delivery", None),
    ("1200 ka material lagega", "material_expenses"),
    ("20 hours lagenge", "estimated_hours"),
    ("۳۰ فراک کا آرڈر ہے، ہر پیس ۲۵۰ روپے، ۵ دن میں دینا ہے", None),
    ("500", "quantity"),
    ("delivery par", "payment_terms"),
    ("kuch nahi", "material_expenses"),
    ("advance 2000 mila hai, 2 weeks mein dena hai", None),
    ("hello", None),
    ("teen suit, bees rupay har piece", None),
    ("order 1,200 pieces, rate 15 each", None),
]

g = {"deal": [], "req": [], "cmp": [], "risks": [], "extract": [], "lang": [], "normalize": []}
for a in deal:
    g["deal"].append({"in": list(a), "out": calc.calculate_deal(*a)})
for a in req:
    g["req"].append({"in": list(a), "out": calc.required_rate_for_target(*a)})
for a in cmp_:
    g["cmp"].append({"in": list(a), "out": calc.compare_payment(*a)})
for o, _, mh in orders:
    full = {k: o.get(k) for k in ("item", "quantity", "rate_per_piece", "deadline_days", "material_expenses",
                                  "estimated_hours", "payment_terms", "contractor_name", "other_terms", "advance_received")}
    c = calc.calculate_deal(full["quantity"], full["rate_per_piece"], full["material_expenses"], full["estimated_hours"])
    g["risks"].append({"order": full, "calc": c, "min_hourly": mh, "out": calc.analyze_risks(full, c, mh) if mh else calc.analyze_risks(full, c)})
for t, asked in phrases:
    g["extract"].append({"text": t, "asked": asked, "out": offline.extract_offline(t, asked)})
    g["lang"].append({"text": t, "out": offline.detect_lang(t)})
    g["normalize"].append({"text": t, "out": offline.normalize(t)})
out = os.path.join(HERE, "..", "test", "golden.json")
json.dump(g, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("wrote", os.path.abspath(out), {k: len(v) for k, v in g.items()})
