// GSLFunctionMap — comptime mapping from Yamori capability names to GSL function names.

const std = @import("std");

pub const GSLFunctionMap = struct {
    const Entry = struct {
        capability_name: []const u8,
        gsl_fn: []const u8,
        gsl_header: []const u8,
    };

    pub const all: []const Entry = &.{
        .{ .capability_name = "mean", .gsl_fn = "gsl_stats_mean", .gsl_header = "mean" },
        .{ .capability_name = "variance", .gsl_fn = "gsl_stats_variance", .gsl_header = "variance" },
        .{ .capability_name = "std_dev", .gsl_fn = "gsl_stats_sd", .gsl_header = "sd" },
        .{ .capability_name = "covariance", .gsl_fn = "gsl_stats_covariance", .gsl_header = "covariance" },
        .{ .capability_name = "correlation", .gsl_fn = "gsl_stats_correlation", .gsl_header = "correlation" },
        .{ .capability_name = "quantile", .gsl_fn = "gsl_stats_quantile", .gsl_header = "quantile" },
        .{ .capability_name = "median", .gsl_fn = "gsl_stats_median_from_sorted_data", .gsl_header = "median" },
        .{ .capability_name = "percentile", .gsl_fn = "gsl_stats_percentile_from_sorted_data", .gsl_header = "percentile" },
    };

    /// Look up the GSL function name for a given capability name.
    /// Returns null if the capability is not mapped.
    pub fn lookup(capability_name: []const u8) ?[]const u8 {
        for (all) |entry| {
            if (std.mem.eql(u8, entry.capability_name, capability_name)) {
                return entry.gsl_fn;
            }
        }
        return null;
    }
};
