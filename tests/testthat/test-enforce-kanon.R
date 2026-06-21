pkgload::load_all(".", quiet = TRUE, export_all = TRUE)

test_that("coarsen_geography truncates postal/zip-like codes by one level", {
  x <- c("M5V 3A8", "M5V 2T6", "90210", "90213")
  out1 <- coarsen_geography(x, level = 1)
  expect_equal(out1, c("M5V3A", "M5V2T", "9021", "9021"))

  out2 <- coarsen_geography(x, level = 2)
  expect_equal(out2, c("M5V3", "M5V2", "902", "902"))
})
