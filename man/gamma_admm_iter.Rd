% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/admm.R
\name{gamma_admm_iter}
\alias{gamma_admm_iter}
\title{Iteration for admm algorithm for two-way fixed effects}
\usage{
gamma_admm_iter(
  e,
  vec,
  est,
  W,
  Year,
  Group,
  tune,
  nu,
  J_levels,
  T_levels,
  err_g_thresh
)
}
\arguments{
\item{est}{previous estimate of Gamma}

\item{W}{matrix or data.table of sqrt(N) by group}

\item{Year}{vector of year assignments}

\item{Group}{vector of group assignments}

\item{tune}{tuning parameter for updates}

\item{nu}{Penalization parameter used in optimization}

\item{J_levels}{factor representing levels of grouping variable, unused here}

\item{T_levels}{factor representing levels of grouping variable, unused here}

\item{err_g_thresh}{threshold for convergence of gamma updates}

\item{DT}{data.table with all the model info}
}
\description{
Iteration for admm algorithm for two-way fixed effects
}
