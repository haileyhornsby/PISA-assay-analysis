# This script is designed to analyse the MSD plate results of the
# PISA GAS 10-plex antibody assay.
# Master copy: https://github.com/haileyhornsby/PISA-assay-analysis

script_version <- "1.0"

# MSD export -> antigen-specific calibration -> interpolation -> AU/mL

# Necessary input files
# a .txt MSD plate reader output file in "_each spot as plate" format
# a .csv sample map with the SAME NAME as the .txt file, saved in the same folder,
#   with the headers sample_number, sample_name, start_dilution (one row per sample, 1-20)

# Plate layout
# Rows A-B: IVIG calibrators S1-S12 in duplicate (A and B in the same column; S12 is diluent only)
# Columns 1-2, rows C-E: MSD controls C1-C3 in duplicate (F1-F2 empty)
# Columns 3-12, rows C-F: samples 1-20 in duplicate (side-by-side wells), numbered down each pair of columns
# Rows G-H: mAb 1-12 in duplicate (G and H in the same column)


# ----------------------------
# 1. Packages
# ----------------------------

# Install any missing packages (only needed the first time), then load them
required_packages <- c("readr", "dplyr", "tidyr", "ggplot2", "openxlsx")
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
options(scipen = 999)

# ----------------------------
# 2. Files and assay settings
# ----------------------------

msd_file <- "C:/path/to/plate_each spot as plate.txt" # paste the full path to the MSD .txt file here (use / not \)
sample_map_file <- file.path(
  dirname(msd_file),
  paste0(tools::file_path_sans_ext(basename(msd_file)), ".csv"))
output_file <- file.path(
  dirname(msd_file),
  paste0(tools::file_path_sans_ext(basename(msd_file)), "_analysis.xlsx"))
plot_dir <- file.path(
  dirname(msd_file),
  paste0(tools::file_path_sans_ext(basename(msd_file)), "_plots"))

# Calibration curve
cal_dilution_factor <- 2.5 # calibrators are 2.5-fold steps from Cal-01
n_calibrators <- 11 # Cal-01 to Cal-11 make up the curve; Cal-12 is diluent only and is not used in the fit

# Antigen information for each MSD spot
# top_AU_ml is the arbitrary units assigned to Cal-01 for each antigen
spot_map <- tibble(
  spot = 1:10,
  antigen = c("GAC", "DNase B", "SLO", "OppA", "PulA",
              "SpnA", "Spy0843", "SpyAD", "ScpA", "SpyCEP"),
  top_AU_ml = c(3, 4, 20, 3, 4,
                7, 4, 6, 7, 4) # CHECK: SpnA is 4 AU/mL in the SOP table
)

# MSD control dilutions (reciprocal)
control_dilutions <- c("MSD - ctrl 1" = 50000, "MSD - ctrl 2" = 200000, "MSD - ctrl 3" = 800000)

# mAb control curve (pool of monoclonal antibodies, rows G-H)
mab_start_ug_ml <- 1 # mAb 1 contains 1 ug/mL of each individual mAb
mab_dilution_factor <- 4 # mAb 2-12 are 4-fold dilutions
mab_target_antigens <- c("GAC", "ScpA", "SpyAD", "SpyCEP") # antigens recognised by the mAb pool

# QC
n_samples_expected <- 20 # number of samples on a full plate
cal_cv_limit <- 15 # calibrator duplicates are flagged if CV > 15%
sample_cv_limit <- 15 # samples and controls with duplicate CV > 15% are not interpolated

# ------------------------------
# 3. Read in the MSD plate data
# ------------------------------

x <- readLines(msd_file, warn = FALSE)

# Find all MSD data sections (one per spot)
data_start <- grep("^=+Data", x)

if (length(data_start) != nrow(spot_map)) {
  stop("Expected ", nrow(spot_map), " MSD data sections, but found ", length(data_start), ".")
}

