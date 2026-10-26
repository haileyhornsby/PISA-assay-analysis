# PISA assay analysis scripts

R scripts for analysing the PISA *Streptococcus pyogenes* serology and functional assays. This repository holds the **master copies**, so every lab uses identical scripts.

| Assay                                      | SOP   | Folder                 | Script                              | Input template                    |
|--------------------------------------------|-------|------------------------|-------------------------------------|-----------------------------------|
| 10-plex GAS antigen MSD serology           | SOP 1 | [10-plex MSD assay]    | `10-plex GAS MSD Analysis Script.R` | `10-plex_sample_map_template.csv` |
| SpyCEP IL-8 cleavage (neutralisation)      | SOP 2 | [SpyCEP IL-8 assay]    | `IL-8 MSD Analysis Script.R`        | `IL-8_sample_map_template.csv`    |
| SLO haemolysis inhibition (neutralisation) | SOP 3 | [SLO haemolysis assay] | `SLO Haemolysis Analysis Script.R`  | `SLO_plate_template.csv`          |
| Control tracking (all assays)              | –     | [Control tracking]     | `Control Tracking Script.R`         | –                                 |

Each assay folder has a README with the plate layout, how to fill in the input template, and how to read the results. The **Control tracking** script follows each assay's controls across plates; see its README.

You never need to edit the scripts. When you run one, a window opens and you choose your data file.

---

## Getting the scripts

There are two ways. **Option A is recommended** if you analyse plates regularly, because updates take one click.

### Option A: link RStudio to this repository (recommended)

**Once only:**

1. Install **R** (version 4.5.0 or later) and **RStudio**. If you don't have admin rights, ask your IT team.
2. Install **Git**:
   - **Windows:** download it from [git-scm.com/download/win](https://git-scm.com/download/win) and install with all the default options.
   - **Mac:** open Terminal, type `git --version` and press Enter. If Git isn't installed, you'll be offered an install.
3. Close and reopen RStudio.
4. In RStudio, click **File → New Project… → Version Control → Git**.
5. In **Repository URL**, paste:
   ```
   https://github.com/haileyhornsby/PISA-assay-analysis.git
   ```
   Leave the project directory name as `PISA-assay-analysis`. Under **Create project as subdirectory of**, click **Browse** and choose where to keep it (e.g. Documents). Click **Create Project**.
6. RStudio downloads everything and opens the project. The three assay folders appear in the **Files** tab (bottom right).

If step 4 doesn't show a Git option, RStudio can't find Git. Go to **Tools → Global Options → Git/SVN**, tick **Enable version control**, set the **Git executable** (on Windows, usually `C:/Program Files/Git/bin/git.exe`), then restart RStudio.

**Getting updates (before analysing a plate):**

1. Open the project: **File → Open Project…** and choose `PISA-assay-analysis.Rproj`, or pick it from the project menu at the top right of RStudio.
2. Click the **Git** tab (top right), then the blue **Pull** arrow (↓).
3. You'll see either *Already up to date* or a list of the files that were updated.

You don't need a GitHub account. This only ever downloads, so nothing you do can change the master copies.

### Option B: download a ZIP

1. Install **R** (version 4.5.0 or later) and **RStudio**.
2. On this page, click the green **`<> Code`** button, then **Download ZIP**.
3. Unzip the folder somewhere you can find it, e.g. Documents.

To get updates, download the ZIP again and replace your old folder. Check the `script_version` at the top of each script if you're not sure whether you have the latest copy.

---

## Analysing a plate

1. **Get the latest scripts:** **Pull** (Option A) or a fresh ZIP (Option B).

2. **Prepare the input files.** Copy the assay's input template into the folder where you keep your plate data, then fill it in. The assay README and the SOP explain how.
   - Fill in **every** plate position. For an unused position, write `empty` as the sample name and leave the dilution blank. The script stops if anything is left blank, so a forgotten entry can't be mistaken for an unused position.
   - **MSD assays:** save the sample map in the same folder as the MSD .txt export, with **exactly the same file name** (only the ending differs: `.csv` instead of `.txt`).
   - Keep your data files outside the `PISA-assay-analysis` folder.

3. **Open the script in RStudio.** In the **Files** tab, open the assay folder and click the script, or use **File → Open File**.

4. **Run the script:** click **Source** (top right of the script window), or press Ctrl+Shift+Enter. The first time, any missing R packages are installed automatically. This needs an internet connection and can take a few minutes.

5. **Choose your data file** in the window that opens:
   - **MSD assays:** the .txt export (each spot as plate)
   - **SLO:** your filled-in plate .csv

   The window may open behind RStudio. If nothing seems to happen, check the taskbar.

6. **If the script stops**, read the red message in the Console. It tells you what to fix (see [Common messages](#common-messages) below). Correct the input file, save it, and run the script again.

7. **Check the results.** When the Console says *Analysis complete*, you'll find two things in the same folder as your data file:
   - **`[file name]_analysis.xlsx`**: QC, results and plots
   - **`[file name]_plots`**: the plots as image files

   Check the QC sheets before using any results. The assay README and SOP explain what to look for.

8. **Record the script version** in the processing record. It's shown in the *Assay parameters* sheet of the results file.

---

## Common messages

| Message in the Console                                              | What to do                                                                                                                                       |
|---------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| `No file was chosen`                                                | The file window was closed without choosing a file. Run the script again.                                                                        |
| `does not exist` / `cannot open file`                               | For the MSD assays, the sample map must be in the same folder as the .txt file, with exactly the same name.                                      |
| `No Sample ID ...` / `No sample_name ...`                           | A plate position has been left blank. Enter the sample name, or write `empty` if it wasn't used.                                                 |
| `... missing from the sample map`                                   | A sample_number row has been deleted from the sample map. Start again from a fresh template, which has a row for every position.                 |
| `... marked empty but have a starting dilution`                     | Delete the dilution for positions marked `empty`.                                                                                                |
| `Missing or non-numeric starting dilution`                          | Enter the dilution as a number only, e.g. `50` for 1:50 (not `1:50`).                                                                            |
| `Expected 10 MSD data sections` / `Expected 12 values in plate row` | The MSD file was exported in the wrong format. Re-export it as **each spot as plate**.                                                           |
| `Could not find the 'Plate column' table and the OD540 grid`        | The SLO input file wasn't made from `SLO_plate_template.csv`. Copy your data into a fresh template.                                              |
| `Control CV above ...` (warning)                                    | The plate controls don't agree. Check the plate before using the results.                                                                        |
| `Installing missing packages` then an error                         | Check your internet connection. If your network blocks downloads, ask IT to install the packages listed at the top of the script.                |
| **Pull** fails: `Your local changes would be overwritten`           | A script has been edited on your computer. In the **Git** tab, select the file, click **More → Revert…** to undo the edits, then **Pull** again. |

Messages starting `Warning` don't stop the script, but read them before using the results.

---

## Questions, problems and suggested changes

Please **don't edit the scripts**, because every lab needs to use identical analysis. If something doesn't work, or you think a script should change, contact Hailey Hornsby (University of Sheffield), or open an issue on the **Issues** tab of this page.

**Never upload data or results here.** This repository is public.

---

*Maintainers: see [MAINTAINING.md](MAINTAINING.md) for how to update the scripts.*

[10-plex MSD assay]: 10-plex%20MSD%20assay
[SpyCEP IL-8 assay]: SpyCEP%20IL-8%20assay
[SLO haemolysis assay]: SLO%20haemolysis%20assay
[Control tracking]: Control%20tracking
