# SpyCEP IL-8 cleavage assay (SOP 2)

`IL-8 MSD Analysis Script.R` analyses MSD plates from the SpyCEP neutralisation assay. SpyCEP cleaves IL-8, and neutralising antibodies prevent this cleavage. The IC50 is the serum dilution at which IL-8 is halfway between the Max (uncleaved) and Min (fully cleaved) controls.

**Method:**
1. Fit a 4PL standard curve (1/Y² weighting, best of many starting values) to the IL-8 calibrators.
2. Convert sample signals to ng/mL IL-8, corrected for the 1:50 assay dilution.
3. Calculate the 50% IL-8 value as (Max − Min)/2 + Min.
4. Interpolate each sample's IC50 by linear regression of IL-8 against log₁₀(dilution).

## Input files

Put both files in the same folder:

1. **MSD export (.txt)** in the "each spot as plate" format.
2. **Sample map (.csv)**: copy **`IL-8_sample_map_template.csv`**, fill it in, and save it with **exactly the same file name** as the .txt (only the ending differs). The template already has these headers and a row for every position:

   | sample_number | sample_name | start_dilution |
   |:-------------:|:-----------:|:--------------:|
   |       1       |  Sample_01  |       20       |
   |       2       |  Sample_02  |       20       |
   |      ...      |     ...     |      ...       |
   |      16       |    empty    |                |

   `sample_number` is 1–16, following the plate layout below. `start_dilution` is the reciprocal starting dilution.

   **Every position 1–16 must have a row.** For an unused position, write `empty` as the sample_name and leave start_dilution blank. The script stops with a message if a sample_name is blank or a position number is missing from the file, so a forgotten entry can't be mistaken for an unused position. It also stops if an `empty` position has a dilution, or a sample has no dilution.

## Plate layout

|       |    1     |     2     |     3     |     4     |     5     |     6     |     7     |     8     |    9     |    10    |  11   |  12   |
|:-----:|:--------:|:---------:|:---------:|:---------:|:---------:|:---------:|:---------:|:---------:|:--------:|:--------:|:-----:|:-----:|
| **A** | Sample 1 | Sample 2  | Sample 3  | Sample 4  | Sample 5  | Sample 6  | Sample 7  | Sample 8  | Max IL-8 | Max IL-8 | Cal 1 | Cal 1 |
| **B** | Sample 1 | Sample 2  | Sample 3  | Sample 4  | Sample 5  | Sample 6  | Sample 7  | Sample 8  | Max IL-8 | Max IL-8 | Cal 2 | Cal 2 |
| **C** | Sample 1 | Sample 2  | Sample 3  | Sample 4  | Sample 5  | Sample 6  | Sample 7  | Sample 8  | Min IL-8 | Min IL-8 | Cal 3 | Cal 3 |
| **D** | Sample 1 | Sample 2  | Sample 3  | Sample 4  | Sample 5  | Sample 6  | Sample 7  | Sample 8  | Min IL-8 | Min IL-8 | Cal 4 | Cal 4 |
| **E** | Sample 9 | Sample 10 | Sample 11 | Sample 12 | Sample 13 | Sample 14 | Sample 15 | Sample 16 |   IVIG   |   IVIG   | Cal 5 | Cal 5 |
| **F** | Sample 9 | Sample 10 | Sample 11 | Sample 12 | Sample 13 | Sample 14 | Sample 15 | Sample 16 |   IVIG   |   IVIG   | Cal 6 | Cal 6 |
| **G** | Sample 9 | Sample 10 | Sample 11 | Sample 12 | Sample 13 | Sample 14 | Sample 15 | Sample 16 |   IVIG   |   IVIG   | Cal 7 | Cal 7 |
| **H** | Sample 9 | Sample 10 | Sample 11 | Sample 12 | Sample 13 | Sample 14 | Sample 15 | Sample 16 |   IVIG   |   IVIG   | Blank | Blank |

- **Samples 1–16:** one per column, 4-point dilution series. Rows A and E are the starting dilution, and each row down is a further 3-fold dilution.
- **Max IL-8 / Min IL-8:** controls for uncleaved and fully cleaved IL-8 (4 wells each).
- **IVIG:** in duplicate, starting at 1:12.5, with 3-fold dilutions down rows E–H.
- **Cal 1–7:** IL-8 calibrators in duplicate, 4-fold dilutions from the top concentration on the certificate of analysis. The concentrations are set in the script. Tell the script maintainer when a new IL-8 lot is introduced, so the script can be updated. **Blank** is the assay blank.

## Outputs

Saved next to the .txt file:

- **`[file name]_analysis.xlsx`**, with these sheets:
  - Assay parameters
  - Plate
  - Sample map
  - Plate plan
  - Calibration QC
  - Control QC
  - IVIG QC
  - Calibration check
  - Sample results
  - IC50 results
  - **IC50 summary**
  - **Control summary**: IVIG IC50 and control values, used by the Control Tracking Script
  - Plots
- **`[file name]_plots/`** with 4 plots:
  1. standard curve
  2. IL-8 across dilutions
  3. standard curve with samples
  4. IC50 regression

QC flags duplicate CVs above 10% (provisional) for the calibrators, controls and IVIG.

## IC50 status

| Status                 | Meaning                                                                                                                                                                     |
|------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Interpolated           | IC50 within the dilution series                                                                                                                                             |
| Insufficient activity  | IL-8 stays below the 50% value at every dilution. The IC50 is assigned as half the starting dilution.                                                                       |
| High activity - retest | IL-8 stays above the 50% value, so the IC50 is beyond the dilution series. Repeat at a higher dilution.                                                                     |
| No result - check      | Fewer than 3 of the 4 dilutions have a signal inside the calibration range, or the fitted line puts the IC50 outside the dilutions tested. Look at the sample individually. |
