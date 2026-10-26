# This script tracks the assay controls across plates for the PISA assays.
# Master copy: https://github.com/haileyhornsby/PISA-assay-analysis

script_version <- "1.0"

# Results files -> control values from every plate -> trends and summary statistics

# Necessary input
# a folder containing "_analysis.xlsx" results files made by the PISA assay scripts
# (subfolders are included). Each results file has a "Control summary" sheet.
# Results files from all three assays can be in the same folder: each assay is
# summarised separately.

# If the same plate has been analysed more than once, only the most recent
# analysis is used.

# Statistics are calculated on log10 values, because IC50s and concentrations vary
# by fold-changes. The trend limits use robust statistics (median and MAD), so a
# single unusual plate cannot widen the limits it is judged against. Limits are
# shown for information only: they are not acceptance criteria.


# ----------------------------
# 1. Packages
# ----------------------------

# Install any missing packages (only needed the first time), then load them
required_packages <- c("dplyr", "tidyr", "ggplot2", "openxlsx", "rstudioapi")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  message("Installing missing packages: ", paste(missing_packages, collapse = ", "))
  install.packages(missing_packages)
}

library(dplyr)
library(tidyr)
library(ggplot2)
library(openxlsx)
options(scipen = 999)

# Opens a window to choose a folder (in RStudio), or a standard folder dialog otherwise
choose_folder <- function(caption) {
  message(caption)
  path <- if (rstudioapi::isAvailable()) {
    rstudioapi::selectDirectory(caption = caption)
  } else if (.Platform$OS.type == "windows") {
    utils::choose.dir(caption = caption)
  } else {
    tcltk::tk_choose.dir(caption = caption)
  }
  if (is.null(path) || is.na(path) || !nzchar(path)) {
    stop("No folder was chosen. Run the script again and choose the results folder.", call. = FALSE)
  }
  normalizePath(path, winslash = "/")
}

# ----------------------------
# 2. Results folder
# ----------------------------

# When the script runs, a window opens: choose the folder containing the results files
results_folder <- choose_folder("Choose the folder containing the _analysis.xlsx results files")

# ----------------------------------------------
# Fixed information - do not change
# ----------------------------------------------

min_plates_for_limits <- 5 # limits are only shown once a control has values from at least 5 plates

# Output files are saved in the results folder, named with today's date
output_file <- file.path(results_folder, paste0("control_tracking_", Sys.Date(), ".xlsx"))
plot_dir <- file.path(results_folder, paste0("control_tracking_", Sys.Date(), "_plots"))

# ------------------------------------
# 3. Find and read the results files
# ------------------------------------

