results_path = ExCodecs.BenchHelper.results_path()

unless File.exists?(results_path) do
  File.mkdir_p!(results_path)
end

IO.puts("""
================================================================
  ExCodecs Benchmark Runner
================================================================

  This script runs the full compression benchmark suite:
    1. Compression speed (5 codecs × 3 sizes × 4 patterns)
    2. Decompression speed (5 codecs × 3 sizes × 4 patterns)
    3. Zstd compression levels (5 levels × 4 patterns)
    4. Zstd decompression levels (5 levels × 4 patterns)
    5. Blosc2 codec/shuffle configurations (6 configs × 4 patterns)
    6. Blosc2 decompression configurations (6 configs × 4 patterns)
    7. Compression ratio summary

  Results are saved to: #{results_path}/
================================================================
""")

Code.require_file("compression_bench.exs", __DIR__)

IO.puts("""

================================================================
  All benchmarks complete!
  
  HTML reports:
    - #{results_path}/compression.html
    - #{results_path}/decompression.html
    - #{results_path}/zstd_levels_compression.html
    - #{results_path}/zstd_levels_decompression.html
    - #{results_path}/blosc2_compression.html
    - #{results_path}/blosc2_decompression.html
  
  Saved benchmark data (.benchee files) can be loaded for comparison.
================================================================
""")
