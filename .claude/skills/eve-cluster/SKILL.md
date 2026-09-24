---
name: eve-cluster
description: Use whenever preparing, submitting, or troubleshooting a job on the UFZ EVE HPC cluster for birdMonitor (the SLURM arrays under modules/models_Monitor/cluster/*.sbatch, or anything else that runs on EVE). Encodes constraints from UFZ's own onboarding email so submissions are efficient and don't get stuck in queue or killed by node policy.
---

# EVE cluster: strategic job submission

EVE is a shared, resource-constrained HPC cluster. The constraints below come
directly from UFZ HPC support's onboarding email (2026-09) and change how a
job should be written, not just how it's submitted.

## Before anything else

1. **VPN required.** EVE is only reachable from UFZ's internal network. Connect
   VPN before any SSH/submission/file-transfer step. There is no way around
   this -- don't try to debug a "cluster unreachable" symptom before checking
   this first.
2. **Software: check the module system first.**
   - Most software should already be in the Lmod module system:
     `module avail`, `module spider <name>`, `module load <name>`.
   - If something's missing, it CAN be requested, but installation is **not
     immediate** -- don't plan a submission around a same-day install.
   - You can always install software into your own EVE directory and
     reference it directly from a job script, without waiting on a module
     request. Prefer this for anything one-off or birdMonitor-specific.
   - Wiki: https://wiki.ufz.de/eve/index.php/Lmod
     https://wiki.ufz.de/eve/index.php/Category:Software_Deployment
   - Every `*.sbatch` in `modules/models_Monitor/cluster/` currently has a
     `# module load R/<version>` line commented out as a TODO -- fill in the
     real module name from `module spider R` before first submission.

## The two constraints that actually change job design

3. **Compute nodes have throttled internet -- downloads/uploads must go
   through the Transfer Queue, not a regular job.** A compute-node job that
   does heavy I/O over the general internet risks being killed under load.
   This directly affects `dataPrep_Monitor`'s download steps (CLMS land
   cover, DEM tiles, land use rasters via its `python/download_*.py`
   scripts): route those through the Transfer Queue, or better, run them
   once on a login/transfer node *before* submitting the compute-only model
   fitting stages to the regular partition. Don't bundle "download raw data"
   and "fit model" into the same SLURM task.
   Wiki: https://wiki.ufz.de/eve/index.php/File_Transfer
4. **Memory requests change which nodes you're even eligible for.** Most EVE
   nodes are provisioned at 6-8GB RAM per core; a smaller subset has ~3x that.
   Requesting more than ~8GB/core routes the job to that smaller node pool --
   which can mean a longer queue wait even though the job itself would run
   fine on a standard node. Consequence: **right-size `--mem` to measured
   usage, don't round up "to be safe."**
   - birdMonitor's own measured local peak is ~11GB (single-species,
     single-scale fit) -- already above the 6-8GB/core standard envelope, so
     these jobs will land on the larger-memory node pool regardless. That's
     fine and expected; just don't request further above what's measured
     (e.g. the habitat array's current `--mem=16G` has real headroom above
     the observed ~11GB peak -- worth tightening towards ~12-13G once a real
     EVE run confirms actual peak there, to stay as close to the true need
     as the "real margin" comment in that file already intends).
   - Storage is requested/managed separately from job memory -- see
     https://wiki.ufz.de/eve/index.php/Storage before a run that will write
     a lot of raster output.

## Fair-share priority: don't dump the whole array at once without thinking about it

5. There's no hard cap on concurrent jobs per user, but **the more jobs you
   have in the queue, the lower your scheduling priority drops** (so other
   users still get a fair shot). This matters for birdMonitor specifically
   because the full species x scale design submits 4 arrays (europe/
   habitat/landscape/meta) x up to 11 tasks each -- over 30 jobs in one go.
   - If wall-clock time isn't the binding constraint, consider staging
     submissions (e.g. habitat first, since it's the long pole and self-
     triggers meta on completion -- see `checkAllScalesReady()` in
     `models_Monitor.R`) rather than firing all four arrays simultaneously.
   - If everything needs to run ASAP, submit the full array anyway and
     accept the priority hit -- just don't be surprised by a queue-wait
     increase as more of your own jobs stack up.
   - Requesting **less** of any resource (mem, cpu, walltime) makes it
     easier for the scheduler to slot the job in sooner, independent of the
     priority effect above.

## Quick pre-submission checklist

- [ ] VPN connected
- [ ] Required module(s) confirmed loadable (`module spider <name>`) or
      installed in your own EVE directory
- [ ] Any raw-data download step routed through the Transfer Queue, not a
      compute-node job
- [ ] `--mem`/`--cpus-per-task` matched to measured usage, not padded further
      "to be safe" beyond existing documented margins
- [ ] Aware of how many jobs this submission adds to your queue, and
      whether staging makes more sense than firing everything at once
- [ ] Output path points at appropriately-provisioned storage (see Storage
      wiki page above)
