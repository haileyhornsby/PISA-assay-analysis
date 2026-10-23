# This script is designed to analyse the OD540 plate results of the
# PISA SLO haemolysis inhibition assay.
# Master copy: https://github.com/haileyhornsby/PISA-assay-analysis

script_version <- "1.0"

# Plate OD540 -> % haemolysis -> % inhibition -> 4PL fit -> IC50

# Necessary input file
# a .csv file made from "SLO_plate_template.csv":
#   - "Sample ID" row: sample names for plate columns 1-10 (IVIG in 11, Controls in 12)
#   - "Starting dilution" row: reciprocal starting dilution for each column (e.g. 50 for 1:50)
#   - rows A-H: raw OD540 values copied from the plate reader (columns 1-12)
# Leave the Sample ID blank for any unused columns.

# Plate layout
# Columns 1-10: samples (singlicate), 2-fold dilutions down rows A-H
# Column 11: IVIG, 2-fold dilutions down rows A-H
# Column 12: no haemolysis controls (A-D) and max haemolysis controls (E-H)


# ----------------------------
# 1. Packages
# ----------------------------

# Install any missing packages (only needed the first time), then load them
required_packages <- c("readr", "dplyr", "tidyr", "ggplot2", "openxlsx", "drc")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  message("Installing missing packages: ", paste(missing_packages, collapse = ", "))
  install.packages(missing_packages)
}

library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(openxlsx)
library(drc)
options(scipen = 999)

# ----------------------------
# 2. Files and assay settings
# ----------------------------

plate_file <- "C:/path/to/SLO_hemolysis_DD-MM-YY.csv" # paste the full path to the plate .csv here (use / not \)
output_file <- file.path(
  dirname(plate_file),
  paste0(tools::file_path_sans_ext(basename(plate_file)), "_analysis.xlsx"))
plot_dir <- file.path(
  dirname(plate_file),
  paste0(tools::file_path_sans_ext(basename(plate_file)), "_plots"))

# Plate layout
sample_cols <- 1:10 # sample columns, one dilution series per column
ivig_col <- 11 # IVIG dilution series
control_col <- 12 # haemolysis controls
no_haem_rows <- c("A", "B", "C", "D") # no haemolysis (PBS-DTT, no toxin)
max_haem_rows <- c("E", "F", "G", "H") # maximum haemolysis (toxin, no serum)

# Dilution series
dilution_factor <- 2 # 2-fold steps down rows A-H
n_points <- 8 # each dilution series is 8 wells long
# starting dilution for each column is entered in the plate .csv

# QC
control_cv_limit <- 10 # control replicates are flagged if CV > 10%
exclude_control_outliers <- TRUE # if CV > limit, drop the single control well that brings the other 3 within the limit
dynamic_range <- c(25, 75) # a usable curve needs at least one point below 25% and one above 75% inhibition

# ------------------------------
# 3. Read in the plate data
# ------------------------------

raw <- read_csv(
  plate_file,
  col_names = FALSE,
  col_types = cols(.default = col_character()),
  trim_ws = TRUE
)

# Find the rows by their label in the first column
row_labels <- toupper(trimws(raw[[1]]))
id_row <- which(row_labels == "SAMPLE ID")
dilution_row <- which(row_labels == "STARTING DILUTION")
od_rows <- match(LETTERS[1:8], row_labels)

if (length(id_row) != 1 || length(dilution_row) != 1 || anyNA(od_rows)) {
  stop("Could not find the 'Sample ID', 'Starting dilution' and A-H rows. ",
       "Check the .csv was made from SLO_plate_template.csv.")
}

# Process OD data into an 8 x 12 data frame with numeric values
plate <- as.data.frame(
  lapply(raw[od_rows, 2:13], function(z) as.numeric(z))
)
rownames(plate) <- LETTERS[1:8]
colnames(plate) <- as.character(1:12)

