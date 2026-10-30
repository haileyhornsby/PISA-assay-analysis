# Control tracking (all assays)

`Control Tracking Script.R` follows the assay controls across plates, so unusual plates and gradual drift stand out.

Every results workbook made by the assay scripts has a **Control summary** sheet. This script reads those sheets from every results file in a folder and puts them together.

| Assay          | Controls tracked                                                                                     |
|----------------|------------------------------------------------------------------------------------------------------|
| 10-plex MSD    | MSD controls C1–C3 (AU/mL, each antigen); mAb pool at one dilution (AU/mL, GAC, ScpA, SpyAD, SpyCEP) |
| SpyCEP IL-8    | IVIG IC50; Max IL-8, Min IL-8 and 50% IL-8 (ng/mL)                                                   |
| SLO haemolysis | IVIG IC50; no haemolysis and max haemolysis control OD540                                            |

## How to use it

1. Keep the results files for an assay together in one folder. Subfolders are fine, e.g. one per run. Results from all three assays can share a folder, because each assay is summarised separately.
2. Open `Control Tracking Script.R` in RStudio and click **Source**.
3. In the window that opens, choose the results folder.
4. The script saves two things in that folder:
   - **`control_tracking_[date].xlsx`**:
     - **Read me**
     - **Files**: which results files were used or skipped
     - a **summary** sheet for each assay: number of plates, geometric mean, median, plate-to-plate CV (using all plates, and robust), and limits
     - a **values** sheet for each assay: every plate's control values, each with a flag
     - a **plots** sheet for each assay
   - **`control_tracking_[date]_plots/`**: the trend plots as images. There is one plot per assay, or for the 10-plex one per MSD control (C1, C2, C3) and one for the mAb pool, with a panel for each antigen in spot order.

Run it whenever you like, e.g. after each batch of plates. It always rebuilds the summary from the results files, so nothing is lost or counted twice.

## Things to know

- **Re-analysed plates are only counted once.** If the same plate has been analysed more than once, only the most recent analysis is used. The Files sheet lists the older ones as "Not used".
- **Older results files are skipped.** Results made before the Control summary sheet was added are listed as skipped. To include them, re-analyse those plates with the current scripts.
- **Plate date:** taken from the file name where it contains a date (MSD exports include one; for SLO, name the file e.g. `SLO_hemolysis_24-10-26.csv`). Otherwise the date the data file was last modified is used.
- **Missing values are shown, not hidden.** Every control has a panel, even if no plate gave it a value. Each panel title says how many plates gave a value (e.g. "values from 4 of 6 plates"), and plates with no value appear as grey ticks along the bottom. The values sheet gives the reason, e.g. duplicate CV too high.
- **Statistics use log10 values,** because IC50s and concentrations vary by fold-changes. The plate-to-plate CVs are geometric CVs.

## Limits are for information only

Once a control has values from **5 or more plates**, the plots show the **median** (solid line) with **±2 robust SD** (dashed) and **±3 robust SD** (dotted) lines. Each plate is flagged *Within 2 SD*, *Outside 2 SD* or *Outside 3 SD*.

The robust SD comes from the median absolute deviation (MAD), so one unusual plate can't widen the limits it is judged against. With an ordinary SD, a plate reading 1.6× too high would not be flagged at all until about 15 plates had been run. With the robust SD it is flagged almost every time, even with 6 plates.

How to read the flags:
- **Outside 3 SD** is worth looking into: check the plate, the reagents and the run notes.
- **Outside 2 SD** happens by chance for about 1 in 10 values while there are only a few plates. Treat it as "keep an eye on", especially for the 10-plex, which has 34 control values per plate.
- **A whole plate outside on many antigens or controls together** (e.g. all of ctrl 2 high) points to a plate or reagent problem rather than chance.

The limits are calculated from the plates themselves, so they describe the variation seen so far. They are not acceptance criteria. Once enough plates have been run (around 15–20 per assay), use the summaries to agree acceptance criteria for the SOPs. The criteria can then be built into the assay scripts.
