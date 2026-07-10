# Read a data file into a tibble

Reads CSV, Excel (`.xlsx`, `.xls`), SAS (`.sas7bdat`), and XPT (`.xpt`)
files into a tibble. Dispatches on file extension.

## Usage

``` r
read_input(file, sheet = NULL, encoding = NULL, ...)
```

## Arguments

- file:

  Path to the data file.

- sheet:

  For Excel files, the sheet name or index to read. Passed to
  [`readxl::read_excel()`](https://readxl.tidyverse.org/reference/read_excel.html).
  Ignored for non-Excel formats.

- encoding:

  Character encoding for CSV files (e.g. `"UTF-8"`, `"latin1"`). Passed
  as `readr::locale(encoding = encoding)`. Ignored when reading non-CSV
  formats or when the caller already supplies a `locale` argument in
  `...`.

- ...:

  Additional arguments passed to the underlying reader
  ([`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html),
  [`readxl::read_excel()`](https://readxl.tidyverse.org/reference/read_excel.html),
  [`haven::read_sas()`](https://haven.tidyverse.org/reference/read_sas.html),
  or
  [`haven::read_xpt()`](https://haven.tidyverse.org/reference/read_xpt.html)).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html).
SAS/XPT imports preserve `haven_labelled` vectors as-is.

## Examples

``` r
path <- tempfile(fileext = ".csv")
readr::write_csv(data.frame(id = 1:3, grp = c("a", "b", "c")), path)
read_input(path)
#> # A tibble: 3 × 2
#>      id grp  
#>   <dbl> <chr>
#> 1     1 a    
#> 2     2 b    
#> 3     3 c    
```