# Check that every well has a value
if (anyNA(plate)) {
  stop("Missing or non-numeric OD values in wells: ",
       paste(outer(LETTERS[1:8], 1:12, paste0)[is.na(as.matrix(plate))], collapse = ", "))
}

# Check that plate data has been read in correctly
plate

# Convert plate to tidy format
plate_long <- expand.grid(
  row = LETTERS[1:8],
  col = 1:12,
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
) %>%
  mutate(
    well = paste0(row, col),
    OD540 = mapply(function(r, c) plate[r, as.character(c)], row, col)
  )

# ------------------------------------
# 4. Read sample IDs and annotate data
# ------------------------------------

sample_map <- tibble(
  col = 1:12,
  sample_name = as.character(unlist(raw[id_row, 2:13])),
  start_dilution = suppressWarnings(as.numeric(unlist(raw[dilution_row, 2:13])))
) %>%
  filter(col %in% c(sample_cols, ivig_col), !is.na(sample_name), sample_name != "") %>%
  mutate(type = if_else(col == ivig_col, "IVIG", "Sample"))

# Report any columns skipped because they have no Sample ID
skipped_cols <- setdiff(c(sample_cols, ivig_col), sample_map$col)
if (length(skipped_cols) > 0) {
  message("No Sample ID entered for plate column(s) ", paste(skipped_cols, collapse = ", "),
          " - these columns have not been analysed.")
}

if (anyNA(sample_map$start_dilution)) {
  stop("Missing starting dilution for: ",
       paste(sample_map$sample_name[is.na(sample_map$start_dilution)], collapse = ", "))
}

if (anyDuplicated(sample_map$sample_name)) {
  warning("Duplicate sample IDs found: ",
          paste(unique(sample_map$sample_name[duplicated(sample_map$sample_name)]), collapse = ", "))
}

sample_map

# Samples and IVIG
sample_wells <- sample_map %>%
  left_join(plate_long, by = "col", relationship = "one-to-many") %>%
  mutate(
    dilution = start_dilution * dilution_factor^(match(row, LETTERS[1:8]) - 1)
  ) %>%
  arrange(col, dilution)

# Controls
control_wells <- plate_long %>%
  filter(col == control_col) %>%
  mutate(type = case_when(row %in% no_haem_rows ~ "No haemolysis",
                          row %in% max_haem_rows ~ "Max haemolysis"))

# ----------------------------
# 5. Plate QC checks
# ----------------------------

# Controls
# If the CV of the 4 control wells is above the limit, each well is left out
# in turn. If leaving out one well brings the remaining 3 within the limit,
# that well is excluded (the one giving the lowest CV). At most one well is
# excluded per control, and a control is flagged if it still fails.

cv <- function(x) 100 * sd(x) / mean(x)

check_controls <- function(data) {
  used <- rep(TRUE, nrow(data))
  cv_all <- cv(data$OD540)
  if (exclude_control_outliers && cv_all > control_cv_limit && nrow(data) > 3) {
    cv_without <- vapply(seq_len(nrow(data)), function(i) cv(data$OD540[-i]), numeric(1))
    if (min(cv_without) <= control_cv_limit) {
      used[which.min(cv_without)] <- FALSE
    }
  }
  tibble(
    n_wells = nrow(data),
    n_used = sum(used),
    excluded_well = if (all(used)) NA_character_ else data$well[!used],
    cv_all_wells_percent = round(cv_all, 2),
    mean_OD = mean(data$OD540[used]),
    cv_percent = round(cv(data$OD540[used]), 2),
    cv_qc = case_when(
      cv_percent > control_cv_limit ~ "FLAG", # flag if control CV > limit
      !all(used) ~ "PASS - 1 well excluded",
      TRUE ~ "PASS"
    )
  )
}

control_qc <- control_wells %>%
  group_by(type) %>%
  group_modify(~ check_controls(.x)) %>%
  ungroup()