# Read each MSD spot as an 8 x 12 plate
plate_data <- lapply(data_start, function(start) {

  # The line after the Data marker contains metadata, including the SpotID
  spot <- as.integer(sub(".*SpotID\\s+([0-9]+).*", "\\1", x[start + 1]))
  if (is.na(spot)) {
    stop("Could not identify SpotID for data section beginning at line ", start)
  }

  # The following 8 lines contain the 8 rows of the 96-well plate
  plate <- lapply(x[(start + 2):(start + 9)], function(z) {
    values <- strsplit(trimws(z), "\\s+")[[1]]
    values <- values[values != ""]
    # Check that each row contains 12 wells
    if (length(values) != 12) {
      stop("Expected 12 values in plate row, but found ", length(values), ": ", z)
    }
    as.numeric(values)
  })
  plate <- as.data.frame(do.call(rbind, plate))
  rownames(plate) <- LETTERS[1:8]
  colnames(plate) <- as.character(1:12)

  # Convert this spot to tidy format
  expand.grid(row = LETTERS[1:8], col = 1:12,
              KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE) %>%
    mutate(
      well = paste0(row, col),
      spot = spot,
      signal = mapply(function(r, c) plate[r, as.character(c)], row, col)
    )
}) %>%
  bind_rows() %>%
  left_join(spot_map, by = "spot") %>%
  arrange(spot, row, col)

# Check that the complete 10-plex plate has been imported
if (nrow(plate_data) != 96 * nrow(spot_map)) {
  stop("Expected ", 96 * nrow(spot_map), " measurements (96 wells x ", nrow(spot_map),
       " spots), but found ", nrow(plate_data), ".")
}

# Check that plate data has been read in correctly
plate_data

# Wide copy of the raw signal for the output file (one row per well)
plate_wide <- plate_data %>%
  dplyr::select(well, row, col, antigen, signal) %>%
  pivot_wider(names_from = antigen, values_from = signal)

# ------------------------------------
# 4. Read sample map and annotate data
# ------------------------------------

sample_map <- read_csv(sample_map_file, show_col_types = FALSE) %>%
  mutate(
    sample_number = as.integer(sample_number),
    sample_name = as.character(sample_name),
    start_dilution = as.numeric(start_dilution)
  ) %>%
  arrange(sample_number)

# Check sample map
if (nrow(sample_map) != n_samples_expected) {
  warning("Expected ", n_samples_expected, " samples in sample map, but found ", nrow(sample_map), ".")
}
if (anyDuplicated(sample_map$sample_number)) {
  stop("Duplicate sample numbers found in sample map.")
}
if (anyNA(sample_map$start_dilution)) {
  stop("Missing start_dilution for sample number(s): ",
       paste(sample_map$sample_number[is.na(sample_map$start_dilution)], collapse = ", "))
}

sample_map

# Calibration wells: Cal-01 to Cal-12 in columns 1-12, rows A and B
cal_wells <- expand.grid(row = c("A", "B"), col = 1:12, stringsAsFactors = FALSE) %>%
  mutate(
    well = paste0(row, col),
    calibrator = col,
    replicate = if_else(row == "A", "Cal_1", "Cal_2"),
    type = if_else(calibrator > n_calibrators, "Calibration diluent", "Calibrator")
  )

# MSD controls
control_wells <- tibble(
  well = c("C1", "C2", "D1", "D2", "E1", "E2"),
  sample_name = rep(names(control_dilutions), each = 2),
  replicate = rep(c("Rep_1", "Rep_2"), 3),
  type = "Control"
) %>%
  mutate(start_dilution = unname(control_dilutions[sample_name]))

# mAb control curve: mAb 1-12 in columns 1-12, duplicates in rows G and H
mab_wells <- expand.grid(row = c("G", "H"), col = 1:12, stringsAsFactors = FALSE) %>%
  mutate(
    well = paste0(row, col),
    sample_number = col,
    sample_name = paste("mAb", col),
    mab_ug_ml = mab_start_ug_ml * mab_dilution_factor^-(col - 1),
    replicate = if_else(row == "G", "Rep_1", "Rep_2"),
    type = "mAb"
  ) %>%
  dplyr::select(well, sample_number, sample_name, mab_ug_ml, replicate, type)

