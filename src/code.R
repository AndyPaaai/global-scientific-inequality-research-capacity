# =============================================================================
# How Robust Are National Rankings of Highly Cited Scientists?
# Research Capacity Adjustment and Data Availability
# Reproducible analysis script for the manuscript (2026)
# =============================================================================
# Run from a clean R session after placing the ORIGINAL downloaded inputs under
# repository_root/data/ (subfolders are allowed). No intermediate CSV is needed.
# In RStudio: open the repository folder and source("src/code.R").
# In a shell: Rscript src/code.R
# Output: results/, Supplementary Material/, figures/ under repository_root.
# The source files are NEVER modified. See README.md for provenance and caveats.
# =============================================================================

# 00. Paths, packages, reproducibility -----------------------------------------
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_file <- if (length(file_arg)) {
  sub("^--file=", "", file_arg[[1]])
} else {
  tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
}
ROOT <- if (!is.null(script_file) && length(script_file) == 1L &&
            file.exists(script_file)) {
  dirname(normalizePath(script_file, winslash = "/"))
} else {
  normalizePath(getwd(), winslash = "/")
}
if (!dir.exists(file.path(ROOT, "data")) &&
    dir.exists(file.path(dirname(ROOT), "data"))) {
  ROOT <- dirname(ROOT)
}
if (nzchar(Sys.getenv("PAPER1_ROOT"))) {
  ROOT <- normalizePath(Sys.getenv("PAPER1_ROOT"), winslash = "/", mustWork = TRUE)
}
DATA <- file.path(ROOT, "data")
if (!dir.exists(DATA)) stop("Missing data/ directory in ", ROOT)

PACKAGES <- c("readxl", "readr", "dplyr", "tidyr", "countrycode",
              "ggplot2", "MASS", "sandwich", "svglite")