control_qc

# Record which control wells were used
control_wells <- control_wells %>%
  mutate(used = !(well %in% control_qc$excluded_well))

# generate a plate plan
plate_plan <- bind_rows(
  sample_wells %>%
    transmute(well, row, col, label = paste0(sample_name, "\n1:", dilution)),
  control_wells %>%
    transmute(well, row, col, label = if_else(used, type, paste0(type, "\n(excluded)")))
) %>%
  dplyr::select(row, col, label) %>%
  pivot_wider(names_from = col, values_from = label) %>%
  arrange(match(row, LETTERS[1:8]))

if (any(!is.na(control_qc$excluded_well))) {
  message("Control well(s) excluded as outliers: ",
          paste(na.omit(control_qc$excluded_well), collapse = ", "))
}
if (any(control_qc$cv_qc == "FLAG")) {
  warning("Control CV above ", control_cv_limit, "% for: ",
          paste(control_qc$type[control_qc$cv_qc == "FLAG"], collapse = ", "),
          " - check the plate before using these results.")
}

no_haem_OD <- control_qc$mean_OD[control_qc$type == "No haemolysis"]
max_haem_OD <- control_qc$mean_OD[control_qc$type == "Max haemolysis"]

if (max_haem_OD <= no_haem_OD) {
  stop("Max haemolysis OD is not higher than no haemolysis OD - check the control wells.")
}

# --------------------------------------------
# 6. Convert to % haemolysis and % inhibition
# --------------------------------------------

# 0% haemolysis = no haemolysis controls, 100% = max haemolysis controls
to_pct_haemolysis <- function(OD) {
  pmax(pmin(100 * (OD - no_haem_OD) / (max_haem_OD - no_haem_OD), 100), 0)
}

sample_wells <- sample_wells %>%
  mutate(
    pct_haemolysis = to_pct_haemolysis(OD540),
    pct_inhibition = 100 - pct_haemolysis
  )

plate_pct <- plate_long %>%
  mutate(
    pct_haemolysis = to_pct_haemolysis(OD540),
    excluded = well %in% control_qc$excluded_well,
    label = paste0(sprintf("%.0f", pct_haemolysis), if_else(excluded, "\nexcluded", ""))
  )

# ----------------------------------------
# 7. Fit inhibition curves (4PL) and IC50s
# ----------------------------------------

# 4PL with the bottom fixed at 0% and the top at 100% inhibition, so the
# IC50 is the dilution giving 50% inhibition. The best fit is found from
# many starting values (as in the MSD scripts), then passed to drc to
# calculate a 95% confidence interval for the IC50.

inhibition_4pl <- function(x, Slope, IC50) {
  100 / (1 + exp(Slope * (log(x) - log(IC50))))
}

fit_4pl <- function(data,
                    x_col = "dilution",
                    y_col = "pct_inhibition") {

  x <- data[[x_col]]
  y <- data[[y_col]]

  # Unweighted least squares
  objective <- function(par) {
    pred <- inhibition_4pl(x, Slope = par[1], IC50 = exp(par[2]))
    if (any(!is.finite(pred))) {
      return(1e100)
    }
    sum((y - pred)^2)
  }
  # Multiple plausible starting values
  slope_starts <- c(-4, -2, -1, -0.5, 0.5, 1, 2, 4)
  ic50_starts <- exp(seq(log(min(x) / 10), log(max(x) * 10), length.out = 8))
  start_grid <- expand.grid(
    Slope = slope_starts,
    IC50 = ic50_starts)
  fits <- vector("list", nrow(start_grid))
  for (i in seq_len(nrow(start_grid))) {
    s <- start_grid[i, ]
    fits[[i]] <- tryCatch(
      optim(
        par = c(Slope = s$Slope, logIC50 = log(s$IC50)),
        fn = objective,
        method = "Nelder-Mead",
        control = list(maxit = 20000, reltol = 1e-12)
      ),
      error = function(e) NULL
    )
  }

  # Retain successful fits
  successful <- fits[
    vapply(fits, function(z) !is.null(z) && is.finite(z$value), logical(1))
  ]
  if (length(successful) == 0) {
    return(NULL)
  }

  # Best fit
  best_fit <- successful[[which.min(vapply(successful, function(z) z$value, numeric(1)))]]
  parameters <- c(
    Slope = unname(best_fit$par["Slope"]),
    IC50 = unname(exp(best_fit$par["logIC50"]))
  )
  list(
    parameters = parameters,
    SS = best_fit$value,
    predict = function(new_x) {
      inhibition_4pl(new_x, Slope = parameters["Slope"], IC50 = parameters["IC50"])
    }
  )
}

