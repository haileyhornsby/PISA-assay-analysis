# This script is designed to analyse the MSD plate results of the
# PISA IL-8 SpyCEP cleavage assay.
# Master copy: https://github.com/haileyhornsby/PISA-assay-analysis

script_version <- "1.0"

# MSD export -> calibration -> interpolation -> IC50

# Necessary input files
# a .txt MSD plate reader output file in "_each spot as plate" format
# a .csv sample map with the SAME NAME as the .txt file, saved in the same folder,
#   with the headers sample_number, sample_name, start_dilution (one row per sample, 1-16, following SOP plate plan)

# Plate layout
# Columns 1-8: samples 1-8 in rows A-D and samples 9-16 in rows E-H (3-fold dilutions down the column)
# Columns 9-10: Max IL-8 (A9, A10, B9, B10) and Min IL-8 (C9, C10, D9, D10) controls,
#   IVIG in duplicate in rows E-H
# Columns 11-12: IL-8 calibrators 1-7 and blank (row H) in duplicate


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

# Sample dilution series
dilution_factor <- 3 # sample and IVIG dilution series are 3-fold steps
n_sample_points <- 4 # each sample dilution series is 4 wells long
# starting dilution for each sample is found in the sample name .csv

# IVIG control
ivig_start_dilution <- 12.5 # IVIG dilution series starts at 1:12.5
n_ivig_points <- 4 # IVIG series is 4 wells long

# IL-8 calibration concentrations (pg/mL)
# Calibrators 1-7 are the standard curve, 8 is the assay blank
cal_concentrations <- 583 * 4^-(0:6) # adjust starting conc of the curve based on COA information, 4-fold steps

# Sample conversion
sample_dilution_correction <- 50 # a 50x correction factor is applied due to dilution for the MSD assay
pg_to_ng <- 1 / 1000

# ------------------------------
# 3. Read in the MSD plate data
# ------------------------------

x <- readLines(
  msd_file,
  warn = FALSE
)

# Find the plate data section
data_start <- grep(
  "^=+Data",
  x
)

if (length(data_start) == 0) {
  stop("Could not find the MSD data section.")
}

# The first line after the Data marker contains metadata.
# The following 8 lines contain the 8 rows of the 96-well plate.
data_lines <- x[
  (data_start[1] + 2):
    (data_start[1] + 9)
]

# Process data into an 8 x 12 data frame with numeric values
plate <- lapply(
  data_lines,
  function(z) {
    values <- strsplit(
      trimws(z),
      "\\s+"
    )[[1]]
    values <- values[
      values != ""
    ]
    # Check that each row contains 12 wells
    if (length(values) != 12) {
      
      stop(
        "Expected 12 values in plate row, but found ",
        length(values),
        ": ",
        z
      )
    }
    as.numeric(values)
  }
)

plate <- as.data.frame(
  do.call(
    rbind,
    plate
  )
)

# Add plate coordinates
rownames(plate) <- LETTERS[1:8]
colnames(plate) <- as.character(1:12)

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
    signal = mapply(
      function(r, c) plate[r, as.character(c)],
      row, col
    )
  ) %>%
  dplyr::select(well, row, col, signal)

# ------------------------------------
# 4. Read sample map and annotate data
# ------------------------------------

sample_map <- read_csv(
  sample_map_file,
  show_col_types = FALSE
) %>%
  mutate(
    sample_number = as.integer(sample_number),
    sample_name = as.character(sample_name),
    start_dilution = as.numeric(start_dilution)
  ) %>%
  arrange(sample_number)

sample_annotation <- lapply(1:16, function(i) {
  if (i <= 8) {
    rows <- LETTERS[1:4]
    col <- i
  } else {
    rows <- LETTERS[5:8]
    col <- i - 8
  }
  start <- sample_map$start_dilution[
    sample_map$sample_number == i
  ]
  tibble(
    sample_number = i,
    sample_name = sample_map$sample_name[
      sample_map$sample_number == i
    ],
    start_dilution = start,
    well = paste0(rows, col),
    dilution = start * dilution_factor^(0:(n_sample_points - 1))
  )
}) %>%
  bind_rows()

