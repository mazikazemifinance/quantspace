#' Sparse Regression Quantile Fitting with Weights
#' @details A wrapper around the rq.fit.sfn function from the quantreg package,
#' extended to allow for  a user-supplied starting value and weights
#' @importFrom quantreg  rq.fit.sfn
#' @param a structure of the design matrix X stored in csr format
#' @param y outcome vector
#' @param tau desired quantile
#' @param rhs the right-hand-side of the dual problem; regular users shouldn't need to specify this,
#' but in special cases can be quite usefully altered to meet special needs.
#' See e.g. Section 6.8 of Koenker (2005).
#' @param control control parameters for fitting routines: see [quantreg::sfn.control()]
#' @param weight_vec Optional vector of weights for regression
rq.fit.sfn_start_val <- function(a,y,tau=.5,
                                 rhs = (1-tau)*c(t(a) %*% rep(1,length(y))),
                                 control,
                                 sv,
                                 weight_vec = NULL)
{
  y <- -y
  n <- length(y)
  m <- a@dimension[2]
  if(n != a@dimension[1])
    stop("Dimensions of design matrix and the response vector not compatible")

  # additional syntax to incorporate weights is included here
  if (!is.null(weight_vec)){
    if(n != dim(as.matrix(weight_vec))[1]){
      stop("Dimensions of design matrix and the weight vector not compatible")
    }
    # multiplying y by the weights
    y <- y * weight_vec

    # pre-multiplying the a matrix by a diagonal matrix of weights
    #a <- sweep(a,MARGIN=1,weight_vec,`*`)
    a <- as(as.vector(weight_vec), "matrix.diag.csr") %*% a
  }

  u <- rep(1,length=n)
  x <- rep((1-tau),length=n)
  nnzdmax <- nnza <- a@ia[n+1]-1
  iwmax <- 7*m+3
  ao <- t(a)
  e <- ao %*% a
  nnzemax <- e@ia[m+1]-1
  ctrl <- sfn.control()
  if (!missing(control)) {
    control <- as.list(control)
    ctrl[names(control)] <- control
  }
  nsubmax <- ctrl$nsubmax
  tmpmax <- ctrl$tmpmax
  nnzlmax <- ctrl$nnzlmax
  if (is.null(ctrl$nsubmax)) nsubmax <- nnzemax
  if (is.null(ctrl$tmpmax)) tmpmax <- 6 * m
  if (is.null(ctrl$nnzlmax)) nnzlmax <- 4 * nnzdmax
  wwm <- vector("numeric",3*m)
  s <- u - x
  if(missing(sv)){
    b1 <- solve(e, ao %*% y, tmpmax=tmpmax,nnzlmax=nnzlmax,nsubmax=nsubmax)
  }
  else {
    # note: LDWS flipped the sign here, since formula above yields OLS coeff * -1
    b1 = -sv
  }

  r <- y - a %*% b1
  z <- ifelse(abs(r)<ctrl$small,(r*(r>0)+ctrl$small),r*(r>0))
  w <- z - r
  wwn <- matrix(0,n,14)
  wwn[,1] <- r
  wwn[,2] <- z
  wwn[,3] <- w
  fit <- .Fortran("srqfn",
                  n = as.integer(n),
                  m = as.integer(m),
                  nnza = as.integer(nnza),
                  a = as.double(a@ra),
                  ja = as.integer(a@ja),
                  ia = as.integer(a@ia),
                  ao = as.double(ao@ra),
                  jao = as.integer(ao@ja),
                  iao = as.integer(ao@ia),
                  nnzdmax = as.integer(nnzdmax),
                  d = double(nnzdmax),
                  jd = integer(nnzdmax),
                  id = integer(m+1),
                  dsub = double(nnzemax+1),
                  jdsub = integer(nnzemax+1),
                  nnzemax = as.integer(nnzemax),
                  e = as.double(e@ra),
                  je = as.integer(e@ja),
                  ie = as.integer(e@ia),
                  nsubmax = as.integer(nsubmax),
                  lindx = integer(nsubmax),
                  xlindx = integer(m+1),
                  nnzlmax = as.integer(nnzlmax),
                  lnz = double(nnzlmax),
                  xlnz = integer(m+1),
                  iw = integer(m*5),
                  iwmax = as.integer(iwmax),
                  iwork = integer(iwmax),
                  xsuper = integer(m+1),
                  tmpmax = as.integer(tmpmax),
                  tmpvec = double(tmpmax),
                  wwm = as.double(wwm),
                  wwn = as.double(wwn),
                  cachsz = as.integer(ctrl$cachsz),
                  level = as.integer( 8 ),
                  x = as.double(x),
                  s = as.double(s),
                  u = as.double(u),
                  c = as.double(y),
                  sol = as.double(b1),
                  rhs = as.double(rhs),
                  small = as.double(ctrl$small),
                  ierr = integer(1),
                  maxiter = as.integer(ctrl$maxiter),
                  time = double(7),
                  PACKAGE = "quantreg")[c("sol","ierr",
                                          "maxiter","time")]
  ierr <- fit$ierr
  if(!(ierr==0) && ctrl$warn.mesg)
    warning(sfnMessage(ierr))
  coefficients <- -fit$sol

  residuals <- -y - a %*% coefficients
  if (!is.null(weight_vec)){
    residuals <- residuals / weight_vec
  }

  list(coefficients = coefficients,
       residuals = residuals,
       control = ctrl,
       ierr = ierr,
       it = fit$maxiter,
       weight_vec = weight_vec)
}