# 95% CI for the IC50 using drc, started from the best fit above
ic50_ci <- function(data, fit) {
  drc_fit <- suppressWarnings(try(
    drm(
      pct_inhibition ~ dilution,
      data = data,
      fct = LL.4(names = c("Slope", "Lower", "Upper", "IC50"), fixed = c(NA, 0, 100, NA)),
      start = unname(fit$parameters)
    ),
    silent = TRUE
  ))
  # only use the drc result if it agrees with the best fit
  if (inherits(drc_fit, "try-error") ||
      sum(residuals(drc_fit)^2) > fit$SS * 1.001 + 1e-6) {
    return(c(Lower = NA_real_, Upper = NA_real_))
  }
  ed <- suppressWarnings(try(ED(drc_fit, 50, interval = "delta", display = FALSE), silent = TRUE))
  if (inherits(ed, "try-error")) {
    return(c(Lower = NA_real_, Upper = NA_real_))
  }
  ci <- c(Lower = unname(ed[1, "Lower"]), Upper = unname(ed[1, "Upper"]))
  ci[!is.finite(ci) | ci <= 0] <- NA_real_ # CI must be > 0
  ci
}

curve_fits <- sample_wells %>%
  group_by(col, sample_name, type, start_dilution) %>%
  group_nest() %>%
  mutate(fit = lapply(data, fit_4pl))

ic50_results <- curve_fits %>%
  rowwise() %>%
  mutate(
    final_dilution = max(data$dilution),
    min_inhibition = min(data$pct_inhibition),
    max_inhibition = max(data$pct_inhibition),
    Slope = if (is.null(fit)) NA_real_ else unname(fit$parameters["Slope"]),
    calculated_ic50 = if (is.null(fit)) NA_real_ else unname(fit$parameters["IC50"]),
    ci = list(if (is.null(fit)) c(Lower = NA_real_, Upper = NA_real_) else ic50_ci(data, fit)),
    ic50_lower_95CI = ci[["Lower"]],
    ic50_upper_95CI = ci[["Upper"]]
  ) %>%
  ungroup() %>%
  mutate(
    # Determine what happened in the dilution series
    ic50_status = case_when(
      is.na(calculated_ic50) ~
        "No result",
      min_inhibition > 50 ~
        "High activity - retest", # all wells > 50% inhibition; IC50 > final dilution
      max_inhibition < 50 ~
        "Insufficient activity - retest", # all wells < 50% inhibition; IC50 < starting dilution
      min_inhibition > dynamic_range[1] | max_inhibition < dynamic_range[2] ~
        "Partial curve - check", # crosses 50% but does not span 25-75% inhibition
      TRUE ~
        "Interpolated"
    ),
    # out of range samples are retested, so no IC50 is assigned
    ic50_dilution = if_else(ic50_status == "Interpolated", calculated_ic50, NA_real_)
  ) %>%
  dplyr::select(col, sample_name, type, start_dilution, final_dilution,
                min_inhibition, max_inhibition, Slope, calculated_ic50,
                ic50_lower_95CI, ic50_upper_95CI, ic50_status, ic50_dilution)

