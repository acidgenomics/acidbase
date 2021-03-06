#' Compress or decompress a file
#'
#' Compress or decompress using gzip, bzip2, or xz compression.
#'
#' @name compress
#' @export
#' @note For ZIP files, refer to `zip` and `unzip` in the utils package.
#' @note Updated 2021-01-06.
#'
#' @inheritParams AcidRoxygen::params
#' @param ext `character(1)`.
#'   Compression file format extension.
#'   Uses [`match.arg()`][base::match.arg] internally and defaults to the first
#'   argument in the `character` vector.
#'
#'   Supported formats:
#'   - `gz`: gzip compression;
#'     calls [`gzfile()`][base::gzfile] internally.
#'   - `bz`: bzip2 (lzma) compression;
#'     calls [`bzfile()`][base::bzfile] internally.
#'   - `xz`: xz compression;
#'     calls [`xzfile()`][base::xzfile] internally.
#'   - `zip`: zip compression;
#'     calls [`zip()`][utils::zip] or [`unzip()`][utils::unzip] internally.
#' @param remove `logical(1)`.
#'   Remove the input file once the output file is fully created and the
#'   connection is closed.
#'
#' @seealso
#' - `help("connections")`
#' - `R.utils::compressFile`, `R.utils::decompressFile`.
#' - `utils::zip`, `utils::unzip`.
#' - `utils::tar`, `utils::untar`.
#' - `memCompress`, `memDecompress`.
#'
#' @examples
#' ## Create an example text file.
#' text <- c("hello", "world")
#' file <- "test.txt"
#' writeLines(text = text, con = file)
#' readLines(con = file)
#'
#' ## Apply gzip compression.
#' gzfile <- compress(file = file, ext = "gz", remove = TRUE, overwrite = TRUE)
#' gzfile
#' readLines(con = gzfile)
#' ## When `remove = TRUE`, the original input file will be removed.
#' file.exists(file)
#'
#' ## Decompress the gzipped file.
#' file <- decompress(file = gzfile, remove = TRUE, overwrite = TRUE)
#' file
#'
#' unlink(file)
NULL



## Modified version of:
## > getS3method(
## >     f = "compressFile",
## >     class = "default",
## >     envir = asNamespace("R.utils")
## > )

#' @rdname compress
#' @export
compress <- function(
    file,
    ext = c("gz", "bz2", "xz", "zip"),
    remove,
    overwrite
) {
    assert(
        isString(file),
        isFlag(remove),
        isFlag(overwrite)
    )
    file <- realpath(file)
    ext <- match.arg(ext)
    destfile <- sprintf("%s.%s", file, ext)
    assert(!identical(file, destfile))
    if (isAFile(destfile)) {
        ## nocov start
        if (isTRUE(overwrite)) {
            alertWarning(sprintf("Overwriting file: {.file %s}.", destfile))
            file.remove(destfile)
        } else {
            stop(sprintf("File exists: '%s'.", destfile))
        }
        ## nocov end
    }
    whatFun <- switch(
        EXPR = ext,
        bz2 = "bzfile",
        gz = "gzfile",
        xz = "xzfile"
    )
    ## For ZIP files, hand off to `utils::zip()` and early return.
    if (identical(ext, "zip")) {
        zip(zipfile = destfile, files = basename(file))
        if (isTRUE(remove)) {
            file.remove(file)
        }
        return(invisible(destfile))
    }
    fun <- get(
        x = whatFun,
        envir = asNamespace("base"),
        mode = "function",
        inherits = FALSE
    )
    assert(is.function(fun))
    inn <- file(description = file, open = "rb")
    on.exit(if (!is.null(inn)) close(inn))
    outComplete <- FALSE
    out <- fun(description = destfile, open = "wb")
    on.exit({
        ## nocov start
        if (!is.null(out)) close(out)
        if (!isTRUE(outComplete)) file.remove(destfile)
        ## nocov end
    }, add = TRUE)
    ## Don't keep as integer here, otherwise can hit integer overflow
    ## on large files.
    nbytes <- as.numeric(0L)
    repeat {
        bfr <- readBin(
            con = inn,
            what = raw(0L),
            size = 1L,
            ## See 'BFR.SIZE' in `R.utils::compressFile`.
            n = 1e+07L
        )
        n <- length(bfr)
        if (n == 0L) break
        nbytes <- nbytes + n
        writeBin(bfr, con = out, size = 1L)
        bfr <- NULL
    }
    outComplete <- TRUE
    close(out)
    out <- NULL
    attr(destfile, "bytes") <- nbytes
    if (isTRUE(remove)) {
        close(inn)
        inn <- NULL
        file.remove(file)
    }
    invisible(destfile)
}