# Sample wells: samples 1-20 run down rows C-F in each pair of columns (3-4, 5-6, ... 11-12)
sample_layout <- tibble(sample_number = 1:20) %>%
  mutate(
    row = c("C", "D", "E", "F")[(sample_number - 1) %% 4 + 1],
    first_col = 3 + 2 * ((sample_number - 1) %/% 4)
  ) %>%
  crossing(replicate_number = 1:2) %>%
  mutate(
    well = paste0(row, first_col + replicate_number - 1),
    replicate = paste0("Rep_", replicate_number),
    type = "Sample"
  ) %>%
  dplyr::select(well, sample_number, replicate, type) %>%
  inner_join(sample_map, by = "sample_number") # positions with no sample in the map are left out

# Add plate information to the MSD data
cal_data <- cal_wells %>%
  left_join(plate_data, by = "well") %>%
  mutate(concentration_AU_ml = if_else(
    type == "Calibration diluent", 0, top_AU_ml * cal_dilution_factor^-(calibrator - 1)))

sample_data <- bind_rows(
  sample_layout,
  control_wells,
  mab_wells
) %>%
  left_join(plate_data, by = "well")

# generate a plate plan
plate_plan <- bind_rows(
  cal_wells %>% transmute(well, label = sprintf("Cal-%02d", calibrator)),
  control_wells %>% transmute(well, label = sample_name),
  mab_wells %>% transmute(well, label = paste0(sample_name, "\n", signif(mab_ug_ml, 3), " ug/mL")),
  sample_layout %>% transmute(well, label = paste0(sample_number, ": ", sample_name, "\n1:", start_dilution))
) %>%
  mutate(
    row = substr(well, 1, 1),
    col = as.integer(sub("^[A-H]", "", well))
  ) %>%
  dplyr::select(row, col, label) %>%
  complete(row = LETTERS[1:8], col = 1:12) %>%
  arrange(col) %>%
  pivot_wider(names_from = col, values_from = label) %>%
  arrange(match(row, LETTERS[1:8]))

# ----------------------------
# 5. Calibration QC
# ----------------------------

# Mean signal and duplicate CV for each calibrator, separately for each antigen
calibration_qc <- cal_data %>%
  group_by(spot, antigen, top_AU_ml, calibrator, concentration_AU_ml) %>%
  summarise(
    mean_signal = mean(signal, na.rm = TRUE),
    cv_percent = round(100 * sd(signal, na.rm = TRUE) / mean_signal, 2),
    cv_qc = if_else(cv_percent <= cal_cv_limit, "PASS", "FLAG"), # flag if duplicate CV > limit
    .groups = "drop"
  )

calibration_qc

# ----------------------------
# 6. Fit calibration curves
# ----------------------------

# Prepare calibration data for 4PL fitting (Cal-12 diluent is not used)
calibration_data <- calibration_qc %>%
  filter(concentration_AU_ml > 0) %>%
  mutate(antigen = factor(antigen, levels = spot_map$antigen)) # keeps plots in spot order