# --------------------------------------
# 8. Plot plate and inhibition curves
# --------------------------------------

# Heatmap of % haemolysis for a sense check of the plate
column_labels <- tibble(col = 1:12) %>%
  left_join(sample_map %>% dplyr::select(col, sample_name), by = "col") %>%
  mutate(label = case_when(col == control_col ~ "12\nControls",
                           is.na(sample_name) ~ as.character(col),
                           TRUE ~ paste0(col, "\n", sample_name)))

plate_heatmap <- ggplot(
  plate_pct,
  aes(x = factor(col, levels = 1:12, labels = column_labels$label),
      y = factor(row, levels = rev(LETTERS[1:8])),
      fill = pct_haemolysis)) +
  geom_tile(colour = "grey85", linewidth = 0.3) +
  geom_tile(data = filter(plate_pct, excluded), colour = "black", linewidth = 1, fill = NA) +
  geom_text(aes(label = label), size = 3) +
  scale_fill_gradient(low = "white", high = "red", limits = c(0, 100)) +
  scale_x_discrete(position = "top") +
  labs(
    title = paste0(tools::file_path_sans_ext(basename(plate_file)), " - % haemolysis"),
    x = NULL,
    y = NULL,
    fill = "% haemolysis"
  ) +
  theme_bw(base_size = 11)

plate_heatmap

# Fitted curves
curve_data <- curve_fits %>%
  filter(!vapply(fit, is.null, logical(1))) %>%
  rowwise() %>%
  reframe(
    sample_name = sample_name,
    dilution = exp(seq(log(min(data$dilution)), log(max(data$dilution)), length.out = 200)),
    pct_inhibition = fit$predict(dilution)
  )

curve_labels <- ic50_results %>%
  mutate(label = if_else(
    is.na(ic50_dilution),
    ic50_status,
    paste0("IC50 = ", round(ic50_dilution))
  ))

sample_order <- sample_map$sample_name

inhibition_curves <- ggplot(
  sample_wells %>% mutate(sample_name = factor(sample_name, levels = sample_order)),
  aes(x = dilution, y = pct_inhibition)) +
  geom_hline(yintercept = 50, linetype = "dashed", alpha = 0.5) +
  geom_line(
    data = curve_data %>% mutate(sample_name = factor(sample_name, levels = sample_order)),
    colour = "#0072B2", linewidth = 1) +
  geom_point(size = 2) +
  geom_text(
    data = curve_labels %>% mutate(sample_name = factor(sample_name, levels = sample_order)),
    aes(label = label), x = -Inf, y = 8, hjust = -0.05, size = 3, inherit.aes = FALSE) +
  facet_wrap(~ sample_name) +
  scale_x_log10() +
  coord_cartesian(ylim = c(0, 100)) +
  labs(
    title = "% inhibition curves (4PL fit)",
    x = "Reciprocal dilution",
    y = "% inhibition of haemolysis"
  ) +
  theme_bw(base_size = 11)

inhibition_curves

# All curves on the same plot
all_curves <- ggplot(
  sample_wells %>% mutate(sample_name = factor(sample_name, levels = sample_order)),
  aes(x = dilution, y = pct_inhibition, colour = sample_name)) +
  geom_hline(yintercept = 50, linetype = "dashed", alpha = 0.5) +
  geom_line(
    data = curve_data %>% mutate(sample_name = factor(sample_name, levels = sample_order)),
    linewidth = 1) +
  geom_point(size = 2) +
  scale_x_log10() +
  coord_cartesian(ylim = c(0, 100)) +
  labs(
    title = "% inhibition curves (4PL fit)",
    x = "Reciprocal dilution",
    y = "% inhibition of haemolysis",
    colour = "Sample"
  ) +
  theme_bw(base_size = 11)

all_curves

# ---------------------------------
# 9. Report final calculated IC50s
# ---------------------------------

