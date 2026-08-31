local({
  batch_fixture <- function() {
    data <- data.frame(
      amount = seq(100.123456, 139.123456, by = 1),
      offset = seq(400.654321, 439.654321, by = 1),
      group = rep(c("north", "south"), 20),
      flag = rep(c(TRUE, FALSE), 20),
      stringsAsFactors = FALSE
    )
    roles <- detect_roles(data)
    roles$simulation <- "synthesize"
    roles$identifies <- "none"
    roles$sensitive <- FALSE
    roles$user_identifies <- NA_character_
    roles$user_sensitive <- NA
    roles$user_role <- NA_character_
    roles$disclosure_role <- "none"
    frozen <- freeze_synthesis(
      data,
      synth_spec("demo", engine = "internal", k_anon = 2L),
      roles,
      allowed = generation_limits(
        seed = c(1L, 1000L), n = c(20L, 100L), datasets = c(1L, 4L)
      ),
      store = tempfile("dataganger-private-store-")
    )
    approve_generator(frozen, approver = "Jax")
    frozen
  }

  test_that("one dataset stays simple and multiple datasets form an auditable batch", {
    frozen <- batch_fixture()
    one <- generate_synthetic(frozen, seed = 42L, n = 40L)
    many <- generate_synthetic(frozen, seed = 42L, n = 40L, datasets = 3L)

    expect_s3_class(one, "dataganger_synthetic")
    expect_false(inherits(one, "dataganger_batch"))
    expect_s3_class(many, "dataganger_batch")
    expect_length(many, 3L)
    expect_s3_class(many[[1L]], "dataganger_synthetic")
    expect_identical(nrow(many[[1L]]), 40L)
    expect_identical(many$seeds, many$provenance$seed)
    expect_length(unique(many$seeds), 3L)
    expect_named(
      many$provenance,
      c(
        "dataset", "seed", "n", "output_hash", "hash_algorithm",
        "receipt_id", "request_receipt_id", "privacy_ok", "exact_match_count",
        "suppressed_cells", "suppressed_rows", "suppressed_row_frac",
        "kanon_infeasible"
      )
    )
    expect_identical(many$provenance$dataset, 1:3)
    expect_identical(nchar(many$provenance$output_hash), rep(64L, 3L))
    expect_identical(nchar(many$provenance$receipt_id), rep(64L, 3L))
    expect_length(unique(many$provenance$receipt_id), 3L)
    expect_identical(many$provenance$privacy_ok, rep(TRUE, 3L))
    expect_true(is.list(attr(many[[1L]], "generation_privacy")))
    expect_s3_class(generation_receipt(many[[1L]]), "dataganger_generation_receipt")
  })

  test_that("batch indexing and repeated generation preserve deterministic outputs", {
    frozen <- batch_fixture()
    first <- generate_synthetic(frozen, seed = 17L, n = 40L, datasets = 3L)
    second <- generate_synthetic(frozen, seed = 17L, n = 40L, datasets = 3L)

    expect_identical(first$seeds, second$seeds)
    expect_identical(generator_data_hash(first[[1L]]), generator_data_hash(second[[1L]]))
    expect_identical(generator_data_hash(first[[3L]]), generator_data_hash(second[[3L]]))
    expect_identical(as.list(first), first$datasets)
    expect_identical(first[1L][[1L]], first[[1L]])
    expect_error(first[[0L]])
    expect_error(first[[4L]])
    expect_length(first[0L], 0L)
    expect_identical(first[c(3L, 1L, 1L)]$seeds, first$seeds[c(3L, 1L, 1L)])
    expect_identical(first[-2L]$seeds, first$seeds[c(1L, 3L)])
    expect_error(first[c(-1L, 2L)])
    expect_error(first[c(1L, NA_integer_)])
    expect_error(first[4L])
    expect_error(first[c(TRUE, FALSE)])
    expect_length(first[FALSE], 0L)
    expect_s3_class(generation_receipt(first[1L][[1L]]),
      "dataganger_generation_receipt")
  })

  test_that("summary and print expose bounded batch provenance", {
    frozen <- batch_fixture()
    batch <- generate_synthetic(frozen, seed = 21L, n = 40L, datasets = 2L)
    info <- summary(batch)

    expect_s3_class(info, "summary_dataganger_batch")
    expect_identical(info$datasets, 2L)
    expect_identical(info$contract_id, frozen$contract_id)
    expect_output(print(batch), "DataGangeR synthetic batch")
    expect_output(print(info), "datasets: 2")
  })
})