fit_4pl <- function(data,
                    x_col = "concentration_AU_ml",
                    y_col = "mean_signal") {

  x <- data[[x_col]]
  y <- data[[y_col]]

  # 4PL, numerically stable
  stable_4pl <- function(x, Bottom, logTop, logIC50, logHillSlope) {
    Top <- exp(logTop)
    IC50 <- exp(logIC50)
    HillSlope <- exp(logHillSlope)
    z <- HillSlope * (log(IC50) - log(x))
    Bottom + (Top - Bottom) / (1 + exp(z))
  }

  # Relative weighting: 1/Y^2
  objective <- function(par) {
    pred <- stable_4pl(x = x, Bottom = par[1], logTop = par[2],
                       logIC50 = par[3], logHillSlope = par[4])
    if (any(!is.finite(pred)) || any(pred <= 0)) {
      return(1e100)
    }
    sum(((y - pred) / y)^2)
  }

  # Multiple plausible starting values
  bottom_starts <- c(min(y) * 0.5, min(y) * 0.9, min(y))
  top_starts <- max(y) * c(2, 10, 100, 1e3, 1e5, 1e7)
  ic50_starts <- max(x) * c(1, 10, 100, 1e3, 1e5, 1e7)
  slope_starts <- c(0.5, 0.75, 1, 1.25, 2)
  start_grid <- expand.grid(
    Bottom = bottom_starts,
    Top = top_starts,
    IC50 = ic50_starts,
    HillSlope = slope_starts)
  fits <- vector("list", nrow(start_grid))
  for (i in seq_len(nrow(start_grid))) {
    s <- start_grid[i, ]
    fits[[i]] <- tryCatch(
      optim(
        par = c(Bottom = s$Bottom, logTop = log(s$Top),
                logIC50 = log(s$IC50), logHillSlope = log(s$HillSlope)),
        fn = objective,
        method = "Nelder-Mead",
        control = list(maxit = 20000, reltol = 1e-10)
      ),
      error = function(e) NULL
    )
  }

  # Retain successful fits
  successful <- fits[
    vapply(fits, function(z) !is.null(z) && is.finite(z$value), logical(1))
  ]
  if (length(successful) == 0) {
    stop("No 4PL fits converged.")
  }

  # Best weighted fit
  best_fit <- successful[[which.min(vapply(successful, function(z) z$value, numeric(1)))]]
  parameters <- c(
    Bottom = unname(best_fit$par["Bottom"]),
    Top = unname(exp(best_fit$par["logTop"])),
    IC50 = unname(exp(best_fit$par["logIC50"])),
    HillSlope = unname(exp(best_fit$par["logHillSlope"]))
  )
  list(
    fit = best_fit,
    parameters = parameters,
    weighted_SS = best_fit$value,
    predict = function(new_x) {
      stable_4pl(x = new_x, Bottom = best_fit$par["Bottom"], logTop = best_fit$par["logTop"],
                 logIC50 = best_fit$par["logIC50"], logHillSlope = best_fit$par["logHillSlope"])
    }
  )
}

# Fit a separate curve for each antigen
calibration_fits <- calibration_data %>%
  group_by(spot, antigen) %>%
  group_nest() %>%
  mutate(fit = lapply(data, fit_4pl))

calibration_parameters <- calibration_fits %>%
  rowwise() %>%
  mutate(
    Bottom = fit$parameters["Bottom"],
    Top = fit$parameters["Top"],
    IC50 = fit$parameters["IC50"],
    HillSlope = fit$parameters["HillSlope"],
    weighted_SS = fit$weighted_SS
  ) %>%
  ungroup() %>%
  dplyr::select(spot, antigen, Bottom, Top, IC50, HillSlope, weighted_SS)

calibration_parameters

curve_data <- calibration_fits %>%
  rowwise() %>%
  reframe(
    spot = spot,
    antigen = antigen,
    concentration_AU_ml = 10^seq(log10(min(data$concentration_AU_ml)),
                                 log10(max(data$concentration_AU_ml)), length.out = 500),
    signal_fit = fit$predict(concentration_AU_ml)
  )

calibration_curve <- ggplot() +
  geom_point(data = calibration_data, aes(x = concentration_AU_ml, y = mean_signal), size = 2) +
  geom_line(data = curve_data, aes(x = concentration_AU_ml, y = signal_fit), linewidth = 0.8) +
  scale_x_log10() +
  scale_y_log10() +
  facet_wrap(~ antigen, scales = "free") +
  labs(
    title = "GAS 10-plex calibration curves",
    x = "Concentration (AU/mL)",
    y = "MSD signal"
  ) +
  theme_classic()

calibration_curve

# -----------------------------------------------------------
# 7. Fit the inverse of the 4PL function and set assay limits
# -----------------------------------------------------------

inverse_4pl <- function(signal, fit) {

  bottom <- fit$parameters["Bottom"]
  top <- fit$parameters["Top"]
  ic50 <- fit$parameters["IC50"]
  hill_slope <- fit$parameters["HillSlope"]

  log_concentration <- log(ic50) +
    (log(signal - bottom) - log(top - signal)) / hill_slope

  concentration <- unname(exp(log_concentration))
  concentration[!is.finite(concentration) | signal <= bottom | signal >= top] <- NA_real_
  concentration
}