ic50_summary <- ic50_results %>%
  transmute(
    sample_name,
    type,
    ic50 = round(ic50_dilution, 1),
    ic50_95CI = if_else(
      !is.na(ic50_dilution) & !is.na(ic50_lower_95CI) & !is.na(ic50_upper_95CI),
      paste0(round(ic50_lower_95CI, 1), "-", round(ic50_upper_95CI, 1)),
      NA_character_),
    ic50_status
  )

ic50_summary

# -------------------------------------------
# 10. Generate an assay / results output file
# -------------------------------------------

# Create output directory for plots
if (!dir.exists(plot_dir)) {
  dir.create(plot_dir)
}

# Save plots as PNG files
ggsave(file.path(plot_dir, "01_plate_heatmap.png"), plate_heatmap,
       width = 10, height = 5, dpi = 300)
ggsave(file.path(plot_dir, "02_inhibition_curves.png"), inhibition_curves,
       width = 10, height = 8, dpi = 300)
ggsave(file.path(plot_dir, "03_all_curves.png"), all_curves,
       width = 8, height = 6, dpi = 300)

# Create Excel workbook
wb <- createWorkbook()

# Add assay parameters
assay_parameters <- tibble(
  parameter = c(
    "Script version",
    "Plate file",
    "Dilution factor",
    "Number of dilution points",
    "Control CV limit (%)",
    "Exclude control outliers",
    "Excluded control wells",
    "Dynamic range (% inhibition)",
    "No haemolysis mean OD540",
    "Max haemolysis mean OD540",
    "Analysis date",
    "R version"
  ),
  value = c(
    script_version,
    plate_file,
    dilution_factor,
    n_points,
    control_cv_limit,
    exclude_control_outliers,
    if (all(is.na(control_qc$excluded_well))) "None" else paste(na.omit(control_qc$excluded_well), collapse = ", "),
    paste(dynamic_range, collapse = "-"),
    no_haem_OD,
    max_haem_OD,
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    R.version.string
  )
)

# Write data sheets
addWorksheet(wb, "Assay parameters")
writeData(wb, "Assay parameters", assay_parameters)

addWorksheet(wb, "Plate")
writeData(wb, "Plate", plate, rowNames = TRUE)

addWorksheet(wb, "Sample map")
writeData(wb, "Sample map", sample_map)

addWorksheet(wb, "Plate plan")
writeData(wb, "Plate plan", plate_plan)

addWorksheet(wb, "Control QC")
writeData(wb, "Control QC", control_qc)

addWorksheet(wb, "Control wells")
writeData(wb, "Control wells", control_wells)

addWorksheet(wb, "Sample results")
writeData(wb, "Sample results", sample_wells)

addWorksheet(wb, "IC50 results")
writeData(wb, "IC50 results", ic50_results)

addWorksheet(wb, "IC50 summary")
writeData(wb, "IC50 summary", ic50_summary)

# Add plots to workbook
addWorksheet(wb, "Plots")
insertImage(wb, "Plots", file.path(plot_dir, "01_plate_heatmap.png"),
            startRow = 1, startCol = 1, width = 10, height = 5)
insertImage(wb, "Plots", file.path(plot_dir, "02_inhibition_curves.png"),
            startRow = 28, startCol = 1, width = 10, height = 8)
insertImage(wb, "Plots", file.path(plot_dir, "03_all_curves.png"),
            startRow = 1, startCol = 17, width = 8, height = 6)

# Basic formatting
for (sheet in names(wb)) {
  setColWidths(wb, sheet, cols = 1:20, widths = "auto")
  freezePane(wb, sheet, firstRow = TRUE)
}

# Save workbook
saveWorkbook(wb, output_file, overwrite = TRUE)

cat(
  "\nAnalysis complete.\n",
  "Results saved to: ",
  output_file,
  "\nPlots saved to: ",
  plot_dir,
  "\n"
)