#' Runs quantile regression on residuals of the model (calculates spaces around jstar quantile)
#' @param reg_spec_data result of ensureSpecRank function; regression matrix with full rank
#' @param ehat current residuals; subset of which to be used as dependent column
#' @param ind_hat column vector indicating which rows to be used in quantile regression
#' @param tau estimated quantile
#' @param trunc Boolean value; if true, replace those dependent values less than small with small itself;
#' else, only use rows with residuals greater than small
#' @param small Value used with trunc; values less than small 'blow up' too greatly when logged
#' @param sv starting values (can be NA's) to be passed to sfn_start_val function
#' @param control control list to be passed to sfn_start_val function
#' @param weight_vec vector of optional weights
#' @return List of estimated coefficients, warnings, iterations, and controls as in
#' standard quantile regression function
#' @export
quantRegress = function(reg_spec_data,
                        ehat,
                        sv,
                        ind_hat,
                        tau,
                        trunc,
                        small,
                        control,
                        weight_vec = NULL) {
  if (trunc) {
    if (!is.null(weight_vec)){
      weight_vec = as.matrix(weight_vec[ind_hat])
    }

    j_model <- rq.fit.sfn_start_val(
      a = reg_spec_data$spec_matrix,
      y = log(pmax(ehat[ind_hat],small)),
      tau = tau,
      sv = sv,
      control = control,
      weight_vec = weight_vec) # Model the quantile
  }
  else {
    resids = ehat[ind_hat]

    if (!is.null(weight_vec)){
      weight_vec = as.matrix(weight_vec[ind_hat])
      weight_vec = weight_vec[resids > small]
    }
    if(dim(reg_spec_data$spec_matrix)[1] == sum(resids > small)) {
      # if the dimensions already match, then we assume that the matrix
      # was already spliced for the correct rows outside of the function
      j_model <- rq.fit.sfn_start_val(
        a = reg_spec_data$spec_matrix,
        y = log(resids[resids > small]),
        tau = tau,
        sv = sv,
        control = control,
        weight_vec = weight_vec) # Model the quantile
    }
    else{
      # else, we splice the correct rows here
      j_model <- rq.fit.sfn_start_val(
        a = reg_spec_data$spec_matrix[resids > small,],
        y = log(resids[resids > small]),
        tau = tau,
        sv = sv,
        control = control,
        weight_vec = weight_vec) # Model the quantile
    }
  }
  return(j_model)
}


