# Read-only: end states, requested memory, peak memory and wait times of the jobs of a user, from the Slurm accounting (sacct).
#   python3 cluster/mem_history.py [since-date, default 2026-10-29] [user, default: you]      (on an EVE login node)
# Used for cluster/MEMORY_LEDGER.md: read it BEFORE changing a --mem-per-cpu and update the ledger after every OUT_OF_MEMORY.
import sys, getpass
SINCE = sys.argv[1] if len(sys.argv) > 1 else "2026-10-29"; USER = sys.argv[2] if len(sys.argv) > 2 else getpass.getuser()
import subprocess, collections, re, datetime, statistics
out = subprocess.run(["sacct", "-u", USER, "-S", SINCE, "-n", "-P", "-o", "JobID,JobName,State,Elapsed,ReqMem,MaxRSS,NCPUS,Eligible,Start"], capture_output=True, text=True).stdout
def gb(s):
    if not s: return None
    m = re.match(r"([\d.]+)([KMGT]?)", s)
    if not m: return None
    v = float(m.group(1)); u = m.group(2)
    return v / (1024 ** 2) if u == "K" else v / 1024 if u == "M" else v if u == "G" else v * 1024 if u == "T" else v / (1024 ** 3)
def reqgb(s, ncpu):
    m = re.match(r"([\d.]+)([MG])([nc]?)", s or "")
    if not m: return None
    v = float(m.group(1)) * (1 if m.group(2) == "G" else 1 / 1024)
    return v * (int(ncpu) if m.group(3) == "c" else 1)
def ts(s):
    try: return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")
    except Exception: return None
alloc = {}; steps = collections.defaultdict(float)
for ln in out.strip().splitlines():
    f = ln.split("|")
    if len(f) < 9: continue
    jid, name, state, el, req, rss, nc, elig, start = f[:9]
    base = jid.split(".")[0]
    if "." not in jid: alloc[base] = (name, state.split()[0], reqgb(req, nc), nc, ts(elig), ts(start))
    else:
        v = gb(rss)
        if v: steps[base] = max(steps[base], v)
fam = collections.defaultdict(lambda: {"n": 0, "st": collections.Counter(), "req": collections.Counter(), "ok": 0.0, "any": 0.0, "wait": []})
keep = re.compile(r"(birdmon-(habitat|europe|landscape|covcache)|ens-|unc-)")
for b, (name, state, req, nc, el, st) in alloc.items():
    if not keep.match(name): continue
    r = fam[name]; r["n"] += 1; r["st"][state] += 1; r["req"][(round(req or 0), nc)] += 1; v = steps.get(b, 0.0); r["any"] = max(r["any"], v)
    if state == "COMPLETED": r["ok"] = max(r["ok"], v)
    if el and st and state == "COMPLETED": r["wait"].append((st - el).total_seconds() / 60)
print("%-30s %5s %-28s %-18s %9s %9s | wait after becoming eligible (min): median / 90th pct / max" % ("job name", "tasks", "end states", "requested GB (cpus)", "peak ok", "peak any"))
for k, r in sorted(fam.items()):
    w = sorted(r["wait"]); med = statistics.median(w) if w else float("nan"); p90 = w[int(0.9 * (len(w) - 1))] if w else float("nan")
    req = ",".join("%d(%s)" % (a, b) for (a, b) in sorted(r["req"]))
    print("%-30s %5d %-28s %-18s %9.1f %9.1f | %6.0f / %6.0f / %6.0f" % (k[:30], r["n"], str(dict(r["st"]))[:28], req[:18], r["ok"], r["any"], med, p90, (w[-1] if w else float("nan"))))