# Samples
sample_wells <- sample_annotation %>%
  left_join(plate_long, by = "well") %>%
  mutate(type = "Sample")

#Controls
control_wells <- tibble(
  well = c("A9", "A10", "B9", "B10", "C9", "C10", "D9", "D10"),
  type = rep(c("Max IL-8", "Min IL-8"), each = 4)
) %>%
  left_join(plate_long, by = "well")

# Calibration curve
cal_wells <- expand.grid(
  row = LETTERS[1:8],
  col = 11:12,
  stringsAsFactors = FALSE
) %>%
  mutate(
    well = paste0(row, col),
    calibrator = match(row, LETTERS[1:8]),
    concentration_pg_ml = ifelse(
      calibrator == 8,
      0,
      cal_concentrations[calibrator]
    ),
    replicate = ifelse(col == 11, "Cal_1", "Cal_2"),
    type = ifelse(
      calibrator == 8,
      "Calibration blank",
      "IL-8 calibrator"
    )
  ) %>%
  left_join(plate_long, by = "well")

# IVIG
ivig_wells <- expand.grid(
  row = LETTERS[5:8],
  col = 9:10,
  stringsAsFactors = FALSE
) %>%
  mutate(
    well = paste0(row, col),
    dilution = ivig_start_dilution * dilution_factor^(match(row, LETTERS[5:8]) - 1),
    sample_number = 17L,
    sample_name = "IVIG",
    start_dilution = ivig_start_dilution,
    replicate = ifelse(col == 9, "IVIG_1", "IVIG_2"),
    type = "IVIG"
  ) %>%
  left_join(plate_long, by = "well")

ivig_wells_mean <- ivig_wells %>%
  group_by(sample_number, sample_name, start_dilution, dilution) %>%
  summarise(signal = mean(signal, na.rm = TRUE), type = "IVIG", .groups = "drop")

# generate a plate plan
plate_plan_long <- bind_rows(
  
  # Samples
  sample_wells %>%
    transmute(
      well,
      label = paste0(
        sample_name,
        "\n1:",
        dilution
      )
    ),
  
  # Controls
  control_wells %>%
    transmute(
      well,
      label = type
    ),
  
  # IVIG
  ivig_wells %>%
    transmute(
      well,
      label = paste0(
        "IVIG",
        "\n1:",
        dilution
      )
    ),
  
  # Calibration standards
  cal_wells %>%
    transmute(
      well,
      label = if_else(
        concentration_pg_ml == 0,
        "Cal blank",
        paste0(
          "Cal ",
          calibrator,
          "\n",
          concentration_pg_ml,
          " pg/mL"
        )
      )
    )
)

# Convert to 8 x 12 plate layout
plate_plan <- plate_plan_long %>%
  mutate(
    row = substr(well, 1, 1),
    col = as.integer(
      sub("^[A-H]", "", well)
    )
  ) %>%
  dplyr::select(row, col, label) %>%
  tidyr::pivot_wider(
    names_from = col,
    values_from = label
  ) %>%
  arrange(
    match(row, LETTERS[1:8])
  )

# ----------------------------
# 5. Plate QC checks
# ----------------------------

# Calibration curve
calibration_qc <- cal_wells %>%
  group_by(
    calibrator,
    concentration_pg_ml
  ) %>%
  summarise(
    mean_signal = mean(signal, na.rm = TRUE),
    cv_percent = round(
      100 * sd(signal, na.rm = TRUE) / mean_signal,
      2
    ),
    cv_qc = if_else(cv_percent <= 5, "PASS", "FLAG"), # flag if duplicate CV > 5%
    .groups = "drop"
  )

calibration_qc

# Controls
control_qc <- control_wells %>%
  group_by(type) %>%
  summarise(
    mean_signal = mean(signal, na.rm = TRUE),
    cv_percent = round(
      100 * sd(signal, na.rm = TRUE) / mean_signal,
      2
    ),
    cv_qc = if_else(
      cv_percent <= 5,
      "PASS",
      "FLAG"
    ),
    .groups = "drop"
  )

