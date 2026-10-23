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
2. **Sample map (.csv)** with **exactly the same file name** as the .txt. It needs these headers:

   | sample_number | sample_name | start_dilution |
   |---|---|---|
   | 1 | Sample_01 | 20 |
   | 2 | Sample_02 | 20 |
   | ... | ... | ... |

   `sample_number` is 1–16, following the plate layout below. `start_dilution` is the reciprocal starting dilution.

## Plate layout

| | 1–8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|
| **A–D** | Samples 1–8 (one per column, 3-fold dilutions down rows A–D) | Max IL-8 (A–B) / Min IL-8 (C–D) | Max IL-8 (A–B) / Min IL-8 (C–D) | Calibrators 1–4 | Calibrators 1–4 |
| **E–H** | Samples 9–16 (one per column, 3-fold dilutions down rows E–H) | IVIG | IVIG | Calibrators 5–7, blank (H) | Calibrators 5–7, blank (H) |

## Settings (Section 2)

| Setting | Default | Change when |
|---|---|---|
| `msd_file` | – | Every run: the full path to the .txt export |
| `cal_concentrations` | 583 pg/mL top, 4-fold | **Check against the IL-8 certificate of analysis for each lot** |
| `dilution_factor`, `n_sample_points` | 3-fold, 4 points | The sample dilution series changes |
| `ivig_start_dilution` | 12.5 | The IVIG dilution series changes |
| `sample_dilution_correction` | 50 | The dilution in the MSD step changes |

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
  - Plots
- **`[file name]_plots/`** with 4 plots:
  1. standard curve
  2. IL-8 across dilutions
  3. standard curve with samples
  4. IC50 regression

QC flags duplicate CVs above 5% for the calibrators, controls and IVIG.

## IC50 status

| Status | Meaning |
|---|---|
| Interpolated | IC50 within the dilution series |
| Insufficient activity | IL-8 stays below the 50% value at every dilution. The IC50 is assigned as half the starting dilution. |
| High activity - retest | IL-8 stays above the 50% value, so the IC50 is beyond the dilution series. Repeat at a higher dilution. |
| No result | Too few valid points to calculate an IC50 |