results_files <- list.files(results_folder, pattern = "_analysis\\.xlsx$",
                            recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
results_files <- results_files[!grepl("^~\\$", basename(results_files))] # skip Excel lock files

if (length(results_files) == 0) {
  stop("No _analysis.xlsx results files were found in ", results_folder, call. = FALSE)
}

# Read the Control summary sheet from each file (files made before this sheet
# existed, or that cannot be opened, are listed as skipped)
file_log <- tibble(file = results_files, status = NA_character_)
control_data <- vector("list", length(results_files))

for (i in seq_along(results_files)) {
  f <- results_files[i]
  sheets <- tryCatch(getSheetNames(f), error = function(e) NULL)
  if (is.null(sheets)) {
    file_log$status[i] <- "Skipped: could not be opened"
  } else if (!"Control summary" %in% sheets) {
    file_log$status[i] <- "Skipped: no Control summary sheet (analysed with an older script version)"
  } else {
    d <- read.xlsx(f, sheet = "Control summary")
    d[] <- lapply(d, function(z) if (is.factor(z)) as.character(z) else z)
    control_data[[i]] <- d %>% mutate(source_file = f, across(any_of(c("assay_date")), as.character))
    file_log$status[i] <- "Read"
  }
}

message(sum(file_log$status == "Read"), " of ", nrow(file_log), " results files read")

control_data <- bind_rows(control_data)

if (nrow(control_data) == 0) {
  stop("None of the results files contain a Control summary sheet. ",
       "Re-analyse the plates with the current assay scripts.", call. = FALSE)
}

# Tidy column types
to_date <- function(x) {
  num <- suppressWarnings(as.numeric(x))
  out <- as.Date(x, optional = TRUE)
  out[!is.na(num)] <- convertToDate(num[!is.na(num)]) # dates stored as Excel numbers
  out
}

control_data <- control_data %>%
  mutate(
    value = suppressWarnings(as.numeric(value)),
    cv_percent = suppressWarnings(as.numeric(if ("cv_percent" %in% names(.)) cv_percent else NA)),
    assay_date = to_date(assay_date),
    analysis_time = as.POSIXct(analysis_date, format = "%Y-%m-%d %H:%M:%S")
  )

# Keep only the most recent analysis of each plate
control_data <- control_data %>%
  group_by(assay, plate) %>%
  filter(analysis_time == max(analysis_time)) %>%
  ungroup() %>%
  distinct(assay, plate, control, measure, .keep_all = TRUE)

n_reanalysed <- file_log %>% filter(status == "Read") %>% nrow() -
  control_data %>% distinct(assay, plate, source_file) %>% nrow()
if (n_reanalysed > 0) {
  message(n_reanalysed, " older or duplicate analyses of the same plate(s) were left out")
}
file_log <- file_log %>%
  mutate(status = if_else(status == "Read" & !file %in% control_data$source_file,
                          "Not used: a more recent analysis of the same plate was used", status))

# ----------------------------------------------
# 4. Summary statistics and limits per control
# ----------------------------------------------

# Keep the controls in the order the assay scripts list them (e.g. antigens in spot order)
control_data <- control_data %>%
  group_by(assay) %>%
  mutate(control_order = match(control, unique(control)),
         measure_order = match(measure, unique(measure))) %>%
  ungroup() %>%
  mutate(has_value = is.finite(value) & value > 0)

# Every control is listed, including those with no values (e.g. every plate failed duplicate CV)
control_stats <- control_data %>%
  group_by(assay, control_order, measure_order, control, measure, unit) %>%
  summarise(
    n_plates = n(),
    n_plates_with_value = sum(has_value),
    geometric_mean = if (any(has_value)) 10^mean(log10(value[has_value])) else NA_real_,
    sd_log10 = if (sum(has_value) > 1) sd(log10(value[has_value])) else NA_real_,
    median = if (any(has_value)) median(value[has_value]) else NA_real_,
    # robust spread: MAD of log10 values, scaled to match an SD for normally distributed data
    robust_sd_log10 = if (sum(has_value) > 1) mad(log10(value[has_value])) else NA_real_,
    min = if (any(has_value)) min(value[has_value]) else NA_real_,
    max = if (any(has_value)) max(value[has_value]) else NA_real_,
    .groups = "drop"
  ) %>%
  arrange(assay, control_order, measure_order) %>%
  mutate(
    # plate-to-plate variation: all plates, and robust (less affected by unusual plates)
    geometric_cv_percent = round(100 * sqrt(exp((sd_log10 * log(10))^2) - 1), 1),
    robust_cv_percent = round(100 * sqrt(exp((robust_sd_log10 * log(10))^2) - 1), 1),
    enough_plates = n_plates_with_value >= min_plates_for_limits,
    # trend limits: median multiplied or divided by 10^(2 or 3 robust SDs)
    lower_3sd = if_else(enough_plates, median / 10^(3 * robust_sd_log10), NA_real_),
    lower_2sd = if_else(enough_plates, median / 10^(2 * robust_sd_log10), NA_real_),
    upper_2sd = if_else(enough_plates, median * 10^(2 * robust_sd_log10), NA_real_),
    upper_3sd = if_else(enough_plates, median * 10^(3 * robust_sd_log10), NA_real_)
  )

# Flag each plate against the limits (for information only)
control_data <- control_data %>%
  left_join(control_stats %>% dplyr::select(assay, control, measure, enough_plates,
                                            lower_3sd, lower_2sd, upper_2sd, upper_3sd),
            by = c("assay", "control", "measure")) %>%
  mutate(
    trend_flag = case_when(
      !has_value ~ paste0("No value (", coalesce(status, "missing"), ")"),
      !coalesce(enough_plates, FALSE) ~ paste0("Fewer than ", min_plates_for_limits, " plates with a value"),
      value < lower_3sd | value > upper_3sd ~ "Outside 3 SD",
      value < lower_2sd | value > upper_2sd ~ "Outside 2 SD",
      TRUE ~ "Within 2 SD"
    )
  ) %>%
  arrange(assay, control_order, measure_order, assay_date, plate)

control_data %>%
  count(assay, trend_flag)

# ----------------------------------------------
# 5. Trend plots
# ----------------------------------------------

# One plot per assay, or one per control when an assay has many control values
# (e.g. the 10-plex MSD controls, with one panel per antigen in spot order).
# Every control has a panel, and plates with no value are marked by grey ticks
# along the bottom, so missing results are visible.

if (!dir.exists(plot_dir)) {
  dir.create(plot_dir)
}

flag_colours <- c("Within 2 SD" = "black", "Outside 2 SD" = "#E69F00", "Outside 3 SD" = "#D55E00")
max_panels_per_plot <- 8

make_trend_plot <- function(d, stats, title, split_by_control) {
  # Panel labels, including how many plates gave a value
  stats <- stats %>%
    mutate(panel_label = paste0(if (split_by_control) "" else paste0(control, " - "),
                                measure, " (", unit, ")\nvalues from ", n_plates_with_value,
                                " of ", n_plates, " plates"))
  panel_levels <- stats$panel_label
  stats <- stats %>% mutate(panel = factor(panel_label, levels = panel_levels))
  d <- d %>%
    left_join(stats %>% dplyr::select(control, measure, panel), by = c("control", "measure")) %>%
    mutate(point_colour = if_else(trend_flag %in% names(flag_colours), trend_flag, "Within 2 SD"))
  values <- d %>% filter(has_value)
  missing <- d %>% filter(!has_value)
  limits <- stats %>% filter(enough_plates)
  n_panels <- length(panel_levels)
  n_cols <- min(if (split_by_control) 5 else 4, n_panels)

  p <- ggplot(values, aes(x = assay_date, y = value)) +
    geom_hline(data = filter(stats, n_plates_with_value > 0), aes(yintercept = median), colour = "grey30") +
    geom_hline(data = limits, aes(yintercept = lower_2sd), linetype = "dashed", colour = "#E69F00") +
    geom_hline(data = limits, aes(yintercept = upper_2sd), linetype = "dashed", colour = "#E69F00") +
    geom_hline(data = limits, aes(yintercept = lower_3sd), linetype = "dotted", colour = "#D55E00") +
    geom_hline(data = limits, aes(yintercept = upper_3sd), linetype = "dotted", colour = "#D55E00") +
    geom_line(aes(group = panel), colour = "grey70") +
    geom_point(aes(colour = point_colour), size = 2) +
    geom_rug(data = missing, aes(x = assay_date), inherit.aes = FALSE, sides = "b",
             colour = "grey45", linewidth = 1, length = unit(0.06, "npc")) +
    scale_colour_manual(values = flag_colours, breaks = names(flag_colours), drop = FALSE) +
    scale_x_date(limits = range(d$assay_date, na.rm = TRUE)) +
    scale_y_log10() +
    facet_wrap(~ panel, scales = "free_y", ncol = n_cols, drop = FALSE) +
    labs(
      title = title,
      subtitle = paste0("Solid line: median. Dashed: plus/minus 2 robust SD. Dotted: plus/minus 3 robust SD (shown once ",
                        min_plates_for_limits, "+ plates have a value). For information only.\n",
                        "Grey ticks along the bottom: plates with no value (e.g. duplicate CV too high or outside the calibration range)."),
      x = "Plate date",
      y = "Value (log scale)",
      colour = NULL
    ) +
    theme_bw(base_size = 10) +
    theme(legend.position = "top", strip.text = element_text(size = 8))
  list(plot = p, width = 3 * n_cols + 1, height = 2.6 * ceiling(n_panels / n_cols) + 2)
}

plot_files <- list() # for each assay: the plot files and their sizes
for (a in unique(control_data$assay)) {
  da <- control_data %>% filter(assay == a)
  sa <- control_stats %>% filter(assay == a)
  split_by_control <- nrow(sa) > max_panels_per_plot
  groups <- if (split_by_control) unique(sa$control) else list(unique(sa$control))
  plot_files[[a]] <- list()
  for (g in groups) {
    title <- if (split_by_control) paste0(a, " - ", g, " across plates") else paste0(a, " - controls across plates")
    tp <- make_trend_plot(filter(da, control %in% g), filter(sa, control %in% g), title, split_by_control)
    name <- if (split_by_control) paste0(a, "_", g) else a
    file <- file.path(plot_dir, paste0(gsub("[^A-Za-z0-9-]+", "_", name), "_controls.png"))
    ggsave(file, tp$plot, width = tp$width, height = tp$height, dpi = 200, limitsize = FALSE)
    plot_files[[a]][[length(plot_files[[a]]) + 1]] <- list(file = file, width = tp$width, height = tp$height)
  }
}

# -------------------------------------------
# 6. Generate the control tracking output file
# -------------------------------------------

wb <- createWorkbook()

read_me <- tibble(
  item = c(
    "Script version",
    "Results folder",
    "Date run",
    "Results files found",
    "Results files used",
    "Statistics",
    "Limits",
    "Trend flags"
  ),
  detail = c(
    script_version,
    results_folder,
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    nrow(file_log),
    sum(file_log$file %in% control_data$source_file),
    "Calculated on log10 values. geometric_cv_percent is the plate-to-plate variation using all plates; robust_cv_percent is less affected by unusual plates.",
    paste0("Median multiplied or divided by 10^(2 or 3 x robust SD of log10 values, from the MAD), shown once a control has ",
           min_plates_for_limits, " or more plates. For information only - not acceptance criteria."),
    "Each plate is compared with limits calculated from all plates, including itself."
  )
)

addWorksheet(wb, "Read me")
writeData(wb, "Read me", read_me)

addWorksheet(wb, "Files")
writeData(wb, "Files", file_log)

for (a in unique(control_data$assay)) {
  short <- substr(a, 1, 20)
  addWorksheet(wb, paste(short, "summary"))
  writeData(wb, paste(short, "summary"), control_stats %>%
              filter(assay == a) %>%
              dplyr::select(-control_order, -measure_order))
  addWorksheet(wb, paste(short, "values"))
  writeData(wb, paste(short, "values"), control_data %>%
              filter(assay == a) %>%
              dplyr::select(assay, plate, assay_date, control, measure, unit, value,
                            cv_percent, status, trend_flag, script_version, analysis_date, source_file))
  # Plots, one below another (an Excel row is about 0.2 inches)
  addWorksheet(wb, paste(short, "plots"))
  start_row <- 1
  for (pf in plot_files[[a]]) {
    insertImage(wb, paste(short, "plots"), pf$file, width = pf$width, height = pf$height,
                startRow = start_row, startCol = 1)
    start_row <- start_row + ceiling(pf$height / 0.2) + 2
  }
}

for (sheet in names(wb)) {
  setColWidths(wb, sheet, cols = 1:20, widths = "auto")
  freezePane(wb, sheet, firstRow = TRUE)
}

saveWorkbook(wb, output_file, overwrite = TRUE)

cat(
  "\nControl tracking complete.\n",
  "Results saved to: ",
  output_file,
  "\nPlots saved to: ",
  plot_dir,
  "\n"
)