missing_packages <- PACKAGES[!vapply(PACKAGES, requireNamespace,
                                      logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  stop("Install these R packages before running code.R: ",
       paste(missing_packages, collapse = ", "))
}
suppressPackageStartupMessages({
  library(readxl)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
options(dplyr.summarise.inform = FALSE)
N_BOOT <- 500L
BOOT_SEED <- 20261106L

OUT <- file.path(ROOT, "results")
SUPP <- file.path(ROOT, "Supplementary Material")
FIG <- file.path(ROOT, "figures")
for (p in c(OUT, SUPP, FIG)) dir.create(p, recursive = TRUE, showWarnings = FALSE)

save_csv <- function(data, name, dir = OUT) {
  readr::write_csv(data, file.path(dir, name), na = "")
}
check_unique <- function(x, columns, label) {
  if (anyDuplicated(x[, columns, drop = FALSE])) {
    stop("Duplicate keys in ", label)
  }
}
find_one <- function(pattern) {
  f <- list.files(DATA, pattern = pattern, recursive = TRUE,
                  full.names = TRUE, ignore.case = TRUE)
  f <- f[!startsWith(basename(f), "~$")]
  if (length(f) != 1L) {
    stop("Expected exactly one input matching '", pattern,
         "' beneath data/; found ", length(f),
         if (length(f)) paste0(":\n", paste(f, collapse = "\n")) else "")
  }
  f[[1]]
}

# Required sources, frozen to the data snapshots used in the manuscript.
inputs <- c(
  io_annual = find_one("^Table_1_Authors_singleyr.*\\.xlsx$"),
  io_career = find_one("^Table_1_Authors_career.*\\.xlsx$"),
  unesco = find_one("^data\\.csv$"),
  gdp = find_one("^API_NY\\.GDP\\.PCAP\\.PP\\.KD.*\\.csv$"),
  population = find_one("^API_SP\\.POP\\.TOTL.*\\.csv$"),
  income = find_one("^OGHIST_.*\\.xlsx$")
)
input_manifest <- tibble(
  source = names(inputs), file = basename(inputs),
  bytes = as.numeric(file.info(unname(inputs))$size),
  md5 = unname(tools::md5sum(unname(inputs)))
)
save_csv(input_manifest, "input_manifest.csv")

# 01. Ioannidis: country-level records -----------------------------------------
# Each row of the author table is counted once, following the original workflow.
# The approximate top-2%-within-subfield flag was NOT used in manuscript models.
read_country_codes <- function(file) {
  headers <- names(readxl::read_excel(file, sheet = "Data", n_max = 0,
                                      .name_repair = "minimal"))
  if (!"cntry" %in% headers) stop("Missing 'cntry' column: ", file)
  types <- ifelse(headers == "cntry", "text", "skip")
  x <- readxl::read_excel(file, sheet = "Data", col_types = types,
                          .name_repair = "minimal")
  toupper(trimws(as.character(x$cntry)))
}
annual_country <- read_country_codes(inputs[["io_annual"]])
career_country <- read_country_codes(inputs[["io_career"]])
valid_iso3 <- function(x) !is.na(x) & grepl("^[A-Z]{3}$", x)
annual_unassigned <- which(!valid_iso3(annual_country))
career_unassigned <- which(!valid_iso3(career_country))
save_csv(tibble(record_number = annual_unassigned,
                country_code = annual_country[annual_unassigned]),
         "annual_records_without_iso3.csv")
save_csv(tibble(record_number = career_unassigned,
                country_code = career_country[career_unassigned]),
         "career_records_without_iso3.csv")
annual_count <- tibble(iso3 = annual_country[valid_iso3(annual_country)]) %>%
  count(iso3, name = "n_anual")
career_count <- tibble(iso3 = career_country[valid_iso3(career_country)]) %>%
  count(iso3, name = "n_carrera")
source_totals <- tibble(
  database = c("Annual 2025", "Career-long"),
  total_author_records = c(length(annual_country), length(career_country)),
  records_with_valid_country_code = c(sum(valid_iso3(annual_country)),
                                      sum(valid_iso3(career_country))),
  records_without_valid_country_code = c(length(annual_unassigned),
                                         length(career_unassigned))
)
save_csv(source_totals, "source_record_counts.csv")
rm(annual_country, career_country)
invisible(gc(verbose = FALSE))

# 02. UNESCO, World Bank, FY2026 income groups and UN M49 ----------------------
uis <- readr::read_csv(inputs[["unesco"]], show_col_types = FALSE)
required_uis <- c("indicatorId", "geoUnit", "year", "value")
if (!all(required_uis %in% names(uis))) stop("Unexpected UNESCO columns")
uis_panel <- uis %>%
  filter(indicatorId %in% c("EXPGDP.TOT", "RESDEN.INHAB.TFTE")) %>%
  transmute(
    iso3 = toupper(trimws(geoUnit)), year = as.integer(year),
    indicator = recode(indicatorId, "EXPGDP.TOT" = "id_pct_pib",
                       "RESDEN.INHAB.TFTE" = "investigadores_fte_millon"),
    value = suppressWarnings(as.numeric(value))
  )
check_unique(uis_panel, c("iso3", "year", "indicator"), "UNESCO indicators")
uis_panel <- tidyr::pivot_wider(uis_panel, names_from = indicator,
                                values_from = value)
rm(uis)

read_wdi <- function(file, code, value_name) {
  df <- readr::read_csv(file, skip = 4, show_col_types = FALSE,
                         name_repair = "unique")
  if (!all(c("Country Code", "Indicator Code") %in% names(df))) {
    stop("Unexpected WDI CSV header: ", basename(file))
  }
  years <- grep("^[0-9]{4}$", names(df), value = TRUE)
  x <- df %>% filter(.data[["Indicator Code"]] == code) %>%
    select(iso3 = `Country Code`, all_of(years)) %>%
    pivot_longer(all_of(years), names_to = "year", values_to = "value") %>%
    transmute(iso3 = toupper(trimws(iso3)), year = as.integer(year),
              value = suppressWarnings(as.numeric(value)))
  if (nrow(x) == 0) stop("WDI indicator not found: ", code)
  names(x)[names(x) == "value"] <- value_name
  check_unique(x, c("iso3", "year"), code)
  x
}
gdp <- read_wdi(inputs[["gdp"]], "NY.GDP.PCAP.PP.KD", "pib_pc_ppa")
pop <- read_wdi(inputs[["population"]], "SP.POP.TOTL", "poblacion")
panel <- uis_panel %>% full_join(gdp, by = c("iso3", "year")) %>%
  full_join(pop, by = c("iso3", "year")) %>% arrange(iso3, year)
check_unique(panel, c("iso3", "year"), "country-year panel")
rm(gdp, pop, uis_panel)

hist <- readxl::read_excel(inputs[["income"]],
                            sheet = "Country Analytical History", skip = 4,
                            col_types = "text", .name_repair = "unique")
if (!"FY26" %in% names(hist)) stop("FY26 not present in OGHIST workbook")
income <- hist %>% transmute(
  iso3 = toupper(trimws(as.character(.data[[names(hist)[1]]]))),
  nombre_bm = as.character(.data[[names(hist)[2]]]),
  codigo_ingreso_fy2026 = trimws(FY26)
) %>% filter(valid_iso3(iso3)) %>% mutate(
  grupo_ingreso = case_when(
    codigo_ingreso_fy2026 == "L" ~ "Low income",
    codigo_ingreso_fy2026 == "LM" ~ "Lower middle income",
    codigo_ingreso_fy2026 == "UM" ~ "Upper middle income",
    codigo_ingreso_fy2026 == "H" ~ "High income",
    TRUE ~ NA_character_
  )
) %>% distinct(iso3, .keep_all = TRUE)
rm(hist)

cl <- countrycode::codelist
m49_cols <- c("iso3c", "iso.name.en", "un.region.name", "un.regionsub.name")
if (!all(m49_cols %in% names(cl))) stop("Unsupported countrycode codelist schema")
m49 <- cl %>% transmute(
  iso3 = toupper(as.character(.data[["iso3c"]])),
  nombre_onu = .data[["iso.name.en"]],
  region_onu = .data[["un.region.name"]],
  subregion_onu = .data[["un.regionsub.name"]]
) %>% filter(valid_iso3(iso3)) %>% distinct(iso3, .keep_all = TRUE)

latest_in_window <- function(data, variable, from, to) {
  x <- data %>% filter(year >= from, year <= to,
                        is.finite(.data[[variable]])) %>%
    select(iso3, year, value = all_of(variable)) %>%
    arrange(iso3, desc(year)) %>% group_by(iso3) %>%
    slice_head(n = 1) %>% ungroup()
  names(x)[names(x) == "year"] <- paste0("year_", variable)
  names(x)[names(x) == "value"] <- variable
  x
}

# Reconstruct the same universe as the original integration script.
population_2025_codes <- panel %>%
  filter(year == 2025, is.finite(poblacion), poblacion > 0) %>% pull(iso3)
country_universe <- sort(unique(c(
  income$iso3[!is.na(income$grupo_ingreso)],
  annual_count$iso3, career_count$iso3,
  intersect(population_2025_codes, m49$iso3)
)))
country_universe <- country_universe[valid_iso3(country_universe)]
master <- tibble(iso3 = country_universe) %>%
  left_join(income, by = "iso3") %>% left_join(m49, by = "iso3") %>%
  left_join(annual_count, by = "iso3") %>%
  left_join(career_count, by = "iso3") %>%
  mutate(
    pais = coalesce(nombre_bm, nombre_onu, iso3),
    n_anual = tidyr::replace_na(n_anual, 0L),
    n_carrera = tidyr::replace_na(n_carrera, 0L)
  )
check_unique(master, "iso3", "master")
if (sum(master$n_anual) != sum(annual_count$n_anual)) {
  stop("Annual record count mismatch after country integration")
}
if (sum(master$n_carrera) != sum(career_count$n_carrera)) {
  stop("Career record count mismatch after country integration")
}

panel <- panel %>% filter(iso3 %in% master$iso3) %>%
  left_join(master %>% select(iso3, pais, region_onu, grupo_ingreso), by = "iso3")
save_csv(master, "master_countries.csv")
save_csv(panel, "country_year_panel.csv")

# 03. Reference values, analytical samples and data coverage -------------------
rd_ref <- latest_in_window(panel, "id_pct_pib", 2019L, 2023L) %>%
  rename(id_pct_pib_ref = id_pct_pib, anio_id_ref = year_id_pct_pib)
fte_ref <- latest_in_window(panel, "investigadores_fte_millon", 2019L, 2023L) %>%
  rename(fte_millon_ref = investigadores_fte_millon,
         anio_fte_ref = year_investigadores_fte_millon)
pib23 <- panel %>% filter(year == 2023L) %>%
  select(iso3, pib_pc_ppa_2023 = pib_pc_ppa)
pop_at_fte_year <- panel %>%
  select(iso3, anio_fte_ref = year, poblacion_anio_fte = poblacion)

sample_all <- master %>%
  select(iso3, pais, region_onu, subregion_onu, grupo_ingreso,
         n_anual, n_carrera) %>%
  left_join(rd_ref, by = "iso3") %>%
  left_join(fte_ref, by = "iso3") %>%
  left_join(pib23, by = "iso3") %>%
  left_join(pop_at_fte_year, by = c("iso3", "anio_fte_ref")) %>%
  mutate(
    investigadores_fte_total_ref = fte_millon_ref * poblacion_anio_fte / 1e6,
    A = is.finite(id_pct_pib_ref) & id_pct_pib_ref >= 0 &
      is.finite(investigadores_fte_total_ref) &
      investigadores_fte_total_ref > 0 & !is.na(region_onu),
    B = A & is.finite(pib_pc_ppa_2023) & pib_pc_ppa_2023 > 0
  )
A <- sample_all %>% filter(A)
B <- sample_all %>% filter(B)
save_csv(sample_all, "sample_eligibility_all_economies.csv")
save_csv(A, "analytical_sample_A.csv")
save_csv(B, "analytical_sample_B.csv")

expected_counts <- c(annual = 249310L, assigned_annual = 249141L,
                     master = 224L, sample_A = 101L, sample_B = 98L,
                     authors_B = 215130L)
actual_counts <- c(annual = source_totals$total_author_records[1],
                   assigned_annual = source_totals$records_with_valid_country_code[1],
                   master = nrow(master), sample_A = nrow(A),
                   sample_B = nrow(B), authors_B = sum(B$n_anual))
if (!identical(as.numeric(actual_counts), as.numeric(expected_counts))) {
  stop("Inputs or country classifications differ from the published snapshot.\n",
       paste(names(actual_counts), actual_counts, expected_counts,
             sep = ": observed=", collapse = "\n"),
       "\nUse the archived source versions; do not silently change inclusion criteria.")
}

coverage_by <- function(column, label) {
  sample_all %>% mutate(category = coalesce(as.character(.data[[column]]),
                                             "Unclassified")) %>%
    group_by(category) %>% summarise(
      economies_master = n(),
      economies_sample_A = sum(A),
      economies_sample_B = sum(B),
      coverage_A_pct = 100 * mean(A),
      coverage_B_pct = 100 * mean(B),
      annual_records_master = sum(n_anual),
      annual_records_sample_B = sum(n_anual[B]),
      .groups = "drop"
    ) %>% mutate(classification = label, .before = 1)
}
coverage_income <- coverage_by("grupo_ingreso", "Income group")
coverage_region <- coverage_by("region_onu", "Geographical region")
save_csv(coverage_income, "coverage_by_income.csv")
save_csv(coverage_region, "coverage_by_region.csv")
coverage_overall <- tibble(
  classification = "Overall", category = "All economies",
  economies_master = nrow(sample_all), economies_sample_A = nrow(A),
  economies_sample_B = nrow(B),
  coverage_A_pct = 100 * nrow(A) / nrow(sample_all),
  coverage_B_pct = 100 * nrow(B) / nrow(sample_all),
  annual_records_master = sum(sample_all$n_anual),
  annual_records_sample_B = sum(B$n_anual)
)
S1 <- bind_rows(coverage_overall, coverage_income, coverage_region)
save_csv(S1, "Supplementary_Table_S1.csv", SUPP)

# 04. Models, dispersion diagnostics and HC3 inference -------------------------
A <- A %>% mutate(log_fte = log(investigadores_fte_total_ref),
                  log2_pib = log2(pib_pc_ppa_2023))
B <- B %>% mutate(log_fte = log(investigadores_fte_total_ref),
                  log2_pib = log2(pib_pc_ppa_2023))
formula_rd <- n_anual ~ id_pct_pib_ref + offset(log_fte)
formula_full <- n_anual ~ id_pct_pib_ref + log2_pib + offset(log_fte)
fit_nb <- function(formula, data) {
  fit <- MASS::glm.nb(formula, data = data,
                      control = glm.control(maxit = 150))
  if (!isTRUE(fit$converged)) stop("Negative-binomial model failed to converge")
  fit
}
pearson_dispersion <- function(fit) {
  sum(residuals(fit, type = "pearson")^2) / df.residual(fit)
}
model_A <- fit_nb(formula_rd, A)
model_0 <- fit_nb(formula_rd, B)       # nested comparison, same 98 economies
model_1 <- fit_nb(formula_full, B)     # manuscript's fully adjusted model
poisson_B <- glm(formula_full, data = B, family = poisson(link = "log"))

extract_irr <- function(fit, model, n = stats::nobs(fit)) {
  b <- coef(fit)
  # Do not silently replace HC3 inference by ordinary model-based standard errors.
  V <- sandwich::vcovHC(fit, type = "HC3")
  se <- sqrt(diag(V))[names(b)]
  if (any(!is.finite(se) | se <= 0)) stop("Invalid HC3 standard errors")
  tibble(
    model = model, n_economies = n, predictor = names(b),
    coefficient = unname(b), HC3_SE = unname(se),
    IRR = unname(exp(b)), CI95_lower = unname(exp(b - 1.96 * se)),
    CI95_upper = unname(exp(b + 1.96 * se)),
    p_value = unname(2 * pnorm(-abs(b / se)))
  )
}
model_IRR <- bind_rows(extract_irr(model_0, "Model 1: RD + FTE offset"),
                       extract_irr(model_1, "Model 2: RD + GDP + FTE offset"))
LR <- 2 * (as.numeric(logLik(model_1)) - as.numeric(logLik(model_0)))
model_fit <- tibble(
  model = c("Model 1: RD + FTE offset", "Model 2: RD + GDP + FTE offset"),
  n_economies = nrow(B), AIC = c(AIC(model_0), AIC(model_1)),
  theta = c(model_0$theta, model_1$theta),
  pearson_dispersion = c(pearson_dispersion(model_0),
                         pearson_dispersion(model_1)),
  likelihood_ratio_for_GDP = c(NA_real_, LR),
  p_likelihood_ratio_for_GDP = c(NA_real_, pchisq(LR, 1, lower.tail = FALSE)),
  poisson_dispersion_full_model = pearson_dispersion(poisson_B)
)
save_csv(model_IRR, "Table_1_model_IRR.csv")
save_csv(model_fit, "Table_1_model_fit.csv")

# 05. National rankings and pairwise agreement -------------------------------
pred <- as.numeric(predict(model_1, newdata = B, type = "response"))
if (length(pred) != nrow(B) || any(!is.finite(pred) | pred <= 0)) {
  stop("Invalid predictions for national rankings")
}
rankings <- B %>% transmute(
  iso3, economy = pais, income_group = grupo_ingreso, UN_region = region_onu,
  annual_listed_authors = n_anual,
  researcher_FTE = investigadores_fte_total_ref,
  listed_per_10000_FTE = 10000 * n_anual / investigadores_fte_total_ref,
  expected_listed_authors = pred,
  observed_expected_ratio = n_anual / pred,
  RD_expenditure_pct_GDP = id_pct_pib_ref,
  RD_reference_year = anio_id_ref,
  researcher_FTE_reference_year = anio_fte_ref,
  GDP_PPP_per_capita_2023 = pib_pc_ppa_2023
) %>% mutate(
  rank_absolute = min_rank(desc(annual_listed_authors)),
  rank_FTE_normalized = min_rank(desc(listed_per_10000_FTE)),
  rank_model_adjusted = min_rank(desc(observed_expected_ratio)),
  change_absolute_to_FTE = rank_absolute - rank_FTE_normalized,
  change_FTE_to_adjusted = rank_FTE_normalized - rank_model_adjusted,
  change_absolute_to_adjusted = rank_absolute - rank_model_adjusted,
  fewer_than_20_listed = annual_listed_authors < 20,
  researcher_FTE_below_1000 = researcher_FTE < 1000
) %>% arrange(rank_model_adjusted, iso3)
save_csv(rankings, "Supplementary_Table_S2.csv", SUPP)

rank_agreement <- function(x, y, name) {
  tibble(comparison = name,
         Spearman_rho = cor(x, y, method = "spearman"),
         Kendall_tau = cor(x, y, method = "kendall"),
         median_absolute_rank_difference = median(abs(x-y)),
         n_moved_20_or_more_positions = sum(abs(x-y) >= 20),
         pct_moved_20_or_more_positions = 100 * mean(abs(x-y) >= 20),
         overlap_in_top_ten = length(intersect(which(x <= 10), which(y <= 10))))
}
rank_comparison <- bind_rows(
  rank_agreement(rankings$rank_absolute, rankings$rank_FTE_normalized,
                 "Absolute vs FTE-normalized"),
  rank_agreement(rankings$rank_absolute, rankings$rank_model_adjusted,
                 "Absolute vs model-adjusted"),
  rank_agreement(rankings$rank_FTE_normalized, rankings$rank_model_adjusted,
                 "FTE-normalized vs model-adjusted")
)
save_csv(rank_comparison, "Table_2_rank_agreement.csv")

# 06. Bootstrap ranking stability --------------------------------------------
# Original 98 economies remain fixed when predicting across resampled fits.
set.seed(BOOT_SEED)
boot_ranks <- matrix(NA_real_, nrow = nrow(B), ncol = N_BOOT)
for (i in seq_len(N_BOOT)) {
  ii <- sample.int(nrow(B), size = nrow(B), replace = TRUE)
  fit <- suppressWarnings(tryCatch(
    MASS::glm.nb(formula_full, data = B[ii, , drop = FALSE],
                 control = glm.control(maxit = 150)),
    error = function(e) NULL
  ))
  predicted <- if (is.null(fit) || !isTRUE(fit$converged)) NULL else {
    suppressWarnings(tryCatch(as.numeric(predict(fit, newdata = B,
                                                 type = "response")),
                              error = function(e) NULL))
  }
  if (is.null(predicted) || length(predicted) != nrow(B) ||
      any(!is.finite(predicted) | predicted <= 0)) next
  boot_ranks[, i] <- rank(-B$n_anual / predicted, ties.method = "min")
}
valid_boot <- colSums(!is.na(boot_ranks)) == nrow(B)
boot_ranks <- boot_ranks[, valid_boot, drop = FALSE]
if (ncol(boot_ranks) < 0.8 * N_BOOT) stop("Too few valid bootstrap replicates")
bootstrap_stats <- tibble(
  iso3 = B$iso3,
  bootstrap_median_rank = apply(boot_ranks, 1, median),
  bootstrap_rank_p05 = apply(boot_ranks, 1, quantile, probs = 0.05),
  bootstrap_rank_p95 = apply(boot_ranks, 1, quantile, probs = 0.95),
  bootstrap_top10_frequency = rowMeans(boot_ranks <= 10)
)
S3 <- rankings %>% select(
  iso3, economy, income_group, annual_listed_authors, researcher_FTE,
  rank_model_adjusted, fewer_than_20_listed, researcher_FTE_below_1000
) %>% left_join(bootstrap_stats, by = "iso3") %>%
  mutate(bootstrap_rank_interval_width = bootstrap_rank_p95 - bootstrap_rank_p05) %>%
  arrange(rank_model_adjusted, iso3)
save_csv(S3, "Supplementary_Table_S3.csv", SUPP)

# 07. Sensitivity analyses ----------------------------------------------------
# FTE denominator restriction; full model on 85 economies in the published run.
B_large <- B %>% filter(investigadores_fte_total_ref >= 1000)
model_large <- fit_nb(formula_full, B_large)
sens_FTE <- bind_rows(
  extract_irr(model_1, "Full model: 98 economies"),
  extract_irr(model_large, "Full model: FTE >= 1000")
) %>% filter(predictor != "(Intercept)") %>% mutate(
  analysis = "FTE denominator sensitivity", scenario = model,
  excluded_ISO3 = NA_character_
)

# Reconstruct alternative windows from the exact same country-year source panel.
window_sample <- function(from, to) {
  r <- latest_in_window(panel, "id_pct_pib", from, to) %>%
    rename(rd_year = year_id_pct_pib, rd = id_pct_pib)
  f <- latest_in_window(panel, "investigadores_fte_millon", from, to) %>%
    rename(fte_year = year_investigadores_fte_millon,
           fte_per_million = investigadores_fte_millon)
  pp <- panel %>% select(iso3, fte_year = year, population = poblacion)
  master %>% select(iso3, n_anual, region_onu) %>%
    left_join(r, by = "iso3") %>% left_join(f, by = "iso3") %>%
    left_join(pp, by = c("iso3", "fte_year")) %>%
    left_join(pib23, by = "iso3") %>%
    mutate(
      FTE = fte_per_million * population / 1e6,
      A = is.finite(rd) & rd >= 0 & is.finite(FTE) & FTE > 0 &
        !is.na(region_onu),
      B = A & is.finite(pib_pc_ppa_2023) & pib_pc_ppa_2023 > 0
    )
}
windows <- list("2015-2023" = c(2015L, 2023L),
                "2019-2023" = c(2019L, 2023L),
                "2019-2024" = c(2019L, 2024L),
                "2021-2023" = c(2021L, 2023L))
window_results <- list()
for (window_name in names(windows)) {
  bounds <- windows[[window_name]]
  v <- window_sample(bounds[1], bounds[2])
  for (model_name in c("A", "B")) {
    data_window <- v %>% filter(.data[[model_name]]) %>%
      mutate(log_FTE = log(FTE), log2_GDP = log2(pib_pc_ppa_2023))
    f <- if (model_name == "A") {
      n_anual ~ rd + offset(log_FTE)
    } else {
      n_anual ~ rd + log2_GDP + offset(log_FTE)
    }
    fit <- fit_nb(f, data_window)
    window_results[[paste(window_name, model_name)]] <-
      extract_irr(fit, paste0("Window ", window_name, "; model ", model_name)) %>%
      filter(predictor != "(Intercept)") %>%
      mutate(analysis = "Alternative R&D reference window",
             scenario = window_name, excluded_ISO3 = NA_character_)
  }
}
sens_windows <- bind_rows(window_results)

# Leave-one-country-out sensitivity, using Cook's distance plus fixed candidates.
leave_one_out <- function(data, fit, formula, model_name) {
  cook <- tryCatch(as.numeric(stats::cooks.distance(fit)),
                   error = function(e) rep(NA_real_, nrow(data)))
  influential <- data$iso3[head(order(cook, decreasing = TRUE, na.last = NA), 5)]
  candidates <- intersect(unique(c(influential, "USA", "CHN", "QAT", "KWT", "GTM")),
                          data$iso3)
  bind_rows(lapply(candidates, function(code) {
    restricted <- data %>% filter(iso3 != code)
    fitted <- fit_nb(formula, restricted)
    extract_irr(fitted, paste0("Model ", model_name, "; exclude ", code)) %>%
      filter(predictor != "(Intercept)") %>%
      mutate(analysis = "Leave-one-country-out",
             scenario = paste0("Excluded ", code), excluded_ISO3 = code)
  }))
}
sens_LOO <- bind_rows(
  leave_one_out(A, model_A, formula_rd, "A"),
  leave_one_out(B, model_1, formula_full, "B")
)

# Harmonize predictor labels across original scripts and models.
S4 <- bind_rows(sens_FTE, sens_windows, sens_LOO) %>%
  mutate(
    predictor = recode(predictor,
      "id_pct_pib_ref" = "R&D expenditure (% GDP)",
      "rd" = "R&D expenditure (% GDP)",
      "log2_pib" = "GDP per capita PPP (doubling)",
      "log2_GDP" = "GDP per capita PPP (doubling)")
  ) %>% select(analysis, scenario, model, excluded_ISO3, n_economies,
             predictor, coefficient, HC3_SE, IRR, CI95_lower, CI95_upper, p_value)
save_csv(S4, "Supplementary_Table_S4.csv", SUPP)

# 08. Publication figures, saved separately for Inkscape ----------------------
# Components for Figure 1 (A-B), Figure 2 (A-B), Figure 3.
COLORS <- c("High income" = "#2455A4", "Upper middle income" = "#008C78",
            "Lower middle income" = "#E18A20", "Low income" = "#B34583")
publication_theme <- function(base = 10.5) {
  theme_minimal(base_size = base, base_family = "Arial") +
    theme(
      plot.title = element_text(face = "bold", size = 12, colour = "#233447"),
      axis.title = element_text(size = 10, colour = "#283747"),
      axis.text = element_text(size = 9.2, colour = "#354455"),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#E9EDF1", linewidth = 0.35),
      legend.position = "bottom", legend.title = element_blank(),
      legend.text = element_text(size = 8.3),
      plot.margin = margin(12, 16, 10, 12)
    )
}
save_figure <- function(p, name, width, height) {
  ggplot2::ggsave(file.path(FIG, paste0(name, ".svg")), p,
                  device = svglite::svglite, width = width, height = height,
                  units = "in", bg = "white")
  ggplot2::ggsave(file.path(FIG, paste0(name, ".png")), p,
                  width = width, height = height, units = "in", dpi = 600,
                  bg = "white")
  tryCatch(ggplot2::ggsave(file.path(FIG, paste0(name, ".pdf")), p,
                           device = grDevices::cairo_pdf,
                           width = width, height = height, units = "in",
                           bg = "white"),
           error = function(e) message("PDF not generated for ", name, ": ", e$message))
}

coverage_plot <- function(d, title, levels) {
  d <- d %>% filter(category != "Unclassified") %>%
    mutate(category = factor(category, levels = levels),
           label = sprintf("%.1f%%  (%d/%d)", coverage_B_pct,
                           economies_sample_B, economies_master))
  ggplot(d, aes(y = category)) +
    geom_col(aes(x = 100), fill = "#E7ECF0", width = 0.56) +
    geom_col(aes(x = coverage_B_pct), fill = "#126E82", width = 0.56) +
    geom_text(aes(x = 103, label = label), hjust = 0, size = 3.2,
              colour = "#273847", family = "Arial") +
    scale_x_continuous(limits = c(0, 141), breaks = c(0, 25, 50, 75, 100),
                       labels = function(x) paste0(x, "%"), expand = c(0, 0)) +
    labs(title = title, x = "Economies with complete indicators (%)", y = NULL) +
    publication_theme() +
    theme(panel.grid.major.y = element_blank())
}
fig1A <- coverage_plot(coverage_income, "A   Income groups",
                       c("Low income", "Lower middle income",
                         "Upper middle income", "High income"))
fig1B <- coverage_plot(coverage_region, "B   Geographical regions",
                       c("Oceania", "Africa", "Americas", "Asia", "Europe"))
save_figure(fig1A, "Figure_1A_income_coverage", 7.4, 3.35)
save_figure(fig1B, "Figure_1B_region_coverage", 7.4, 3.35)

ranking_scatter <- function(x, y, title, xlab, ylab) {
  rho <- cor(rankings[[x]], rankings[[y]], method = "spearman")
  dd <- rankings %>% mutate(income_group = factor(income_group, levels = names(COLORS)))
  ggplot(dd, aes(x = .data[[x]], y = .data[[y]])) +
    geom_abline(intercept = 0, slope = 1, colour = "#AEB9C3",
                linewidth = 0.65, linetype = "22") +
    geom_point(aes(fill = income_group), shape = 21, colour = "white",
               size = 2.8, stroke = 0.35, alpha = 0.95) +
    annotate("label", x = 5, y = 92,
             label = sprintf("Spearman rho = %.3f", rho), hjust = 0,
             size = 3.2, label.size = 0, family = "Arial", fill = "white") +
    scale_fill_manual(values = COLORS, drop = FALSE) +
    scale_x_continuous(limits = c(1, 98), breaks = c(1, 25, 50, 75, 98),
                       expand = expansion(mult = 0.025)) +
    scale_y_continuous(limits = c(1, 98), breaks = c(1, 25, 50, 75, 98),
                       expand = expansion(mult = 0.025)) +
    coord_fixed(ratio = 1, clip = "off") +
    labs(title = title, x = xlab, y = ylab, fill = NULL) +
    guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
    publication_theme() + theme(legend.key.width = grid::unit(1, "lines"))
}
fig2A <- ranking_scatter("rank_absolute", "rank_FTE_normalized",
                         "A   Absolute vs FTE-normalized", "Absolute-count rank",
                         "FTE-normalized rank")
fig2B <- ranking_scatter("rank_FTE_normalized", "rank_model_adjusted",
                         "B   FTE vs model-adjusted", "FTE-normalized rank",
                         "Model-adjusted rank")
save_figure(fig2A, "Figure_2A_absolute_vs_FTE", 3.8, 4.65)
save_figure(fig2B, "Figure_2B_FTE_vs_adjusted", 3.8, 4.65)

first10 <- S3 %>% arrange(rank_model_adjusted, iso3) %>%
  slice_head(n = 10) %>% mutate(panel = "Top 10 by adjusted rank")
widest10 <- S3 %>% anti_join(first10, by = "iso3") %>%
  arrange(desc(bootstrap_rank_interval_width), iso3) %>%
  slice_head(n = 10) %>% mutate(panel = "10 widest rank intervals")
selected <- bind_rows(first10, widest10) %>%
  mutate(panel = factor(panel, levels = c("Top 10 by adjusted rank",
                                          "10 widest rank intervals")),
         label = paste0(economy, " (", iso3, ")"),
         FTE_group = if_else(researcher_FTE_below_1000, "<1,000 FTE", "1,000+ FTE"))
selected$label <- factor(selected$label, levels = rev(selected$label))
fig3 <- ggplot(selected, aes(y = label)) +
  geom_vline(xintercept = 10, linetype = "dotted", colour = "#9DAAB5") +
  geom_segment(aes(x = bootstrap_rank_p05, xend = bootstrap_rank_p95,
                   yend = label), colour = "#97A8B7", linewidth = 1.15) +
  geom_point(aes(x = rank_model_adjusted, fill = FTE_group),
             shape = 21, size = 3, stroke = 0.7, colour = "#24364C") +
  facet_grid(panel ~ ., scales = "free_y", space = "free_y") +
  scale_fill_manual(values = c("1,000+ FTE" = "#315A77", "<1,000 FTE" = "#D18B21")) +
  scale_x_continuous(limits = c(1, 98), breaks = c(1, 10, 25, 50, 75, 98),
                     expand = expansion(mult = 0.02)) +
  labs(title = "Model-adjusted rank stability",
       x = "Adjusted ranking position (lower means higher representation)",
       y = NULL, fill = NULL) +
  publication_theme(10.3) +
  theme(strip.background = element_rect(fill = "#EFF3F6", colour = NA),
        strip.text = element_text(face = "bold", size = 9.5),
        panel.spacing = grid::unit(0.65, "lines"),
        axis.text.y = element_text(size = 9))
save_figure(fig3, "Figure_3_bootstrap_stability", 8.3, 9.0)
save_csv(selected %>% select(iso3, economy, panel, rank_model_adjusted,
                             bootstrap_rank_p05, bootstrap_rank_p95,
                             researcher_FTE_below_1000),
         "Figure_3_selected_economies.csv")

# 09. Record reproducibility information -------------------------------------
run_summary <- c(
  "National highly cited researcher comparisons: reproducibility report",
  paste("Run time:", Sys.time()),
  paste("Annual author records:", source_totals$total_author_records[1]),
  paste("Annual author records with ISO3:", source_totals$records_with_valid_country_code[1]),
  paste("Master economies:", nrow(master)),
  paste("Sample A economies:", nrow(A)),
  paste("Sample B economies:", nrow(B)),
  paste("Annual author records in sample B:", sum(B$n_anual)),
  paste("Sample B economies with zero annual records:", sum(B$n_anual == 0)),
  paste("Bootstrap valid replicates:", ncol(boot_ranks), "of", N_BOOT),
  paste("Poisson Pearson dispersion (full model):", pearson_dispersion(poisson_B)),
  paste("Model 1 AIC:", AIC(model_0)),
  paste("Model 2 AIC:", AIC(model_1)),
  paste("Likelihood ratio p value:", pchisq(LR, 1, lower.tail = FALSE)),
  "Researchers FTE are not the Scopus-eligible author population.",
  "Bootstrap rank intervals exclude uncertainty in observed inputs.",
  "Observed/expected ratios are not direct measures of scientific quality."
)
writeLines(run_summary, file.path(OUT, "reproducibility_report.txt"))
capture.output(sessionInfo(), file = file.path(OUT, "sessionInfo.txt"))
message("Completed. Figures: ", FIG, "; supplementary CSVs: ", SUPP)
