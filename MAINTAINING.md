# Maintaining the PISA analysis scripts

Instructions for updating the master copies. Changes are made by Hailey Hornsby (University of Sheffield). Every change is recorded on GitHub with a short description, so any earlier version can be recovered.

## One-off setup on a new computer

1. Install [Git for Windows](https://git-scm.com/download/win), keeping the default options.
2. Open **Git Bash** and tell Git who you are:
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```
3. Download a copy of the repository into your Documents folder:
   ```bash
   cd ~/Documents
   git clone https://github.com/haileyhornsby/PISA-assay-analysis.git
   ```

## Each time you change a script

Open Git Bash in the `PISA-assay-analysis` folder (right-click in the folder → **Open Git Bash here**), then:

1. **Get the latest version first**, in case it was changed from another computer:
   ```bash
   git pull
   ```
2. **Edit the script** in RStudio and test it on real data.
3. **Increase `script_version`** at the top of the script: for example 1.0 → 1.1 for a small fix, or 1.0 → 2.0 for a change that alters results.
4. **Check what has changed.** Only the files you meant to change should be listed, and never any data or results:
   ```bash
   git status
   ```
5. **Save a snapshot (commit)** with a message saying what changed and why:
   ```bash
   git add "SLO haemolysis assay/SLO Haemolysis Analysis Script.R"
   git commit -m "SLO v1.1: changed control CV limit to 10%"
   ```
6. **Upload it to GitHub (push):**
   ```bash
   git push
   ```
   The first time, a window opens asking you to sign in to GitHub.

If a change affects how the assay is run or analysed, update the SOP and the assay README as well.

## Assay values fixed in the scripts

Users never edit the scripts: each script asks for its input file in a pop-up window when it runs, so users can always **Pull** updates without conflicts. Every assay value sits in the **"Fixed assay information - do not change"** block near the top of each script, and is changed only by the maintainer, with a new script version. Values that may need updating:

- **IL-8 (`cal_concentrations`):** the top IL-8 calibrator concentration from the certificate of analysis. Update it for each new IL-8 lot.
- **10-plex (`spot_map$top_AU_ml`):** the AU/mL assigned to S1 for each antigen.
- **QC limits, dilution series, control dilutions and IVIG starting dilutions**, if the SOP changes.

## Control tracking and acceptance criteria

Each assay script writes a **Control summary** sheet, which the `Control tracking` script collects. If you change which controls are tracked, keep the Control summary columns the same (assay, plate, assay_date, analysis_date, script_version, control, measure, unit, value, cv_percent, status), so old and new results files can still be combined.

Once enough plates have been run (around 15–20 per assay), use the summary sheets from the tracking script to agree acceptance criteria for the controls, e.g. IVIG IC50 within the geometric mean ±2 SD, or within 2-fold. Then add the criteria to the SOPs, and to the assay scripts as a QC check with a new script version. Until then, the tracking limits are for information only.

For the 10-plex mAb pool, `mab_tracking_point` sets which mAb dilution is tracked. It is provisional: choose a dilution in the middle of the curve once real mAb data are available.

## Keeping data out of the repository

The repository is public. The `.gitignore` file stops plate data (`.txt`, `.csv`), results workbooks, plots and R history files being committed. The only exceptions are the three input templates. If you add a new template, add a `!` exception line for it in `.gitignore`. Always check `git status` before committing, and never use `git add -f`, which overrides `.gitignore`.

## An older copy on another computer

If a computer has a copy made before the repository was renamed from `PISA-SpyCEP-IL-8-cleavage-assay-analysis`, point it at the new name once:
```bash
git remote set-url origin https://github.com/haileyhornsby/PISA-assay-analysis.git
git pull
```

## Planned changes

- **10-plex:** interpolate ng/mL values for each target antigen in the mAb pool (GAC, ScpA, SpyAD, SpyCEP). Do this once real mAb data are available, and choose `mab_tracking_point` for control tracking at the same time.
- **All assays:** confirm the duplicate CV limits (currently provisional) and agree acceptance criteria for the controls, using the control tracking summaries.