control_qc

# IVIG 
ivig_qc <- ivig_wells %>%
  group_by(
    dilution
  ) %>%
  summarise(
    mean_signal = mean(signal, na.rm = TRUE),
    cv_percent = round(
      100 * sd(signal, na.rm = TRUE) / mean_signal,
      2
    ),
    cv_qc = if_else(
      cv_percent <= 5, # duplicates are flagged if > 5% CV
      "PASS",
      "FLAG"
    ),
    .groups = "drop"
  )

ivig_qc

# ----------------------------
# Optional - Blank-correction
# ----------------------------

#calibration_blank <- mean(
#  cal_wells$signal[cal_wells$calibrator == 8],
#  na.rm = TRUE
#)

#calibration_qc_corrected <- calibration_qc %>%
#  filter(calibrator <= 7) # %>%
#  mutate(
#    mean_signal = mean_signal - calibration_blank
#  )

# ----------------------------
# 6. Fit calibration curve
# ----------------------------

# Prepare calibration data for 4PL fitting
calibration_data <- calibration_qc %>%
  filter(concentration_pg_ml > 0)

fit_4pl <- function(data,
                    x_col = "concentration_pg_ml",
                    y_col = "mean_signal") {
  
  x <- data[[x_col]]
  y <- data[[y_col]]
  
  # 4PL, numerically stable
  stable_4pl <- function(x,
                         Bottom,
                         logTop,
                         logIC50,
                         logHillSlope) {
    
    Top <- exp(logTop)
    IC50 <- exp(logIC50)
    HillSlope <- exp(logHillSlope)
    z <- HillSlope * (log(IC50) - log(x))
    Bottom +
      (Top - Bottom) / (1 + exp(z))
  }
  
  # Relative weighting: 1/Y^2
  objective <- function(par) {
    
    pred <- stable_4pl(
      x = x,
      Bottom = par[1],
      logTop = par[2],
      logIC50 = par[3],
      logHillSlope = par[4]
    )
    if (
      any(!is.finite(pred)) ||
      any(pred <= 0)
    ) {
      return(1e100)
    }
    sum(
      ((y - pred) / y)^2
    )
  }
  # Multiple plausible starting values
  bottom_starts <- c(
    min(y) * 0.5,
    min(y) * 0.9,
    min(y))
  top_starts <- max(y) * c(2, 10, 100, 1e3, 1e5, 1e7)
  ic50_starts <- max(x) * c(1, 10, 100, 1e3, 1e5, 1e7)
  slope_starts <- c(0.5, 0.75, 1, 1.25, 2)
  start_grid <- expand.grid(
    Bottom = bottom_starts,
    Top = top_starts,
    IC50 = ic50_starts,
    HillSlope = slope_starts)
  fits <- vector(
    "list",
    nrow(start_grid))
  for (i in seq_len(nrow(start_grid))) {
    s <- start_grid[i, ]
    fit <- tryCatch(
      optim(
        par = c(
          Bottom = s$Bottom,
          logTop = log(s$Top),
          logIC50 = log(s$IC50),
          logHillSlope = log(s$HillSlope)
        ),
        fn = objective,
        method = "Nelder-Mead",
        control = list(
          maxit = 20000,
          reltol = 1e-10
        )
      ),
      error = function(e) NULL
    )
    fits[[i]] <- fit
  }
  
  # Retain successful fits
  successful <- fits[
    vapply(
      fits,
      function(z) {
        !is.null(z) &&
          is.finite(z$value)
      },
      logical(1)
    )
  ]
  
  if (length(successful) == 0) {
    stop("No 4PL fits converged.")
  }
  
  # Best weighted fit
  best_fit <- successful[[
    which.min(
      vapply(
        successful,
        function(z) z$value,
        numeric(1)
      )
    )
  ]]
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
      
      stable_4pl(
        x = new_x,
        Bottom = best_fit$par["Bottom"],
        logTop = best_fit$par["logTop"],
        logIC50 = best_fit$par["logIC50"],
        logHillSlope = best_fit$par["logHillSlope"]
      )
    }
  )
}

