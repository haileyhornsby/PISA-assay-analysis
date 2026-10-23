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
   - **Columns A–C (sample information):** one row for each sample column 1–10 on the plate. Enter the Sample ID and the reciprocal starting dilution (50 = 1:50).
   - **The OD540 grid (to the right of sample info):** paste the 8 × 12 block of OD540 values from the plate reader into the grid, starting in the cell under **1** and next to **A**.

   | A: Plate column | B: Sample ID | C: Starting dilution |     | E: OD540 |  1   |  2   | ... |  12  |
   |:---------------:|:------------:|:--------------------:|:---:|:--------:|:----:|:----:|:---:|:----:|
   |        1        |  Sample_01   |          50          |     |    A     | 0.05 | 0.04 | ... | 0.04 |
   |        2        |  Sample_02   |          50          |     |    B     | 0.26 | 0.15 | ... | 0.04 |
   |       ...       |     ...      |         ...          |     |   ...    | ...  | ...  | ... | ...  |
   |       10        |    empty     |                      |     |          |      |      |     |      |

3. Save the file as .csv.

**Every sample column 1–10 must be filled in.** For an unused column, write `empty` as the Sample ID and leave the dilution blank. The script stops with a message if a Sample ID is blank, so a forgotten entry can't be mistaken for an unused column. It also stops if an `empty` column has a dilution, or a sample has no dilution.

The IVIG (column 11) and the controls (column 12) are the same on every plate, so they're set in the script and don't need entering.

## Plate layout

|       |    1     |    2     |    3     |    4     |    5     |    6     |    7     |    8     |    9     |    10     |  11  |    12    |
|:-----:|:--------:|:--------:|:--------:|:--------:|:--------:|:--------:|:--------:|:--------:|:--------:|:---------:|:----:|:--------:|
| **A** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | No haem  |
| **B** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | No haem  |
| **C** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | No haem  |
| **D** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | No haem  |
| **E** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | Max haem |
| **F** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | Max haem |
| **G** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | Max haem |
| **H** | Sample 1 | Sample 2 | Sample 3 | Sample 4 | Sample 5 | Sample 6 | Sample 7 | Sample 8 | Sample 9 | Sample 10 | IVIG | Max haem |

- **Samples 1–10:** one per column, run in singlicate. Row A is the starting dilution entered in the input file, and each row down is a further 2-fold dilution (e.g. 1:50 to 1:6,400).
- **IVIG:** in singlicate, from 1:50 to 1:6,400 in 2-fold dilutions.
- **No haem:** no haemolysis control (PBS-DTT, no toxin), giving 0% haemolysis.
- **Max haem:** maximum haemolysis control (toxin, no serum), giving 100% haemolysis.

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

| Status                         | Meaning                                                                          |
|--------------------------------|----------------------------------------------------------------------------------|
| Interpolated                   | Valid IC50                                                                       |
| High activity - retest         | All wells above 50% inhibition. Retest at a higher starting dilution.            |
| Insufficient activity - retest | All wells below 50% inhibition. Retest at a lower starting dilution.             |
| Partial curve - check          | Crosses 50%, but does not include a point below 25% and one above 75% inhibition |
| No result                      | Curve could not be fitted                                                        |
