# CPU benchmark (compare machines): fixed synthetic BRT fit + predict. Same code, same data -> the
# ratio of the timings between two machines is the speed ratio to apply to our runtime estimates.
suppressMessages(library(gbm))
set.seed(1)
n <- 5000; p <- 20
x <- as.data.frame(matrix(runif(n * p), n, p)); names(x) <- paste0("v", 1:p)
y <- rbinom(n, 1, plogis(3 * x$v1 - 2 * x$v2 * x$v3 + sin(6 * x$v4) - 1))
t0 <- proc.time()[3]
fit <- gbm(y ~ ., data = cbind(y = y, x), distribution = "bernoulli", n.trees = 1500, shrinkage = 0.05,
           interaction.depth = 2, bag.fraction = 0.75, verbose = FALSE)
tFit <- unname(proc.time()[3] - t0)
nd <- as.data.frame(matrix(runif(1e6 * p), 1e6, p)); names(nd) <- names(x)
t0 <- proc.time()[3]; pr <- predict(fit, nd, n.trees = 1500, type = "response"); tPred <- unname(proc.time()[3] - t0)
cat(sprintf("BENCH fit(5000 x 20, 1500 trees) = %.1f s | predict(1e6 rows, 1500 trees) = %.1f s | host = %s\n", tFit, tPred, Sys.info()[["nodename"]]))