calibration_check <- calibration_fits %>%
  rowwise() %>%
  reframe(
    spot = spot,
    antigen = antigen,
    calibrator = data$calibrator,
    concentration_AU_ml = data$concentration_AU_ml,
    mean_signal = data$mean_signal,
    predicted_AU_ml = inverse_4pl(data$mean_signal, fit),
    recovery_percent = round(100 * predicted_AU_ml / concentration_AU_ml, 1)
  )

# Check that the predicted_AU_ml values are similar to the actual curve concentrations
calibration_check %>%
  print(n = Inf)

# set upper and lower bounds of calibration curve signal for each antigen
calibration_ranges <- calibration_data %>%
  group_by(spot, antigen) %>%
  summarise(
    calibration_signal_min = min(mean_signal, na.rm = TRUE),
    calibration_signal_max = max(mean_signal, na.rm = TRUE),
    calibration_AU_min = min(concentration_AU_ml, na.rm = TRUE),
    calibration_AU_max = max(concentration_AU_ml, na.rm = TRUE),
    .groups = "drop"
  )

# -----------------------------------------------------------
# 8. Sample and control QC, and interpolation of AU/mL
# -----------------------------------------------------------

sample_results <- sample_data %>%
  group_by(type, sample_number, sample_name, start_dilution, mab_ug_ml, spot, antigen) %>%
  summarise(
    rep_1_signal = signal[replicate == "Rep_1"],
    rep_2_signal = signal[replicate == "Rep_2"],
    mean_signal = mean(signal, na.rm = TRUE),
    cv_percent = round(100 * sd(signal, na.rm = TRUE) / mean_signal, 2),
    .groups = "drop"
  ) %>%
  mutate(cv_qc = if_else(cv_percent <= sample_cv_limit, "PASS", "FLAG")) %>%
  left_join(calibration_fits %>% dplyr::select(spot, antigen, fit), by = c("spot", "antigen")) %>%
  left_join(calibration_ranges, by = c("spot", "antigen")) %>%
  mutate(
    calibration_status = case_when(
      mean_signal < calibration_signal_min ~ "Below calibration range",
      mean_signal > calibration_signal_max ~ "Above calibration range",
      TRUE ~ "Within calibration range"
    )
  ) %>%
  rowwise() %>%
  mutate(
    # Convert signal to AU/mL when the duplicates agree and the signal is within the calibration range
    interpolated_AU_ml = if (cv_qc == "PASS" && calibration_status == "Within calibration range") {
      inverse_4pl(mean_signal, fit)
    } else {
      NA_real_
    }
  ) %>%
  ungroup() %>%
  mutate(
    # Apply the sample dilution
    corrected_AU_ml = interpolated_AU_ml * start_dilution,
    result_status = case_when(
      cv_qc == "FLAG" ~ paste0("Duplicate CV > ", sample_cv_limit, "%"),
      calibration_status != "Within calibration range" ~ calibration_status,
      is.na(interpolated_AU_ml) ~ "Interpolation failed",
      TRUE ~ "Interpolated"
    )
  ) %>%
  dplyr::select(-fit) %>%
  arrange(type, sample_number, spot)

# mAb control curve
# interpolated_AU_ml is the AU/mL in the well (no dilution correction)
mab_results <- sample_results %>%
  filter(type == "mAb") %>%
  mutate(target_antigen = antigen %in% mab_target_antigens) %>%
  dplyr::select(sample_name, mab_ug_ml, antigen, target_antigen, rep_1_signal, rep_2_signal,
                mean_signal, cv_percent, cv_qc, calibration_status, interpolated_AU_ml, result_status)

mab_results %>%
  filter(target_antigen) %>%
  print(n = Inf)

# MSD controls
control_results <- sample_results %>%
  filter(type == "Control") %>%
  dplyr::select(sample_name, start_dilution, antigen, rep_1_signal, rep_2_signal, mean_signal,
                cv_percent, cv_qc, calibration_status, corrected_AU_ml, result_status)

control_results %>%
  print(n = Inf)

sample_results <- sample_results %>%
  filter(type == "Sample") %>%
  dplyr::select(-mab_ug_ml)

# ----------------------------------------
# 9. Plot calibration curves with samples
# ----------------------------------------

calibration_plot_samples <- sample_results %>%
  filter(is.finite(interpolated_AU_ml))

