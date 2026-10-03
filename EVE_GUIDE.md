# Running birdMonitor on the EVE cluster -- step by step

Written for someone who has never used a cluster. Do the steps **in order** and do
not skip any. Anything in a grey box is typed into a terminal, one line at a time.
If a step prints an error, stop and send the whole output to the person helping you.

Words you will meet:
- **Login node** (`frontend1.eve.ufz.de` / `frontend2.eve.ufz.de`): the computer you
  type into. Never run heavy work there -- you *submit jobs* from it.
- **Job**: a script the cluster runs for you on a compute node, when there is room.
- **Module**: EVE hides its software until you "load" it (`module load ...`).
- **/home**: 80 GiB, backed up. Only code and R packages go here.
- **/work/YOURNAME**: no size limit, no backup, **files not touched for 60 days are
  deleted automatically**. Data and results live here while you run.
- **/data/birds**: shared project folder (once EVE has created it). The long-term
  copy of the input data lives here.

## Part A -- once per person

### A1. Account and VPN
1. Ask for an EVE account: e-mail `wkdv-cluster@ufz.de`, subject `request account ufz`,
   text `Please create a new account for: <your name>`.
2. Connect the UFZ VPN. EVE cannot be reached without it.

### A2. Log in (Windows PowerShell)
Windows needs a one-time fix, otherwise you get "Corrupted MAC on input". In PowerShell:
```
mkdir $HOME\.ssh
notepad $HOME\.ssh\config
```
Paste this into the file (replace `USERNAME` with your UFZ user name), save, close:
```
Host *.eve.ufz.de
   Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
   MACs hmac-sha2-256

Host *.ufz.de
   User USERNAME
```
(If Notepad saves it as `config.txt`, rename it to `config` without the `.txt`.)
Then log in:
```
ssh frontend1.eve.ufz.de
```
Type your UFZ password. The first time, answer `yes` to the question about the host key.

### A3. Download the code
On EVE:
```
mkdir -p ~/projects
cd ~/projects
git clone --recurse-submodules https://github.com/tati-micheletti/birdMonitor.git
cd birdMonitor
git submodule foreach 'git checkout main'
```
Use exactly this HTTPS address (the `git@github.com` address does not work on EVE).

### A4. Set everything up (one command, 30-60 minutes)
```
bash --login cluster/setup_eve.sh
```
It loads the modules, creates your `/work` folders, links `inputs`/`cache`/`outputs` to
them, installs all R packages, and submits a 10-minute test. Keep the window open until it
ends. If it stops, run the same command again -- it continues where it stopped.

About a minute after it finishes:
```
squeue -u $USER
cat logs/smoketest_NNN.err
```
(`NNN` = the job number the script printed.) The last line must be `SMOKETEST: ALL OK`.
If you see a `FAIL` line instead, send the file to the person helping you.

### A5. Get the input data
The data (about 60 GB) is **not** in git. Ask the project administrator for it, then
either:
- **from the shared project folder** (fast, no upload; works once `/data/birds` exists and
  you were added to its group):
  ```
  rsync -avhP /data/birds/inputs/ /work/$USER/birdMonitor/inputs/
  ```
- **or** from a PC with WinSCP: synchronize the PC's `inputs` folder to
  `/work/YOURNAME/birdMonitor/inputs`. Leave out `predictors/raw/dem`,
  `predictors/raw/chelsa_monthly` and `predictors/processed/dem` unless told otherwise.

Do not copy data into `/home`. EVE will block your account when `/home` is over its limit
(check with `quota-eve`).

## Part B -- every time you want to run the pipeline

```
ssh frontend1.eve.ufz.de
cd ~/projects/birdMonitor
git pull
git submodule foreach 'git checkout main && git pull --ff-only origin main'
bash cluster/submit_eve_pipeline.sh
```
This submits the whole workflow as one chain: data preparation, then one model task per
species and scale, then the index. You do not need to keep the window open.

Useful commands:
| What | Command |
|---|---|
| What is running or waiting? | `squeue -u $USER` |
| Why is a job waiting? | `squeue -t pd -o "%i %R"` |
| Cancel everything | `scancel --me` |
| Logs of the jobs | files in `logs/` (`.out` = normal output, `.err` = messages and errors) |
| How long/how much memory did a finished job use? | `sacct -j JOBID --format=JobID,Elapsed,MaxRSS,State` |
| Disk quota | `quota-eve` |

If the first (preparation) job fails, the model jobs that wait for it are cancelled
automatically. Read `logs/prep_JOBID.err`, fix the cause (ask for help with that text),
and run `bash cluster/submit_eve_pipeline.sh` again. Work already done is reused.

## Part C -- results
They are in `/work/YOURNAME/birdMonitor/outputs/<run name>/`. **Copy results you want to
keep to `/data/birds` (or to your PC) within a few weeks** -- `/work` deletes old files
and has no backup.

Download results to a Windows PC with WinSCP (right panel = EVE, left panel = PC).

## Rules of the house (from the EVE wiki)
- Never store data in `/home`; never run heavy work on the login nodes.
- No downloads inside jobs (compute nodes have almost no internet).
- Do not submit hundreds of separate jobs in a loop -- use job arrays (the scripts do).
- Questions to the cluster admins: `wkdv-cluster@ufz.de` (say what you ran, the job number
  and where the log is).
