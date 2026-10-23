# SLO haemolysis inhibition assay (SOP 3)

`SLO Haemolysis Analysis Script.R` analyses OD540 plates from the SLO neutralisation assay. SLO lyses red blood cells, and neutralising antibodies inhibit this haemolysis.

**Method:**
1. Convert OD540 to % haemolysis, using the no-haemolysis (0%) and max-haemolysis (100%) controls, and from that to % inhibition.
2. Fit a 4PL curve to each sample and IVIG, with the curve fixed at 0% and 100% inhibition. The best fit is chosen from many starting values.
3. Report the IC50 (the reciprocal dilution giving 50% inhibition) with a 95% confidence interval from `drc`.

## Input file

The plate reader software differs between sites, so the OD values are copied into a standard template.

1. Copy **`SLO_plate_template.csv`** and rename it after the run, e.g. `SLO_hemolysis_24-10-26.csv`.
2. Open it in Excel and fill in:
   - **Sample ID** row: sample names for plate columns 1–10. Leave unused columns blank; they are skipped and listed in a message. Column 11 is IVIG and column 12 the controls.
   - **Starting dilution** row: the reciprocal starting dilution of each column (50 = 1:50).
   - **Rows A–H:** paste the 8 × 12 block of OD540 values from the plate reader.
3. Save the file as .csv.

## Plate layout

| | 1–10 | 11 | 12 |
|---|---|---|---|
| **A–D** | Samples (one per column, singlicate, 2-fold dilutions down rows A–H) | IVIG (2-fold dilutions down rows A–H) | No haemolysis |
| **E–H** | | | Max haemolysis |

## Settings (Section 2)

| Setting | Default | Change when |
|---|---|---|
| `plate_file` | – | Every run: the full path to the .csv |
| `dilution_factor`, `n_points` | 2-fold, 8 points | The dilution series changes |
| `control_cv_limit` | 10% | QC criteria change |
| `exclude_control_outliers` | TRUE | Set to FALSE to turn off automatic exclusion of a control well |
| `dynamic_range` | 25–75% | The curve-acceptance criteria change |

## Control QC

Each control (no haemolysis and max haemolysis) has 4 wells.

- If the CV of the 4 wells is 10% or less, all 4 are used.
- If it is above 10%, but removing one well brings the other 3 within 10%, that well is excluded. This is shown in the Control QC sheet and outlined on the plate heatmap.
- At most one well is excluded per control. If the control still fails, it is marked **FLAG** and the script warns you to check the plate.

## Outputs

Saved next to the .csv file:

- **`[file name]_analysis.xlsx`**, with these sheets:
  - Assay parameters
  - Plate
  - Sample map
  - Plate plan
  - Control QC
  - Control wells
  - Sample results
  - IC50 results
  - **IC50 summary**
  - Plots
- **`[file name]_plots/`** with 3 plots:
  1. % haemolysis plate heatmap
  2. inhibition curves for each sample
  3. all curves together

## IC50 status

An IC50 is only reported when the curve crosses 50% inhibition and includes at least one point below 25% and one above 75% inhibition. Samples outside the range of the assay are retested, and no value is assigned.

| Status | Meaning |
|---|---|
| Interpolated | Valid IC50 |
| High activity - retest | All wells above 50% inhibition. Retest at a higher starting dilution. |
| Insufficient activity - retest | All wells below 50% inhibition. Retest at a lower starting dilution. |
| Partial curve - check | Crosses 50%, but does not include a point below 25% and one above 75% inhibition |
| No result | Curve could not be fitted |