#' Computes coefficients for the quantile regression spacing method.
#' @param dep_col Column of response variable.
#' @param data Regression specification matrix.
#' @param var_names RHS regression variable names.
#' @param alpha Quantiles to be estimated.
#' @param jstar First quantile to be estimated (usually the center one)
#' @param p Length of alpha.
#' @param small Minimum size of residuals for computational accuracy.
#' @param trunc Boolean value; if true, replace those dependent values less than small with small itself;
#' else, only use rows with residuals greater than small
#' @param start_list Starting values for regression optimization.
#' @param weight_vec vector of optional weights
#' @return
#' Returns a list of coefficients.
#' num_betas is an x by p matrix of estimated parameters for each supplied quantiles.
#' pseudo_r is a  1 by p matrix of psuedo R^2 values for each quantile estimate.
#' warnings is a 1 by p matrix of warnings produced by each quantile regression call.
#' iter: is a 1 by p matrix of iterations ran by each quantile regression call.
#' @export
quantRegSpacing = function(
  dep_col,
  data,
  var_names,
  alpha,
  jstar,
  small = 1e-3,
  trunc = FALSE,
  start_list,
  weight_vec = NULL) {

  width = dim(data)[2]
  tau = alpha[jstar]
  p = length(alpha)

  #create logs for output
  count_log = list()
  length(count_log) = p
  warnings_log = list()
  length(warnings_log) = p
  iter_log = list()
  length(iter_log) = p
  pseudo_r = list()
  length(pseudo_r) = p
  model = list() # Collect the quantile regressions into a list
  length(model) = p

  # check to see if regression matrix is sparse. If not, then turn into CSR matrix
  if(!is(data, 'matrix.csr')) data = denseMatrixToSparse(data)

  tmpmax <- floor(1e5 + exp(-12.1)*(data@ia[width+1]-1)^2.35)

  # Ensure matrix is not rank deficient
  reg_spec_starting_data <- ensureSpecFullRank(spec_mat = data, col_names = var_names)

  # Calculate initial fit
  ##print(jstar)
  ptm <- proc.time()
  if(!missing(start_list)){
    col_nums = getColNums(start_list, reg_spec_starting_data, alpha, jstar)
    sv = as.numeric(start_list[col_nums])
    star_model = rq.fit.sfn_start_val(
      a = reg_spec_starting_data$spec_matrix,
      y = dep_col,
      tau = tau,
      control = list(tmpmax= tmpmax),
      sv = sv,
      weight_vec = weight_vec)
  }
  else{
    star_model = rq.fit.sfn_start_val(
      a = reg_spec_starting_data$spec_matrix,
      y = dep_col,
      tau = tau,
      control = list(tmpmax= tmpmax),
      weight_vec = weight_vec)
  }
  ##printWarnings(star_model)

  ehat0 = star_model$residuals

  #Calculate R^2
  V <- sum(rho(u = ehat0, tau = tau, weight_vec = weight_vec))
  V0 <- rq.fit.sfn_start_val(a = as.matrix.csr(rep(1, length(dep_col))),
                             y = dep_col,
                             tau = tau,
                             weight_vec = weight_vec)$residuals
  V0 <- sum(rho(u = V0, tau = tau,weight_vec = weight_vec))

  ##print(paste('Pseudo-R^2 Value of', (1 - V/V0), 'for', alpha[jstar], 'quantile'))
  ##print(proc.time() - ptm)

  #set column names
  coef_df <- as.data.frame(t(star_model$coefficients))
  colnames(coef_df) <- reg_spec_starting_data$var_names
  coef_df <- addMissingSpecColumns(
    coef_df,
    var_names)
  colnames(coef_df) <- paste(alpha[jstar], colnames(coef_df), sep="_")

  #log output for return
  pseudo_r[[jstar]] = (1 - V/V0)
  model[[jstar]] = coef_df
  warnings_log[[jstar]] = star_model$ierr
  iter_log[[jstar]] = star_model$it
  count_log[[jstar]] = dim(reg_spec_starting_data$spec_matrix)[1]

  rm(star_model)

  # Estimate upper quantiles sequentially
  ehat = ehat0
  for (j in (jstar+1):p) {
    ind_hat = which(ehat > 0)

    # Determine quantile to estimate
    tau.t = (alpha[j] - alpha[j-1])/(1 - alpha[j-1])

    # Ensure the cut of the starting data that we take for
    # current spacing is not rank-deficient
    if(!trunc) reg_spec_data <- ensureSpecFullRank(spec_mat = reg_spec_starting_data$spec_matrix[which(ehat > small),],
                                                   col_names = reg_spec_starting_data$var_names)
    # else, handle rank specification for typically-sized matrix
    else reg_spec_data <- ensureSpecFullRank(spec_mat = reg_spec_starting_data$spec_matrix[ind_hat,],
                                             col_names = reg_spec_starting_data$var_names)

    #run quantile regression
    coef <- NULL
    ##print(j)
    ptm <- proc.time()
    if(!missing(start_list)){
      col_nums = getColNums(start_list, reg_spec_data, alpha, j)
      sv = as.numeric(start_list[col_nums])
      j_model <- quantRegress(reg_spec_data = reg_spec_data, ehat = ehat,
                              sv = sv, ind_hat = ind_hat, tau = tau.t, trunc = trunc,
                              small = small, control = list(tmpmax = tmpmax), weight_vec = weight_vec)
    }
    else{
      j_model <- quantRegress(reg_spec_data = reg_spec_data, ehat = ehat,
                              ind_hat = ind_hat, tau = tau.t, trunc =  trunc,
                              small = small, control = list(tmpmax = tmpmax), weight_vec = weight_vec)
    }
    #printWarnings(j_model)

    #Calculate R^2
    V <- sum(rho( u = j_model$residuals, tau = tau.t, weight_vec = j_model$weight_vec))
    V0 <- quantRegress(reg_spec_data = list('spec_matrix' = as.matrix.csr(rep(1, length(ind_hat)))),
                       ehat = ehat, ind_hat = ind_hat, tau = tau.t, trunc = trunc,
                       small = small, weight_vec = weight_vec)
    V0 <- sum(rho(u = V0$residuals, tau = tau.t, weight_vec = V0$weight_vec))
    #print(paste('Pseudo-R^2 Value of', (1 - V/V0), 'for', alpha[j], 'quantile'))
    #print(proc.time() - ptm)

    # Update residuals
    coef = j_model$coefficients
    coef_df <- as.data.frame(t(coef))


    #get column names
    colnames(coef_df) <- reg_spec_data$var_names
    coef_df <- addMissingSpecColumns(
      coef_df,
      var_names)
    colnames(coef_df) <- paste(alpha[j], colnames(coef_df), sep="_")

    #log results
    model[[j]] = coef_df
    pseudo_r[[j]] = (1 - V/V0)
    warnings_log[[j]] = j_model$ierr
    iter_log[[j]] = j_model$it
    count_log[[j]] = dim(reg_spec_data$spec_matrix)[1]

    # Update residuals
    ehat = ehat - exp(
      as.matrix(
        data %*%
          unname(t(as.matrix(model[[j]])))))

  }

  # Estimate lower quantiles sequentially
  ehat = ehat0
  for (j in (jstar-1):1) {
    ind_hat = which(ehat < 0)

    # Determine quantile to estimate
    tau.t = (alpha[j + 1] - alpha[j])/(alpha[j + 1])

    # Ensure the cut of the starting data that we take for
    # current spacing is not rank-deficient
    # if truncating, then ensure exact rows of the regression matrix is included
    if(!trunc) reg_spec_data <- ensureSpecFullRank(spec_mat = reg_spec_starting_data$spec_matrix[which(-ehat > small),],
                                                   col_names = reg_spec_starting_data$var_names)
    # else, handle rank specification for typically-sized matrix
    else reg_spec_data <- ensureSpecFullRank(spec_mat = reg_spec_starting_data$spec_matrix[ind_hat,],
                                             col_names = reg_spec_starting_data$var_names)
    #run quantile regression

    coef <- NULL
    #print(j)
    ptm <- proc.time()
    if(!missing(start_list)){
      col_nums = getColNums(start_list, reg_spec_data, alpha, j)
      sv = as.numeric(start_list[col_nums])
      j_model <- quantRegress(reg_spec_data = reg_spec_data,
                              ehat = -ehat,
                              sv = sv,
                              ind_hat = ind_hat,
                              tau = tau.t, trunc = trunc, small = small,
                              control = list(tmpmax = tmpmax),
                              weight_vec = weight_vec)
    }
    else{
      j_model <- quantRegress(reg_spec_data = reg_spec_data,
                              ehat = -ehat,
                              ind_hat = ind_hat,
                              tau = tau.t, trunc = trunc, small = small,
                              control = list(tmpmax = tmpmax),
                              weight_vec = weight_vec)
    }

    #printWarnings(j_model)

    #Calculate pseudo-R^2
    V <- sum(rho(u = j_model$residuals, tau = tau.t, weight_vec = j_model$weight_vec))
    V0 <- quantRegress(reg_spec_data = list('spec_matrix' = as.matrix.csr(rep(1, length(ind_hat)))),
                       ehat = -ehat, ind_hat = ind_hat, tau = tau.t, trunc = trunc,
                       small = small, weight_vec = weight_vec)
    V0 <- sum(rho(u = V0$residuals, tau = tau.t, weight_vec = V0$weight_vec))
    ##print(paste('Pseudo-R^2 Value of', (1 - V/V0), 'for', alpha[j], 'quantile'))
    ##print(proc.time() - ptm)

    # Update residuals
    coef = j_model$coefficients
    coef_df <- as.data.frame(t(coef))

    #get column names
    colnames(coef_df) <- reg_spec_data$var_names
    coef_df <- addMissingSpecColumns(
      coef_df,
      var_names)
    colnames(coef_df) <- paste(alpha[j], colnames(coef_df), sep="_")

    #log results
    model[[j]] = coef_df
    pseudo_r[[j]] = (1 - V/V0)
    warnings_log[[j]] = j_model$ierr
    iter_log[[j]] = j_model$it
    count_log[[j]] = dim(reg_spec_data$spec_matrix)[1]

    # Update residuals
    ehat = ehat + exp(as.matrix(
      data %*%
        unname(t(as.matrix(model[[j]])))))
  }

  return(list('coef' = do.call(cbind, model),
              'pseudo_r' = do.call(cbind, pseudo_r),
              'warnings' = do.call(cbind, warnings_log),
              'iter' = do.call(cbind, iter_log),
              'counts' = do.call(cbind, count_log)))
}


#' Compute quantiles given parameter coefficients and data
#' @param spacingCoef J by p matrix; row is number of variables, p is number of quantiles
#' @param data independent variables
#' @param jstar index of median quantiles
#' @return N by p matrix of quantiles
#' @export
spacingsToQuantiles <- function(spacingCoef, data, jstar) {

  p = dim(spacingCoef)[2]
  quantiles = matrix(NA, nrow = dim(data)[1], ncol = p)

  starResids = data %*% spacingCoef[,jstar]
  quantiles[,jstar] = starResids

  resids = starResids
  for (j in (jstar+1):p) {
    spacing = data %*% spacingCoef[,j]
    resids = resids + exp(spacing)
    quantiles[,j] = resids
  }

  resids = starResids
  for (j in (jstar-1):1) {
    spacing = data %*% spacingCoef[,j]
    resids = resids - exp(spacing)
    quantiles[,j] = resids
  }

  return(quantiles)
}