calibration_curve_samples <- ggplot() +
  geom_hline(data = calibration_ranges, aes(yintercept = calibration_signal_min), linetype = "dotted") +
  geom_hline(data = calibration_ranges, aes(yintercept = calibration_signal_max), linetype = "dotted") +
  geom_line(data = curve_data, aes(x = concentration_AU_ml, y = signal_fit), linewidth = 0.8) +
  geom_point(data = calibration_data, aes(x = concentration_AU_ml, y = mean_signal), size = 2) +
  geom_point(data = calibration_plot_samples,
             aes(x = interpolated_AU_ml, y = mean_signal), colour = "blue", size = 1.5, alpha = 0.7) +
  scale_x_log10() +
  scale_y_log10() +
  facet_wrap(~ antigen, scales = "free") +
  labs(
    title = "GAS 10-plex calibration curves with interpolated samples (blue)",
    subtitle = "Dotted lines show the calibration signal range",
    x = "Concentration (AU/mL)",
    y = "MSD signal"
  ) +
  theme_classic()

calibration_curve_samples

# Heatmap of final results for each sample and antigen
results_heatmap <- ggplot(
  sample_results %>%
    mutate(
      sample_label = factor(paste0(sample_number, ": ", sample_name),
                            levels = rev(unique(paste0(sample_number, ": ", sample_name)))),
      antigen = factor(antigen, levels = spot_map$antigen),
      label = case_when(
        result_status == "Interpolated" ~ format(signif(corrected_AU_ml, 3), big.mark = ",", trim = TRUE),
        grepl("CV", result_status) ~ "CV",
        result_status == "Below calibration range" ~ "<",
        result_status == "Above calibration range" ~ ">",
        TRUE ~ "NA"
      )
    ),
  aes(x = antigen, y = sample_label, fill = log10(corrected_AU_ml))) +
  geom_tile(colour = "grey85", linewidth = 0.3) +
  geom_text(aes(label = label), size = 2.5) +
  scale_fill_gradient(low = "white", high = "steelblue", na.value = "grey90") +
  scale_x_discrete(position = "top") +
  labs(
    title = "Sample results (AU/mL)",
    subtitle = "CV = duplicate CV above limit, < / > = below / above calibration range",
    x = NULL,
    y = NULL,
    fill = "log10 AU/mL"
  ) +
  theme_bw(base_size = 10)

results_heatmap

# mAb control curve on each spot (target antigens should respond, the others should stay at background)
mab_curve <- ggplot(
  mab_results %>%
    mutate(
      antigen = factor(antigen, levels = spot_map$antigen),
      target = if_else(target_antigen, "Target antigen", "Non-target antigen")
    ),
  aes(x = mab_ug_ml, y = mean_signal, colour = target)) +
  geom_hline(data = calibration_ranges %>% mutate(antigen = factor(antigen, levels = spot_map$antigen)),
             aes(yintercept = calibration_signal_min), linetype = "dotted") +
  geom_hline(data = calibration_ranges %>% mutate(antigen = factor(antigen, levels = spot_map$antigen)),
             aes(yintercept = calibration_signal_max), linetype = "dotted") +
  geom_line() +
  geom_point(size = 1.8) +
  scale_x_log10() +
  scale_y_log10() +
  scale_colour_manual(values = c("Target antigen" = "#D55E00", "Non-target antigen" = "grey50")) +
  facet_wrap(~ antigen) +
  labs(
    title = "mAb pool control curve",
    subtitle = "Dotted lines show the calibration signal range",
    x = "Concentration of each mAb (ug/mL)",
    y = "MSD signal",
    colour = NULL
  ) +
  theme_classic() +
  theme(legend.position = "top")

mab_curve

# ---------------------------------
# 10. Report final results
# ---------------------------------

# One row per sample, one column per antigen (AU/mL; blank if not interpolated)
results_summary <- sample_results %>%
  mutate(
    antigen = factor(antigen, levels = spot_map$antigen),
    result = if_else(result_status == "Interpolated", corrected_AU_ml, NA_real_)
  ) %>%
  dplyr::select(sample_number, sample_name, start_dilution, antigen, result) %>%
  pivot_wider(names_from = antigen, values_from = result)