formals(compress)[c("remove", "overwrite")] <-
    formalsList[c(
        "compress.remove",
        "overwrite"
    )]



## Modified version of:
## > getS3method(
## >     f = "decompressFile",
## >     class = "default",
## >     envir = asNamespace("R.utils")
## > )
##
## Note that `gunzip`, etc. are wrappers of `decompressFile`:
## > getS3method(
## >     f = "gunzip",
## >     class = "default",
## >     envir = asNamespace("R.utils")
## > )

#' @rdname compress
#' @export
decompress <- function(
    file,
    remove,
    overwrite
) {
    assert(
        isString(file),
        isFlag(remove),
        isFlag(overwrite)
    )
    file <- realpath(file)
    assert(isTRUE(grepl(pattern = compressExtPattern, x = file)))
    ext <- substring(
        text = file,
        first = regexpr(
            pattern = compressExtPattern,
            text = file,
            ignore.case = TRUE
        ) + 1L
    )
    destfile <- gsub(
        pattern = sprintf("[.]%s$", ext),
        replacement = "",
        x = file,
        ignore.case = TRUE
    )
    assert(!identical(file, destfile))
    if (isAFile(destfile)) {
        ## nocov start
        if (isTRUE(overwrite)) {
            file.remove(destfile)
        }
        else {
            stop(sprintf("File exists: '%s'.", destfile))
        }
        ## nocov end
    }
    ## For ZIP files, hand off to `utils::unzip()` and early return.
    if (identical(ext, "zip")) {
        destfile <- unzip(
            zipfile = file,
            files = NULL,
            list = FALSE,
            overwrite = overwrite,
            junkpaths = FALSE,
            exdir = ".",
            unzip = "internal",
            setTimes = FALSE
        )
        if (length(destfile) > 1L) {
            ## nocov start
            alertWarning(sprintf(
                "{.var %s} contains multiple files.",
                basename(file)
            ))
            ## nocov end
        }
        if (isTRUE(remove)) {
            file.remove(file)
        }
        destfile <- realpath(destfile)
        return(invisible(destfile))
    }
    whatFun <- switch(
        EXPR = ext,
        bz2 = "bzfile",
        gz = "gzfile",
        xz = "xzfile"
    )
    fun <- get(
        x = whatFun,
        envir = asNamespace("base"),
        mode = "function",
        inherits = FALSE
    )
    assert(is.function(fun))
    inn <- fun(file, open = "rb")
    on.exit(if (!is.null(inn)) close(inn))
    outComplete <- FALSE
    out <- file(destfile, open = "wb")
    on.exit({
        ## nocov start
        if (!is.null(out)) close(out)
        if (!outComplete) file.remove(destfile)
        ## nocov end
    }, add = TRUE)
    ## Don't keep as integer here, otherwise can hit integer overflow
    ## on large files.
    nbytes <- as.numeric(0L)
    repeat {
        bfr <- readBin(
            con = inn,
            what = raw(0L),
            size = 1L,
            ## See 'BFR.SIZE' in `R.utils::decompressFile`.
            n = 1e+07L
        )
        n <- length(bfr)
        if (n == 0L) break
        nbytes <- nbytes + n
        writeBin(bfr, con = out, size = 1L)
        bfr <- NULL
    }
    outComplete <- TRUE
    close(out)
    out <- NULL
    attr(destfile, "bytes") <- nbytes
    if (remove) {
        close(inn)
        inn <- NULL
        file.remove(file)
    }
    invisible(destfile)
}

formals(decompress)[c("remove", "overwrite")] <-
    formalsList[c(
        "decompress.remove",
        "overwrite"
    )]