IL8_fit <- fit_4pl(calibration_data)

curve_data <- tibble(
  concentration_pg_ml = 10^seq(
    log10(min(calibration_data$concentration_pg_ml[calibration_data$concentration_pg_ml > 0])),
    log10(max(calibration_data$concentration_pg_ml)),
    length.out = 500
  )
) %>%
  mutate(
    OD_fit = IL8_fit$predict(concentration_pg_ml)
  )

calibration_curve <- ggplot() +
  geom_point(
    data = calibration_data,
    aes(
      x = concentration_pg_ml,
      y = mean_signal
    ),
    size = 3
  ) +
  geom_line(
    data = curve_data,
    aes(
      x = concentration_pg_ml,
      y = OD_fit
    ),
    linewidth = 1
  ) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "IL-8 standard curve",
    x = "Concentration (pg/mL)",
    y = "MSD signal"
  ) +
  theme_classic()

calibration_curve

# -----------------------------------------------------------
# 7. Fit the inverse of the 4PL function and set assay limits
# -----------------------------------------------------------

inverse_IL8_fit <- function(signal, fit) {
  
  bottom <- fit$parameters["Bottom"]
  top <- fit$parameters["Top"]
  ic50 <- fit$parameters["IC50"]
  hill_slope <- fit$parameters["HillSlope"]
  
  log_concentration <- log(ic50) +
    (
      log(signal - bottom) -
        log(top - signal)
    ) / hill_slope
  
  concentration <- exp(log_concentration)
  
  concentration[
    !is.finite(concentration) |
      signal <= bottom |
      signal >= top
  ] <- NA_real_
  
  concentration
}

calibration_check <- calibration_data %>%
  mutate(
    predicted_concentration = inverse_IL8_fit(
      mean_signal,
      IL8_fit
    )
  )

# Check that the predicted_concentration values are similar to the actual curve concentrations
calibration_check

# set upper and lower bounds of calibration curve signal
calibration_signal_min <- min(calibration_data$mean_signal, na.rm = TRUE)
calibration_signal_max <- max(calibration_data$mean_signal, na.rm = TRUE)

# convert IL-8 min and max values to ng/ml
assay_limits <- control_qc %>%
  mutate(il8_pg_ml = inverse_IL8_fit(mean_signal, IL8_fit),
         il8_ng_ml = il8_pg_ml * sample_dilution_correction * pg_to_ng) %>%
  dplyr::select(type, mean_signal, il8_pg_ml, il8_ng_ml)

# set the max and min IL-8 assay values
assay_signal_min <- assay_limits$mean_signal[assay_limits$type == "Min IL-8"]
assay_signal_max <- assay_limits$mean_signal[assay_limits$type == "Max IL-8"]
max_il8_ng_ml <- assay_limits$il8_ng_ml[assay_limits$type == "Max IL-8"]
min_il8_ng_ml <- assay_limits$il8_ng_ml[assay_limits$type == "Min IL-8"]

# calculate the amount of IL-8 present when inhibition is 50% (in ng/ml)
il8_50_ng_ml <- (
  max_il8_ng_ml - min_il8_ng_ml
) / 2 + min_il8_ng_ml

il8_50_ng_ml

# -------------------------------------
# 8. Interpolate sample IL-8 quantities
# -------------------------------------

sample_and_ivig_wells <- bind_rows(
  sample_wells %>%
    dplyr::select(sample_number, sample_name, start_dilution, well,
                  dilution, signal, type),
  ivig_wells_mean %>%
    dplyr::select(sample_number, sample_name, start_dilution,
                  dilution, signal, type)
)

