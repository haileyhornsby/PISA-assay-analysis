# 10-plex GAS antigen MSD serology (SOP 1)

`10-plex GAS MSD Analysis Script.R` analyses MSD plates measuring IgG against 10 Streptococcus pyogenes antigens (GAC, DNase B, SLO, OppA, PulA, SpnA, Spy0843, SpyAD, ScpA, SpyCEP).

**Method:** for each antigen, a 4-parameter logistic (4PL) curve with 1/Y² weighting is fitted to the IVIG calibrators. The best fit is chosen from many starting values. Sample signals are then interpolated and corrected for the sample dilution to give AU/mL.

## Input files

Put both files in the same folder:

1. **MSD export (.txt)** in the "each spot as plate" format. This contains all 10 spots.
2. **Sample map (.csv)**: copy **`10-plex_sample_map_template.csv`**, fill it in, and save it with **exactly the same file name** as the .txt (only the extension differs). The template already has these headers and a row for every position:

   | sample_number | sample_name | start_dilution |
   |:-------------:|:-----------:|:--------------:|
   |       1       |  Sample_01  |     100000     |
   |       2       |  Sample_02  |     100000     |
   |      etc      |     etc     |      etc       |
   |      20       |    empty    |                |

   `sample_number` is 1–20, following the plate layout below. `start_dilution` is the reciprocal dilution, e.g. 100000 for 1:100,000.

   **Every position 1–20 must have a row.** For an unused position, write `empty` as the sample_name and leave start_dilution blank. The script stops with a message if a sample_name is blank or a position number is missing from the file, so a forgotten entry can't be mistaken for an unused position. It also stops if an `empty` position has a dilution, or a sample has no dilution.

## Plate layout

|       |   1   |   2   |    3     |    4     |    5     |    6     |     7     |     8     |     9     |    10     |    11     |    12     |
|:-----:|:-----:|:-----:|:--------:|:--------:|:--------:|:--------:|:---------:|:---------:|:---------:|:---------:|:---------:|:---------:|
| **A** |  S1   |  S2   |    S3    |    S4    |    S5    |    S6    |    S7     |    S8     |    S9     |    S10    |    S11    |    S12    |
| **B** |  S1   |  S2   |    S3    |    S4    |    S5    |    S6    |    S7     |    S8     |    S9     |    S10    |    S11    |    S12    |
| **C** |  C1   |  C1   | Sample 1 | Sample 1 | Sample 5 | Sample 5 | Sample 9  | Sample 9  | Sample 13 | Sample 13 | Sample 17 | Sample 17 |
| **D** |  C2   |  C2   | Sample 2 | Sample 2 | Sample 6 | Sample 6 | Sample 10 | Sample 10 | Sample 14 | Sample 14 | Sample 18 | Sample 18 |
| **E** |  C3   |  C3   | Sample 3 | Sample 3 | Sample 7 | Sample 7 | Sample 11 | Sample 11 | Sample 15 | Sample 15 | Sample 19 | Sample 19 |
| **F** |   –   |   –   | Sample 4 | Sample 4 | Sample 8 | Sample 8 | Sample 12 | Sample 12 | Sample 16 | Sample 16 | Sample 20 | Sample 20 |
| **G** | mAb 1 | mAb 2 |  mAb 3   |  mAb 4   |  mAb 5   |  mAb 6   |   mAb 7   |   mAb 8   |   mAb 9   |  mAb 10   |  mAb 11   |  mAb 12   |
| **H** | mAb 1 | mAb 2 |  mAb 3   |  mAb 4   |  mAb 5   |  mAb 6   |   mAb 7   |   mAb 8   |   mAb 9   |  mAb 10   |  mAb 11   |  mAb 12   |

- **S1–S12:** IVIG calibrators, 2.5-fold dilutions. S12 is diluent only and is not used in the curve fit. The AU/mL assigned to S1 for each antigen is fixed in the script.
- **C1–C3:** MSD controls at 1:50,000, 1:200,000 and 1:800,000.
- **mAb 1–12:** a pool of GAC, ScpA, SpyAD and SpyCEP monoclonal antibodies at 1 µg/mL of each mAb, then 4-fold dilutions.

## Outputs

Saved next to the .txt file:

- **`[file name]_analysis.xlsx`**, with these sheets:
  - Assay parameters: the settings used and the script version
  - Plate
  - Sample map
  - Plate plan
  - Calibration QC
  - Calibration fits
  - Calibration check: % recovery of each calibrator
  - Control results
  - mAb results
  - Sample results: full detail
  - **Results summary**: AU/mL, one row per sample and one column per antigen
  - **Status summary**
  - **Control summary**: the MSD controls and mAb pool values, used by the Control Tracking Script
  - Plots
- **`[file name]_plots/`** with 4 plots:
  1. calibration curves
  2. calibration curves with interpolated samples
  3. results heatmap
  4. mAb curve: target antigens should respond, non-target antigens stay at background

## Result status

| Status                  | Meaning                                                                                                                  |
|-------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Interpolated            | Valid result (AU/mL corrected for dilution)                                                                              |
| Duplicate CV > 10%      | Duplicates disagree, so the sample is not interpolated                                                                   |
| Below calibration range | Signal below the lowest calibrator in the fit                                                                            |
| Above calibration range | Signal above the highest calibrator                                                                                      |
| No result - check       | Anything else, e.g. a missing or unreadable well, or a signal the curve cannot convert. Look at the sample individually. |

See SOP 1 for the action to take for each status.
