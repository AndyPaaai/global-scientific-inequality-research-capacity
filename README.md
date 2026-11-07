# How Robust Are National Rankings of Highly Cited Scientists? Research Capacity Adjustment and Data Availability

[![DOI](https://zenodo.org/badge/1448998565.svg)](https://doi.org/10.5281/zenodo.24027736)

**Author:** Andy A. Acosta-Monterrosa  
**Repository:** [https://github.com/AndyPaaai/global-scientific-inequality-research-capacity](https://github.com/AndyPaaai/global-scientific-inequality-research-capacity)  
**Zenodo DOI:** [https://doi.org/10.5281/zenodo.24027736](https://doi.org/10.5281/zenodo.24027736)

---

## Overview

This repository contains the raw source datasets, reproducible R analytical workflow (`src/code.R`), and supplementary tables (`Supplementary Material/`) accompanying the manuscript:

> **How Robust Are National Rankings of Highly Cited Scientists? Research Capacity Adjustment and Data Availability**  
> *Global inequalities in highly cited scientist representation: The role of research capacity and economic development*  
> **Author:** Andy A. Acosta-Monterrosa

The study conducts a cross-sectional, country/economy-level bibliometric analysis of the **August 2026 update (Version 9)** of the Ioannidis science-wide author databases (2025 single-year citation impact), integrated with research and development (R&D) indicators from the **UNESCO Institute for Statistics (UIS)**, macroeconomic and demographic data from the **World Bank World Development Indicators (WDI)**, World Bank FY2026 income classifications, and **United Nations M49** geographical regions.

---

## 1. Repository Structure

```text
global-scientific-inequality-research-capacity/
├── LICENSE
├── README.md
├── src/
│   └── code.R                                                      # Main reproducible R workflow
├── Supplementary Material/
│   ├── Supplementary_Table_S1.csv                                  # Data availability by income group & UN region (12 rows)
│   ├── Supplementary_Table_S2.csv                                  # National counts, FTE rates, O/E ratios & rankings (98 rows)
│   ├── Supplementary_Table_S3.csv                                  # Bootstrap rank stability (500 resamples; 98 rows)
│   └── Supplementary_Table_S4.csv                                  # Sensitivity analyses across windows, FTE cutoffs & LOO (40 rows)
└── data/
    ├── classifications/
    │   └── OGHIST_2026_10_08.xlsx                                  # World Bank historical income classifications (FY2026)
    ├── ioannidis_v9_2026/
    │   ├── FREQUENTLY ASKED QUESTIONS 2026.docx
    │   ├── Table_1_Authors_career_2025_pubs_since_1788_wopp_extracted_202608.xlsx
    │   ├── Table_1_Authors_singleyr_2025_pubs_since_1788_wopp_extracted_202608.xlsx
    │   ├── Table_2_field_subfield_thresholds_career_2025_pubs_since_1788_wopp_extracted_202608.xlsx
    │   ├── Table_2_field_subfield_thresholds_singleyr_2025_pubs_since_1788_wopp_extracted_202608.xlsx
    │   ├── Table_3_maxlog_career_2025_pubs_since_1788_wopp_extracted_202608.xlsx
    │   └── Table_3_maxlog_singleyr_2025_pubs_since_1788_wopp_extracted_202608.xlsx
    ├── unesco_uis/
    │   ├── data.csv                                                # UNESCO UIS SDG 9.5.1 & 9.5.2 extract
    │   ├── disaggregations.csv
    │   ├── footnotes.csv
    │   ├── glossary-terms.csv
    │   ├── indicators.csv
    │   └── README.md
    └── world_bank/
        ├── GDP_per_capita_PPA/
        │   ├── API_NY.GDP.PCAP.PP.KD_DS2_en_csv_v2_1629.csv        # WDI GDP per capita, PPP (constant 2021 international $)
        │   ├── Metadata_Country_API_NY.GDP.PCAP.PP.KD_DS2_en_csv_v2_1629.csv
        │   └── Metadata_Indicator_API_NY.GDP.PCAP.PP.KD_DS2_en_csv_v2_1629.csv
        └── total_population/
            ├── API_SP.POP.TOTL_DS2_en_csv_v2_5254.csv              # WDI total population (matched to FTE reference year)
            ├── Metadata_Country_API_SP.POP.TOTL_DS2_en_csv_v2_5254.csv
            └── Metadata_Indicator_API_SP.POP.TOTL_DS2_en_csv_v2_5254.csv
```

When `src/code.R` is executed, it automatically creates (or updates):
- `results/` — Intermediate audit tables, sample eligibility files, `Table_1_model_IRR.csv`, `Table_1_model_fit.csv`, `Table_2_rank_agreement.csv`, `reproducibility_report.txt`, and `sessionInfo.txt`.
- `Supplementary Material/` — Regenerates `Supplementary_Table_S1.csv` through `Supplementary_Table_S4.csv`.
- `figures/` — Exports high-resolution publication panels (`Figure_1A_income_coverage`, `Figure_1B_region_coverage`, `Figure_2A_absolute_vs_FTE`, `Figure_2B_FTE_vs_adjusted`, and `Figure_3_bootstrap_stability`) in `.svg`, `.png` (600 DPI), and `.pdf` formats.

---

## 2. Original Data Sources

All raw input snapshots used in the manuscript are staged under `data/`:

1. **Ioannidis Science-Wide Author Databases (Version 9, August 2026):**  
   Ioannidis JPA. *August 2026 data-update for "Updated science-wide author databases of standardized citation indicators"*, Version 9. Elsevier Data Repository. DOI: [https://doi.org/10.17632/btchxktzyw.9](https://doi.org/10.17632/btchxktzyw.9).  
   - Primary outcome: **single-year 2025** citation database (`Table_1_Authors_singleyr_2025_pubs_since_1788_wopp_extracted_202608.xlsx`).
   - Validation & master universe construction: **career-long** database (`Table_1_Authors_career_2025_pubs_since_1788_wopp_extracted_202608.xlsx`).
   - Additional companion files from Version 9 (`Table_2_*`, `Table_3_*`, and FAQ documentation) are included in `data/ioannidis_v9_2026/` for completeness.

2. **UNESCO Institute for Statistics (UIS):**  
   SDG Indicator 9.5.1 — *Research and development expenditure as a proportion of GDP* (`EXPGDP.TOT`) and SDG Indicator 9.5.2 — *Researchers (in full-time equivalent) per million inhabitants* (`RESDEN.INHAB.TFTE`), located in `data/unesco_uis/data.csv`. Most recent available observations within **2019–2023** were selected independently per economy and indicator. Portal: [https://uis.unesco.org/](https://uis.unesco.org/)

3. **World Bank — World Development Indicators (WDI):**  
   - `NY.GDP.PCAP.PP.KD`: GDP per capita, PPP (constant 2021 international dollars) for reference year **2023** (`data/world_bank/GDP_per_capita_PPA/API_NY.GDP.PCAP.PP.KD_DS2_en_csv_v2_1629.csv`).
   - `SP.POP.TOTL`: Total population matched to each economy's researcher FTE reference year to compute total national researchers FTE (`data/world_bank/total_population/API_SP.POP.TOTL_DS2_en_csv_v2_5254.csv`).  
   Portal: [https://databank.worldbank.org/source/world-development-indicators](https://databank.worldbank.org/source/world-development-indicators)

4. **World Bank Country and Lending Groups (FY2026):**  
   Historical income classification workbook (`data/classifications/OGHIST_2026_10_08.xlsx`), using fiscal year 2026 (`FY26`) income categories (*Low income*, *Lower middle income*, *Upper middle income*, *High income*). Portal: [https://datahelpdesk.worldbank.org/knowledgebase/articles/906519-world-bank-country-and-lending-groups](https://datahelpdesk.worldbank.org/knowledgebase/articles/906519-world-bank-country-and-lending-groups)

5. **United Nations M49 Geographical Regions:**  
   Standard country/area codes and regional classifications obtained via the `countrycode` R package (v1.6.1). Portal: [https://unstats.un.org/unsd/methodology/m49/](https://unstats.un.org/unsd/methodology/m49/)

---

## 3. Running the Analysis

### System Requirements
- **R version:** R 4.4.2 (tested on Windows 11)
- **Required R packages:**

```r
install.packages(c(
  "readxl", "readr", "dplyr", "tidyr", "countrycode",
  "ggplot2", "MASS", "sandwich", "svglite"
))
```

### Execution
From the **repository root**, run:

```bash
Rscript src/code.R
```

Or inside an R / RStudio session with the working directory set to the repository root:

```r
source("src/code.R")
```

*(Optional)* You can also explicitly set the `PAPER1_ROOT` environment variable to the repository root path prior to running the script.

### Workflow Summary
`src/code.R` performs the following sequential steps without modifying any raw files in `data/`:
1. Verifies that each required data source pattern matches a single file under `data/` and records file sizes and MD5 checksums (`results/input_manifest.csv`).
2. Aggregates country-level author counts from the 2025 single-year and career-long Ioannidis databases and audits unassigned ISO3 records.
3. Integrates UNESCO UIS indicators, World Bank WDI indicators, FY2026 income classifications, and UN M49 regions into a 224-economy master dataset and country-year panel.
4. Constructs the analytical samples (Sample A: $n = 101$ economies; primary Sample B: $n = 98$ economies) and computes data coverage stratified by income group and UN region (`Supplementary_Table_S1.csv`).
5. Fits Poisson dispersion diagnostics and two nested negative binomial models with $\log(\text{FTE})$ as an offset and heteroskedasticity-consistent **HC3** standard errors (`Table_1_model_IRR.csv`, `Table_1_model_fit.csv`).
6. Computes national rankings across three representations — (i) absolute researcher counts, (ii) listed researchers per 10,000 national researchers FTE, and (iii) model-adjusted observed-to-expected (O/E) ratios (`Supplementary_Table_S2.csv`) — and evaluates pairwise rank concordance using Spearman's $\rho$ and Kendall's $\tau$ (`Table_2_rank_agreement.csv`).
7. Evaluates model-adjusted ranking stability across 500 nonparametric bootstrap resamples (`BOOT_SEED = 20261106L`; `Supplementary_Table_S3.csv`).
8. Runs sensitivity analyses restricting to economies with $\ge 1{,}000$ FTE ($n = 85$), testing alternative R&D reference windows (`2015–2023`, `2019–2023`, `2019–2024`, `2021–2023`), and conducting leave-one-country-out analyses (`Supplementary_Table_S4.csv`).
9. Generates publication figure panels in `figures/` and logs session metadata (`results/reproducibility_report.txt`, `results/sessionInfo.txt`).

---

## 4. Expected Analytical Checks & Key Results

The script enforces strict sample-size assertions to guarantee exact reproduction of the manuscript snapshot:

| Metric | Expected Study Output |
|---|---:|
| Annual database rows (2025 single-year) | 249,310 |
| Annual rows with valid ISO3 country code | 249,141 |
| Master dataset economies | 224 |
| Economies with R&D expenditure and FTE in 2019–2023 (Sample A) | 101 |
| Economies with additional 2023 PPP GDP per capita (Sample B) | 98 |
| Annual author records captured in Sample B | 215,130 (86.3%) |
| Economies with zero annual author records in Sample B | 5 |
| Valid bootstrap replicates (`BOOT_SEED = 20261106L`) | 472 of 500 (94.4%) |

### Summary of Principal Findings
- **Data availability (`Supplementary_Table_S1.csv`):** Complete indicators were available for 43.8% (98/224) of economies, with marked disparities across income groups (56.3% high-income vs. 16.0% low-income) and regions (82.6% Europe vs. 25.9% Africa and 5.0% Oceania).
- **Negative binomial regression (Table 1):**
  - *Model 1 (R&D % GDP + FTE offset):* R&D expenditure $\text{IRR} = 1.204$ (95% CI: $0.996\text{--}1.457$, $p = 0.055$), $\text{AIC} = 1298.03$.
  - *Model 2 (R&D % GDP + $\log_2(\text{GDP per capita PPP})$ + FTE offset):* R&D expenditure $\text{IRR} = 0.958$ (95% CI: $0.750\text{--}1.224$, $p = 0.732$); GDP per capita (per doubling) $\text{IRR} = 1.435$ (95% CI: $1.054\text{--}1.955$, $p = 0.022$), $\text{AIC} = 1278.98$ (likelihood-ratio $\chi^2 = 21.05$, $p = 4.47 \times 10^{-6}$).
- **Rank concordance (Table 2):**
  - *Absolute vs. FTE-normalized:* Spearman's $\rho = 0.608$, Kendall's $\tau = 0.428$, median shift = 14 positions, 35.7% (35/98) shifting $\ge 20$ positions.
  - *Absolute vs. Model-adjusted (O/E):* Spearman's $\rho = 0.504$, Kendall's $\tau = 0.365$, median shift = 15 positions, 38.8% (38/98) shifting $\ge 20$ positions.
  - *FTE-normalized vs. Model-adjusted (O/E):* Spearman's $\rho = 0.924$, Kendall's $\tau = 0.798$, median shift = 5 positions, 10.2% (10/98) shifting $\ge 20$ positions.

---

## 5. Supplementary Material Description

The pre-computed supplementary tables are located in `Supplementary Material/`:

- **`Supplementary_Table_S1.csv`**: Availability of national research and economic indicators across the 224-economy master dataset, stratified by World Bank FY2026 income group and UN M49 geographical region (12 summary rows).
- **`Supplementary_Table_S2.csv`**: Country-level dataset for all 98 economies in the primary analytical sample, including observed annual listed-author counts, estimated researcher FTE, listed authors per 10,000 FTE, model-predicted counts, observed-to-expected (O/E) ratios, reference years, and positions under all three ranking schemes (98 rows).
- **`Supplementary_Table_S3.csv`**: Nonparametric bootstrap rank stability summaries across 472 converged replicates (median rank, 5th–95th percentile rank intervals, interval widths, top-10 inclusion frequencies, and small-sample indicator flags for $<20$ listed authors or $<1{,}000$ FTE; 98 rows).
- **`Supplementary_Table_S4.csv`**: Complete sensitivity analysis results covering FTE denominator restriction ($\ge 1{,}000$ FTE, $n = 85$), four alternative R&D reference windows (`2015–2023`, `2019–2023`, `2019–2024`, `2021–2023`) for Models A and B, and leave-one-country-out diagnostics for influential economies (40 rows).

---

## 6. Methodological Notes & Interpretation Limits

- **Workforce denominator vs. publishing population:** National researchers in full-time equivalents (FTE) measure R&D labor input rather than the population of Scopus-indexed publishing authors. Workforce-normalized rates therefore represent concentration relative to national R&D personnel, not an individual probability of selection.
- **Model-dependent O/E ratios:** Observed-to-expected ratios depend on the specified parametric form and included covariates and should not be interpreted as direct measures of national scientific excellence.
- **Bootstrap scope:** The bootstrap procedure quantifies sensitivity of adjusted ranks to regression parameter re-estimation while holding observed author counts and national indicators fixed; it does not capture underlying survey error or bibliographic coverage bias.
- **Geographical selectivity:** Complete-case availability of R&D and macroeconomic indicators is uneven across income groups and regions, which must be accounted for when generalizing cross-national rankings.

---

## Citation

[![DOI](https://zenodo.org/badge/1448998565.svg)](https://doi.org/10.5281/zenodo.24027736)

If you use this code, data workflow, or supplementary material, please cite the accompanying manuscript, the archived Zenodo release, and the primary data sources (Ioannidis v9 2026, UNESCO UIS, and World Bank WDI):

> Acosta-Monterrosa AA. *How Robust Are National Rankings of Highly Cited Scientists? Research Capacity Adjustment and Data Availability* [Data set and code]. Zenodo; 2026. DOI: [https://doi.org/10.5281/zenodo.24027736](https://doi.org/10.5281/zenodo.24027736). GitHub repository: [https://github.com/AndyPaaai/global-scientific-inequality-research-capacity](https://github.com/AndyPaaai/global-scientific-inequality-research-capacity)

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details. Raw third-party datasets under `data/` remain subject to the respective terms of use of their original providers (Elsevier Data Repository / CC BY 4.0, UNESCO UIS, and World Bank CC BY 4.0).

