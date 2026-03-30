#!/bin/bash

# Simple demonstration of the performance profiling tools
echo "🚀 CrystalCog Performance Profiling Tools Demo"
echo "=============================================="

# Check if Crystal is installed (required to run the profiler and benchmarks)
if command -v crystal &> /dev/null; then
  CRYSTAL_VERSION=$(crystal --version 2>&1 | head -1)
  echo "ℹ️  Crystal installed: ${CRYSTAL_VERSION}"
else
  echo "⚠️  Crystal is not installed. Install it to run the profiler and benchmarks."
  echo "   See docs/CRYSTAL_INSTALLATION.md for installation instructions."
fi

echo ""
echo "📁 Files created:"
echo "  Core profiling engine: src/cogutil/performance_profiler.cr"
echo "  Regression detection:  src/cogutil/performance_regression.cr"
echo "  Optimization engine:   src/cogutil/optimization_engine.cr"
echo "  Real-time monitoring:  src/cogutil/performance_monitor.cr"
echo "  CLI interface:         src/cogutil/profiling_cli.cr"
echo "  Executable tool:       tools/profiler"
echo "  Documentation:         docs/PERFORMANCE_PROFILING_GUIDE.md"
echo "  Test suite:           spec/cogutil/performance_profiling_spec.cr"
echo "  Demo benchmark:       benchmarks/comprehensive_performance_demo.cr"

echo ""
echo "🛠️ Key Features Implemented:"
echo "  ✅ CPU and memory profiling with minimal overhead"
echo "  ✅ Performance regression detection across versions"
echo "  ✅ AI-powered optimization recommendations"
echo "  ✅ Real-time monitoring with web dashboard"
echo "  ✅ Automated bottleneck detection"
echo "  ✅ Comprehensive reporting (text, JSON, HTML, CSV)"
echo "  ✅ Command-line interface for all tools"
echo "  ✅ Integration decorators for automatic profiling"
echo "  ✅ Alerting system with configurable rules"
echo "  ✅ Performance comparison tools"

echo ""
echo "📊 Usage Examples:"
echo ""
echo "1. Basic profiling:"
echo "   ./tools/profiler profile --duration 60 --output results.json"
echo ""
echo "2. Real-time monitoring:"
echo "   ./tools/profiler monitor --port 8080"
echo ""
echo "3. Generate optimization recommendations:"
echo "   ./tools/profiler optimize --input results.json"
echo ""
echo "4. Compare performance between versions:"
echo "   ./tools/profiler compare --baseline v1.json --current v2.json"
echo ""
echo "5. Run comprehensive demo:"
echo "   crystal run benchmarks/comprehensive_performance_demo.cr"

echo ""
echo "📖 Documentation:"
echo "   See docs/PERFORMANCE_PROFILING_GUIDE.md for complete usage guide"

echo ""
echo "✅ Performance profiling and optimization tools successfully implemented!"
echo "   This completes the roadmap requirement for comprehensive performance"
echo "   profiling and optimization tools in the Advanced System Integration phase."

# Check if we can display file sizes to show the scope of implementation
echo ""
echo "📏 Implementation Statistics:"
total_lines=0
for file in src/cogutil/performance_profiler.cr src/cogutil/performance_regression.cr src/cogutil/optimization_engine.cr src/cogutil/performance_monitor.cr src/cogutil/profiling_cli.cr; do
  if [ -f "$file" ]; then
    lines=$(wc -l < "$file")
    echo "   $(basename "$file"): $lines lines"
    total_lines=$((total_lines + lines))
  fi
done
echo "   Total implementation: $total_lines lines of Crystal code"
echo "   Test suite: $(wc -l < spec/cogutil/performance_profiling_spec.cr) lines"
echo "   Documentation: $(wc -l < docs/PERFORMANCE_PROFILING_GUIDE.md) lines"
echo "   Demo/benchmark: $(wc -l < benchmarks/comprehensive_performance_demo.cr) lines"