# Matching table of result status for each sample and antigen
status_summary <- sample_results %>%
  mutate(antigen = factor(antigen, levels = spot_map$antigen)) %>%
  dplyr::select(sample_number, sample_name, antigen, result_status) %>%
  pivot_wider(names_from = antigen, values_from = result_status)

results_summary

sample_results %>%
  count(result_status)

# -------------------------------------------
# 11. Generate an assay / results output file
# -------------------------------------------

# Create output directory for plots
if (!dir.exists(plot_dir)) {
  dir.create(plot_dir)
}

# Save plots as PNG files
ggsave(file.path(plot_dir, "01_calibration_curves.png"), calibration_curve,
       width = 10, height = 7, dpi = 300)
ggsave(file.path(plot_dir, "02_calibration_curves_samples.png"), calibration_curve_samples,
       width = 10, height = 7, dpi = 300)
ggsave(file.path(plot_dir, "03_results_heatmap.png"), results_heatmap,
       width = 9, height = 7, dpi = 300)
ggsave(file.path(plot_dir, "04_mAb_curve.png"), mab_curve,
       width = 10, height = 7, dpi = 300)

# Create Excel workbook
wb <- createWorkbook()

# Add assay parameters
assay_parameters <- tibble(
  parameter = c(
    "Script version",
    "MSD file",
    "Sample map file",
    "Calibrator dilution factor",
    "Number of calibrators in curve",
    paste0("Cal-01 AU/mL - ", spot_map$antigen),
    paste0("Dilution - ", names(control_dilutions)),
    "mAb 1 concentration (ug/mL each mAb)",
    "mAb dilution factor",
    "mAb target antigens",
    "Calibrator CV limit (%)",
    "Sample CV limit (%)",
    "Analysis date",
    "R version"
  ),
  value = c(
    script_version,
    msd_file,
    sample_map_file,
    cal_dilution_factor,
    n_calibrators,
    spot_map$top_AU_ml,
    unname(control_dilutions),
    mab_start_ug_ml,
    mab_dilution_factor,
    paste(mab_target_antigens, collapse = ", "),
    cal_cv_limit,
    sample_cv_limit,
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    R.version.string
  )
)

# Write data sheets
addWorksheet(wb, "Assay parameters")
writeData(wb, "Assay parameters", assay_parameters)

addWorksheet(wb, "Plate")
writeData(wb, "Plate", plate_wide)

addWorksheet(wb, "Sample map")
writeData(wb, "Sample map", sample_map)

addWorksheet(wb, "Plate plan")
writeData(wb, "Plate plan", plate_plan)

addWorksheet(wb, "Calibration QC")
writeData(wb, "Calibration QC", calibration_qc)

addWorksheet(wb, "Calibration fits")
writeData(wb, "Calibration fits", calibration_parameters %>% left_join(calibration_ranges, by = c("spot", "antigen")))

addWorksheet(wb, "Calibration check")
writeData(wb, "Calibration check", calibration_check)

addWorksheet(wb, "Control results")
writeData(wb, "Control results", control_results)

addWorksheet(wb, "mAb results")
writeData(wb, "mAb results", mab_results)

addWorksheet(wb, "Sample results")
writeData(wb, "Sample results", sample_results)

addWorksheet(wb, "Results summary")
writeData(wb, "Results summary", results_summary)

addWorksheet(wb, "Status summary")
writeData(wb, "Status summary", status_summary)

# Add plots to workbook
addWorksheet(wb, "Plots")
insertImage(wb, "Plots", file.path(plot_dir, "01_calibration_curves.png"),
            startRow = 1, startCol = 1, width = 10, height = 7)
insertImage(wb, "Plots", file.path(plot_dir, "02_calibration_curves_samples.png"),
            startRow = 38, startCol = 1, width = 10, height = 7)
insertImage(wb, "Plots", file.path(plot_dir, "03_results_heatmap.png"),
            startRow = 1, startCol = 17, width = 9, height = 7)
insertImage(wb, "Plots", file.path(plot_dir, "04_mAb_curve.png"),
            startRow = 38, startCol = 17, width = 10, height = 7)

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