sample_results <- sample_and_ivig_wells %>%
  mutate(calibration_status = case_when(signal < calibration_signal_min ~ "BELOW_CALIBRATION_RANGE",
                                        signal > calibration_signal_max ~ "ABOVE_CALIBRATION_RANGE",
                                        TRUE                            ~ "WITHIN_CALIBRATION_RANGE"),
         # Convert signal to IL-8 concentration whenever it is within the calibration range
         il8_pg_ml = if_else(calibration_status == "WITHIN_CALIBRATION_RANGE",
                             inverse_IL8_fit(signal, IL8_fit),
                             NA_real_),
         il8_ng_ml =
           il8_pg_ml *
           sample_dilution_correction *
           pg_to_ng,
         # Now assess whether the concentration is
         # within the actual assay response limits
         assay_status = case_when(
           calibration_status != "WITHIN_CALIBRATION_RANGE" ~
             "OUTSIDE_CALIBRATION_RANGE",
           il8_ng_ml < min_il8_ng_ml ~
             "BELOW_ASSAY_RANGE",
           il8_ng_ml > max_il8_ng_ml ~
             "ABOVE_ASSAY_RANGE",
           TRUE ~
             "WITHIN_ASSAY_RANGE"
         )
  )

# ----------------------------
# 9. Plot sample IL-8 quantities
# ----------------------------

il8_concentration_plot <- ggplot(
  sample_results, aes(x = dilution, y = il8_ng_ml, colour = sample_name)) +
  geom_point() +
  geom_line() +
  scale_x_log10() +
  geom_hline(
    yintercept = max_il8_ng_ml,
    linetype = "dashed"
  ) +
  geom_hline(
    yintercept = il8_50_ng_ml,
    linetype = "dashed"
  ) +
  geom_hline(
    yintercept = min_il8_ng_ml,
    linetype = "dashed"
  ) +
  labs(
    x = "Dilution",
    y = "IL-8 (ng/mL)",
    title = "IL-8 concentration across sample dilutions"
  ) +
  theme_classic()

il8_concentration_plot

# ----------------------------
# Calibration curve with
# assay limits and samples
# ----------------------------

calibration_plot_samples <- sample_results %>%
  filter(
    is.finite(il8_pg_ml),
    is.finite(signal)
  )

calibration_curve_samples <- ggplot() +
  geom_point(
    data = calibration_data,
    aes(
      x = concentration_pg_ml,
      y = mean_signal
    ),
    size = 3
  ) +
  
  # 4PL
  geom_line(
    data = curve_data,
    aes(
      x = concentration_pg_ml,
      y = OD_fit
    ),
    linewidth = 1
  ) +
  
  # Sample measurements
  geom_point(
    data = calibration_plot_samples,
    aes(
      x = il8_pg_ml,
      y = signal,
      colour = assay_status
    ),
    size = 2.5
  ) +
  
  # Min IL-8
  geom_hline(
    yintercept = assay_signal_min,
    linetype = "dotted"
  ) +
  
  # Max IL-8
  geom_hline(
    yintercept = assay_signal_max,
    linetype = "dotted"
  ) +
  
  scale_colour_manual(
    values = c(
      "WITHIN_ASSAY_RANGE" = "blue",
      "BELOW_ASSAY_RANGE" = "red",
      "ABOVE_ASSAY_RANGE" = "red"
    ),
    na.value = "red"
  ) +
  
  scale_x_log10() +
  scale_y_log10() +
  
  labs(
    title = "IL-8 calibration curve",
    subtitle = paste0(
      "Assay range: ",
      round(min_il8_ng_ml, 3),
      "–",
      round(max_il8_ng_ml, 2),
      " ng/mL"
    ),
    x = "IL-8 concentration (pg/mL)",
    y = "MSD signal",
    colour = "Sample status",
    shape = "Sample status"
  ) +
  theme_classic()

calibration_curve_samples

# -----------------------------------------------------
# 10. Linear regression and calculation of sample IC50s
# -----------------------------------------------------

sample_response <- sample_results %>%
  filter(
    is.finite(il8_ng_ml)
  ) %>%  mutate(
    log_dilution = log10(dilution)
  )

