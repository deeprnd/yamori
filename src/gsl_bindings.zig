// src/gsl_bindings.zig
// External GSL function bindings.
// All functions operate on double-precision arrays with stride=1.

const std = @import("std");

extern "gsl" fn gsl_stats_mean(data: [*]const f64, stride: usize, n: usize) f64;
extern "gsl" fn gsl_stats_variance(data: [*]const f64, stride: usize, n: usize) f64;
extern "gsl" fn gsl_stats_sd(data: [*]const f64, stride: usize, n: usize) f64;
extern "gsl" fn gsl_stats_covariance(data1: [*]const f64, stride1: usize,
    data2: [*]const f64, stride2: usize, n: usize) f64;
extern "gsl" fn gsl_stats_correlation(data1: [*]const f64, stride1: usize,
    data2: [*]const f64, stride2: usize, n: usize) f64;
extern "gsl" fn gsl_stats_quantile_from_sorted_data(sorted_data: [*]const f64,
    stride: usize, n: usize, f: f64) f64;
extern "gsl" fn gsl_stats_median_from_sorted_data(sorted_data: [*]const f64,
    stride: usize, n: usize) f64;

/// Compute the arithmetic mean of a data array.
pub fn mean(data: []const f64) f64 {
    return gsl_stats_mean(data.ptr, 1, data.len);
}

/// Compute the variance of a data array.
pub fn variance(data: []const f64) f64 {
    return gsl_stats_variance(data.ptr, 1, data.len);
}

/// Compute the standard deviation of a data array.
pub fn sd(data: []const f64) f64 {
    return gsl_stats_sd(data.ptr, 1, data.len);
}

/// Compute the covariance between two data arrays.
pub fn covariance(data1: []const f64, data2: []const f64) f64 {
    return gsl_stats_covariance(data1.ptr, 1, data2.ptr, 1, data1.len);
}

/// Compute the correlation between two data arrays.
pub fn correlation(data1: []const f64, data2: []const f64) f64 {
    return gsl_stats_correlation(data1.ptr, 1, data2.ptr, 1, data1.len);
}

/// Compute the quantile from sorted data at fraction f (0.0 ≤ f ≤ 1.0).
pub fn quantile(sorted_data: []const f64, f: f64) f64 {
    return gsl_stats_quantile_from_sorted_data(sorted_data.ptr, 1, sorted_data.len, f);
}

/// Compute the median from sorted data.
pub fn median(sorted_data: []const f64) f64 {
    return gsl_stats_median_from_sorted_data(sorted_data.ptr, 1, sorted_data.len);
}
