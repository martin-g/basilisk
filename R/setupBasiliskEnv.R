#' Set up \pkg{basilisk}-managed environments
#'
#' Set up a conda environment for isolated execution of Python code with appropriate versions of all Python packages.
#' 
#' @param envpath String containing the path to the environment to use. 
#' @param packages Character vector containing the names of conda packages to install into the environment.
#' Version numbers must be included.
#' @param channels Character vector containing the names of additional conda channels to search.
#' Defaults to the conda-forge repository.
#' @param pip Character vector containing the names of additional packages to install from PyPi using \code{pip}.
#' Version numbers must be included.
#' @param paths Character vector containing absolute paths to Python package directories, to be installed by \code{pip}.
#' 
#' @return 
#' A conda environment is created at \code{envpath} containing the specified \code{packages}.
#' A \code{NULL} is invisibly returned.
#'
#' @details
#' Developers of client packages should never need to call this function directly.
#' For typical usage, \code{setupBasiliskEnv} is automatically called by \code{\link{basiliskStart}} to perform lazy installation.
#' Developers should also create \code{configure(.win)} files to call \code{\link{configureBasiliskEnv}},
#' which will call \code{setupBasiliskEnv} during R package installation when \code{BASILISK_USE_SYSTEM_DIR=1}.
#'
#' Pinned version numbers must be present for all desired conda packages in \code{packages}.
#' This improves predictability and simplifies debugging across different systems.
#' Note that the version notation for conda packages uses a single \code{=}, while the notation for Python packages uses \code{==}; any instances of the latter will be coerced to the former automatically.
#'
#' It is possible to use the \code{pip} argument to install additional packages from PyPi after all the conda packages are installed.
#' All packages listed here are also expected to have pinned versions, this time using the \code{==} notation.
#' However, some caution is required when mixing packages from conda and pip,
#' see \url{https://www.anaconda.com/using-pip-in-a-conda-environment} for more details.
#'
#' It is further possible to install Python packages from directories.
#' In the package development context, this typically assumes that the Python directories are included in the \code{inst} subdirectory of the R package.
#' \code{\link{basiliskStart}} will then convert the relative path to an absolute path before calling this function - see \code{\link{BasiliskEnvironment}} for details.
#'
#' It is also good practice to explicitly list the versions of the \emph{dependencies} of all desired packages.
#' This protects against future changes in the behavior of your code if conda's solver decides to use a different version of a dependency.
#' To identify appropriate versions of dependencies, we suggest:
#' \enumerate{
#' \item Creating a fresh conda environment with the desired packages, using \code{packages=} in \code{setupBasiliskEnv}.
#' \item Calling \code{\link{listPackages}} on the environment to identify any relevant dependencies and their versions.
#' \item Including those dependencies in the \code{packages=} argument for future use.
#' (It is helpful to mark dependencies in some manner, e.g., with comments, to distinguish them from the actual desired packages.)
#' }
#' The only reason that pinned dependencies are not mandatory is because some dependencies are OS-specific,
#' requiring some manual pruning of the output of \code{\link{listPackages}}.
#'
#' If versions for the desired conda packages are not known beforehand, developers may use \code{\link{setBasiliskCheckVersions}(FALSE)} before running \code{setupBasiliskEnv}.
#' This instructs conda to create an environment with appropriate versions of all unpinned packages, 
#' which can then be read out via \code{\link{listPackages}} for insertion in the \code{packages=} argument as described above.
#' We stress that this option should \emph{not} be used in any release of the R package, it is a development-phase-only utility.
#'
#' If no Python version is listed, the version in the base conda installation is used by default - check \code{\link{listPythonVersion}} for the version number.
#' However, it is often prudent to explicitly list the desired version of Python in \code{packages}, even if this is already version-compatible with the default (e.g., \code{"python=3.8"}).
#' This protects against changes to the Python version in the base installation, e.g., if administrators override the choice of conda installation with certain environment variables.
#' Of course, it is possible to specify an entirely different version of Python in \code{packages} by supplying, e.g., \code{"python=2.7.10"}.
#'
#' @examples
#' \dontshow{basilisk.utils::installConda()}
#'
#' tmploc <- file.path(tempdir(), "my_package_A")
#' if (!file.exists(tmploc)) {
#'     setupBasiliskEnv(tmploc, c('pandas=1.4.3'))
#' }
#'
#' @seealso
#' \code{\link{listPackages}}, to list the packages in the conda environment.
#'
#' @export
#' @importFrom reticulate conda_install
setupBasiliskEnv <- function(envpath, packages, channels="conda-forge", pip=NULL, paths=NULL) {
    packages <- sub("==", "=", packages)
    .check_versions(packages, "[^=<>]=[0-9]")

    previous <- activateEnvironment()
    on.exit(deactivateEnvironment(previous))

    base.dir <- getCondaDir()
    conda.cmd <- getCondaBinary(base.dir)

    # Determining the Python version to use (possibly from `packages=`).
    if (any(is.py <- grepl("^python=", packages))) {
        version <- sub("^python=+", "", packages[is.py][1])
    } else {
        version <- .python_version(base.dir)
    }

    success <- FALSE
    unlink2(envpath)
    dir.create2(envpath)
    on.exit(if (!success) unlink2(envpath), add=TRUE, after=FALSE)
    
    conda_install(envname=normalizePath(envpath), conda=conda.cmd, 
        python_version=version, packages=packages, channel=channels)

    if (length(pip)) {
        .check_versions(pip, "==")
        env.py <- getPythonBinary(envpath)
        result <- system2(env.py, c("-m", "pip", "install", pip))
        if (result!=0L) {
            stop("failed to install additional packages via pip")
        }
    }

    if (length(paths)) {
        env.py <- getPythonBinary(envpath)
        for (p in paths) {
            result <- system2(env.py, c("-m", "pip", "install", p))
        }
    }

    success <- TRUE
    invisible(NULL)
}

.check_versions <- function(packages, pattern) {
    if (getBasiliskCheckVersions()) {
        if (any(failed <- !grepl(pattern, packages))) {
            stop(paste("versions must be explicitly specified for",
                paste(sprintf("'%s'", packages[failed]), collapse=", ")))
        }
    }
}