sample_models <- sample_response %>%
  group_by(
    sample_number,
    sample_name,
    dilution,
    log_dilution
  ) %>%
  summarise(
    il8_ng_ml = mean(il8_ng_ml, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(
    sample_number,
    sample_name
  ) %>%
  group_modify(~ {
    if (
      nrow(.x) < 2 ||
      n_distinct(.x$log_dilution) < 2
    ) {
      return(
        tibble(
          intercept = NA_real_,
          slope = NA_real_,
          r_squared = NA_real_
        )
      )
    }
    fit <- lm(
      il8_ng_ml ~ log_dilution,
      data = .x
    )
    tibble(
      intercept = coef(fit)[1],
      slope = coef(fit)[2],
      r_squared = summary(fit)$r.squared
    )
  }) %>%
  ungroup()

sample_range <- sample_response %>%
  group_by(
    sample_number,
    sample_name
  ) %>%
  summarise(
    start_dilution = first(start_dilution),
    observed_min_il8 = min(il8_ng_ml, na.rm = TRUE),
    observed_max_il8 = max(il8_ng_ml, na.rm = TRUE),
    min_dilution = min(dilution, na.rm = TRUE),
    max_dilution = max(dilution, na.rm = TRUE),
    .groups = "drop"
  )

# Calculate the serum dilution corresponding to the 50% inhibition value
ic50_results <- sample_models %>%
  left_join(
    sample_range,
    by = c("sample_number", "sample_name")
  ) %>%
  mutate(il8_50_ng_ml = il8_50_ng_ml,
    log10_ic50 = (
      il8_50_ng_ml - intercept
    ) / slope,
    
    calculated_ic50 = 10^log10_ic50,
    
    # Determine what happened in the dilution series
    ic50_status = case_when(
      is.na(calculated_ic50) ~
        "No result",
      observed_max_il8 < il8_50_ng_ml ~
        "Insufficient activity",
      observed_min_il8 > il8_50_ng_ml ~
        "High activity - retest",
      calculated_ic50 < min_dilution ~
        "High activity - retest",
      TRUE ~
        "Interpolated"
    ),
    #  assign IC50 = starting dilution / 2 where the sample never reaches the 50% IL-8 threshold
    ic50_dilution = case_when(
      ic50_status == "Insufficient activity" ~
        start_dilution / 2,
      ic50_status == "Interpolated" ~
        calculated_ic50,
      TRUE ~
        NA_real_
    )
  )

# --------------------------------------
# 11. Plot the sample/IVIG linear regression 
# --------------------------------------

sample_plot_data <- sample_response %>%
  left_join(
    sample_models,
    by = c("sample_number", "sample_name")
  ) %>%
  mutate(
    fitted_il8 = intercept +
      slope * log_dilution
  )

regression_plot <- ggplot(
  sample_plot_data,
  aes(
    x = dilution,
    y = il8_ng_ml,
    colour = sample_name
  )) +
  geom_point(size = 3) +
  geom_line(
    aes(
      y = fitted_il8
    ),
    linewidth = 1
  ) +
  geom_hline(
    yintercept = il8_50_ng_ml,
    linetype = "dotted",
    colour = "black"
  ) +
  scale_x_log10() +
  labs(
    title = "IL-8 linear regression plot",
    subtitle = paste0(
      "50% IL-8 response = ",
      round(il8_50_ng_ml, 3),
      " ng/mL"
    ),
    x = "Serum dilution",
    y = "IL-8 (ng/mL)",
    colour = "Sample"
  ) +
  theme_classic()

regression_plot

# ---------------------------------
# 12. Report final calculated IC50s
# ---------------------------------

ic50_summary <- ic50_results %>%
  group_by(sample_number, sample_name) %>%
  summarise(
    ic50 = first(ic50_dilution),
    ic50_status = first(ic50_status),
    .groups = "drop"
  )

ic50_summary

# -------------------------------------------
# 13. Generate an assay / results output file
# -------------------------------------------

# Create output directory for plots
if (!dir.exists(plot_dir)) {
  dir.create(plot_dir)
}

# Save plots as PNG files
ggsave(
  file.path(plot_dir, "01_calibration_curve.png"),
  calibration_curve,
  width = 8,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(plot_dir, "02_IL-8_concentrations.png"),
  il8_concentration_plot,
  width = 8,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(plot_dir, "03_calibration_curve_samples.png"),
  calibration_curve_samples,
  width = 8,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(plot_dir, "04_IC50_regression.png"),
  regression_plot,
  width = 8,
  height = 6,
  dpi = 300
)

# Create Excel workbook
wb <- createWorkbook()

# Add assay parameters

assay_parameters <- tibble(
  parameter = c(
    "Script version",
    "MSD file",
    "Sample map file",
    "Dilution factor",
    "Number of sample points",
    "IVIG starting dilution",
    "Number of IVIG points",
    "Sample dilution correction",
    "pg to ng conversion",
    "Calibration concentrations (pg/mL)",
    "Calibration signal minimum",
    "Calibration signal maximum",
    "Assay signal minimum",
    "Assay signal maximum",
    "Minimum IL-8 (ng/mL)",
    "Maximum IL-8 (ng/mL)",
    "50% IL-8 response (ng/mL)",
    "4PL Bottom",
    "4PL Top",
    "4PL IC50",
    "4PL Hill slope",
    "Analysis date",
    "R version"
  ),
  value = c(
    script_version,
    msd_file,
    sample_map_file,
    dilution_factor,
    n_sample_points,
    ivig_start_dilution,
    n_ivig_points,
    sample_dilution_correction,
    pg_to_ng,
    paste(cal_concentrations, collapse = ", "),
    calibration_signal_min,
    calibration_signal_max,
    assay_signal_min,
    assay_signal_max,
    min_il8_ng_ml,
    max_il8_ng_ml,
    il8_50_ng_ml,
    IL8_fit$parameters["Bottom"],
    IL8_fit$parameters["Top"],
    IL8_fit$parameters["IC50"],
    IL8_fit$parameters["HillSlope"],
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

addWorksheet(wb, "Calibration QC")
writeData(wb, "Calibration QC", calibration_qc)

addWorksheet(wb, "Control QC")
writeData(wb, "Control QC", control_qc)

addWorksheet(wb, "IVIG QC")
writeData(wb, "IVIG QC", ivig_qc)

addWorksheet(wb, "Calibration check")
writeData(wb, "Calibration check", calibration_check)

addWorksheet(wb, "Sample results")
writeData(wb, "Sample results", sample_results)

addWorksheet(wb, "IC50 results")
writeData(wb, "IC50 results", ic50_results)

addWorksheet(wb, "IC50 summary")
writeData(wb, "IC50 summary", ic50_summary)


# Add plots to workbook

addWorksheet(wb, "Plots")

insertImage(
  wb,
  "Plots",
  file.path(plot_dir, "01_calibration_curve.png"),
  startRow = 1,
  startCol = 1,
  width = 8,
  height = 6
)

insertImage(
  wb,
  "Plots",
  file.path(plot_dir, "02_IL-8_concentrations.png"),
  startRow = 1,
  startCol = 10,
  width = 8,
  height = 6
)

insertImage(
  wb,
  "Plots",
  file.path(plot_dir, "03_calibration_curve_samples.png"),
  startRow = 35,
  startCol = 1,
  width = 8,
  height = 6
)

insertImage(
  wb,
  "Plots",
  file.path(plot_dir, "04_IC50_regression.png"),
  startRow = 35,
  startCol = 10,
  width = 8,
  height = 6
)

# Basic formatting

for (sheet in names(wb)) {
  
  setColWidths(
    wb,
    sheet,
    cols = 1:20,
    widths = "auto"
  )
  
  freezePane(
    wb,
    sheet,
    firstRow = TRUE
  )
}

# Save workbook

saveWorkbook(
  wb,
  output_file,
  overwrite = TRUE
)

cat(
  "\nAnalysis complete.\n",
  "Results saved to: ",
  output_file,
  "\nPlots saved to: ",
  plot_dir,
  "\n"
)

