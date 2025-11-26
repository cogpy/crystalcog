#!/usr/bin/env crystal

# CrystalCog Performance Profiler CLI Tool
# Provides command-line interface for all profiling and optimization features
# Note: This file expects to be located in the tools/ directory of the crystalcog project

require "../src/cogutil/profiling_cli"

# Run the profiling CLI with command-line arguments
cli = CogUtil::ProfilingCLI.new
cli.run(ARGV)
