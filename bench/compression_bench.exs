ExCodecs.BenchHelper.ensure_results_dir()

results_path = ExCodecs.BenchHelper.results_path()
basic_inputs = ExCodecs.BenchHelper.compression_inputs()

IO.puts("\n")
IO.puts(String.duplicate("=", 80))
IO.puts("  EXCODECS COMPRESSION BENCHMARK SUITE")
IO.puts(String.duplicate("=", 80))
IO.puts("\n")

IO.puts("--- Phase 1: Compression speed across codecs, sizes, and patterns ---\n")

Benchee.run(
  %{
    "lz4" => fn data ->
      {:ok, _} = ExCodecs.encode(:lz4, data, [])
    end,
    "snappy" => fn data ->
      {:ok, _} = ExCodecs.encode(:snappy, data, [])
    end,
    "bzip2" => fn data ->
      {:ok, _} = ExCodecs.encode(:bzip2, data, [])
    end,
    "zstd" => fn data ->
      {:ok, _} = ExCodecs.encode(:zstd, data, level: 3)
    end,
    "blosc2" => fn data ->
      {:ok, _} = ExCodecs.encode(:blosc2, data, cname: :lz4, clevel: 5, shuffle: :byte, typesize: 8)
    end
  },
  before_scenario: fn {size_name, pattern_name} ->
    ExCodecs.BenchHelper.generate_data(size_name, pattern_name)
  end,
  inputs: basic_inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false},
    {Benchee.Formatters.HTML, file: Path.join(results_path, "compression.html")}
  ],
  save: [path: Path.join(results_path, "compression.benchee")]
)

IO.puts("\n--- Phase 2: Decompression speed across codecs, sizes, and patterns ---\n")

decompress_jobs = %{
  "lz4" => fn precompressed -> {:ok, _} = ExCodecs.decode(:lz4, precompressed.lz4, []) end,
  "snappy" => fn precompressed -> {:ok, _} = ExCodecs.decode(:snappy, precompressed.snappy, []) end,
  "bzip2" => fn precompressed -> {:ok, _} = ExCodecs.decode(:bzip2, precompressed.bzip2, []) end,
  "zstd" => fn precompressed -> {:ok, _} = ExCodecs.decode(:zstd, precompressed.zstd, []) end,
  "blosc2" => fn precompressed -> {:ok, _} = ExCodecs.decode(:blosc2, precompressed.blosc2, []) end
}

Benchee.run(
  decompress_jobs,
  before_scenario: fn {size_name, pattern_name} ->
    data = ExCodecs.BenchHelper.generate_data(size_name, pattern_name)

    {:ok, lz4_data} = ExCodecs.encode(:lz4, data, [])
    {:ok, snappy_data} = ExCodecs.encode(:snappy, data, [])
    {:ok, bzip2_data} = ExCodecs.encode(:bzip2, data, [])
    {:ok, zstd_data} = ExCodecs.encode(:zstd, data, level: 3)

    {:ok, blosc2_data} =
      ExCodecs.encode(:blosc2, data, cname: :lz4, clevel: 5, shuffle: :byte, typesize: 8)

    %{
      lz4: lz4_data,
      snappy: snappy_data,
      bzip2: bzip2_data,
      zstd: zstd_data,
      blosc2: blosc2_data
    }
  end,
  inputs: basic_inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false},
    {Benchee.Formatters.HTML, file: Path.join(results_path, "decompression.html")}
  ],
  save: [path: Path.join(results_path, "decompression.benchee")]
)

IO.puts("\n--- Phase 3: Zstd compression levels ---\n")

zstd_inputs = ExCodecs.BenchHelper.zstd_level_inputs()

Benchee.run(
  %{
    "zstd/level_1/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:zstd, data, level: 1)
    end,
    "zstd/level_3/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:zstd, data, level: 3)
    end,
    "zstd/level_9/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:zstd, data, level: 9)
    end,
    "zstd/level_19/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:zstd, data, level: 19)
    end,
    "zstd/level_22/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:zstd, data, level: 22)
    end
  },
  before_scenario: fn {_level, pattern_name} ->
    ExCodecs.BenchHelper.generate_data(:medium, pattern_name)
  end,
  inputs: zstd_inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false},
    {Benchee.Formatters.HTML, file: Path.join(results_path, "zstd_levels_compression.html")}
  ],
  save: [path: Path.join(results_path, "zstd_levels_compression.benchee")]
)

Benchee.run(
  %{
    "zstd/level_1/decompress" => fn precompressed ->
      {:ok, _} = ExCodecs.decode(:zstd, precompressed.level_1, [])
    end,
    "zstd/level_3/decompress" => fn precompressed ->
      {:ok, _} = ExCodecs.decode(:zstd, precompressed.level_3, [])
    end,
    "zstd/level_9/decompress" => fn precompressed ->
      {:ok, _} = ExCodecs.decode(:zstd, precompressed.level_9, [])
    end,
    "zstd/level_19/decompress" => fn precompressed ->
      {:ok, _} = ExCodecs.decode(:zstd, precompressed.level_19, [])
    end,
    "zstd/level_22/decompress" => fn precompressed ->
      {:ok, _} = ExCodecs.decode(:zstd, precompressed.level_22, [])
    end
  },
  before_scenario: fn {_level, pattern_name} ->
    data = ExCodecs.BenchHelper.generate_data(:medium, pattern_name)

    levels = ExCodecs.BenchHelper.zstd_levels()

    for level <- levels, into: %{} do
      {:ok, compressed} = ExCodecs.encode(:zstd, data, level: level)
      {:"level_#{level}", compressed}
    end
  end,
  inputs: zstd_inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false},
    {Benchee.Formatters.HTML, file: Path.join(results_path, "zstd_levels_decompression.html")}
  ],
  save: [path: Path.join(results_path, "zstd_levels_decompression.benchee")]
)

IO.puts("\n--- Phase 4: Blosc2 internal codecs and shuffle modes ---\n")

blosc2_inputs = ExCodecs.BenchHelper.blosc2_inputs()

Benchee.run(
  %{
    "blosc2/lz4/none/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:blosc2, data, cname: :lz4, clevel: 5, shuffle: :none, typesize: 8)
    end,
    "blosc2/lz4/byte/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:blosc2, data, cname: :lz4, clevel: 5, shuffle: :byte, typesize: 8)
    end,
    "blosc2/lz4/bit/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:blosc2, data, cname: :lz4, clevel: 5, shuffle: :bit, typesize: 8)
    end,
    "blosc2/zstd/none/compress" => fn data ->
      {:ok, _} =
        ExCodecs.encode(:blosc2, data, cname: :zstd, clevel: 5, shuffle: :none, typesize: 8)
    end,
    "blosc2/zstd/byte/compress" => fn data ->
      {:ok, _} =
        ExCodecs.encode(:blosc2, data, cname: :zstd, clevel: 5, shuffle: :byte, typesize: 8)
    end,
    "blosc2/zstd/bit/compress" => fn data ->
      {:ok, _} = ExCodecs.encode(:blosc2, data, cname: :zstd, clevel: 5, shuffle: :bit, typesize: 8)
    end
  },
  before_scenario: fn {_cname, _shuffle, pattern_name} ->
    ExCodecs.BenchHelper.generate_data(:medium, pattern_name)
  end,
  inputs: blosc2_inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false},
    {Benchee.Formatters.HTML, file: Path.join(results_path, "blosc2_compression.html")}
  ],
  save: [path: Path.join(results_path, "blosc2_compression.benchee")]
)

blosc2_configs = [
  {"lz4_none", [cname: :lz4, clevel: 5, shuffle: :none, typesize: 8]},
  {"lz4_byte", [cname: :lz4, clevel: 5, shuffle: :byte, typesize: 8]},
  {"lz4_bit", [cname: :lz4, clevel: 5, shuffle: :bit, typesize: 8]},
  {"zstd_none", [cname: :zstd, clevel: 5, shuffle: :none, typesize: 8]},
  {"zstd_byte", [cname: :zstd, clevel: 5, shuffle: :byte, typesize: 8]},
  {"zstd_bit", [cname: :zstd, clevel: 5, shuffle: :bit, typesize: 8]}
]

decompress_blosc2_jobs =
  for {key, opts} <- blosc2_configs, into: %{} do
    name = "blosc2/#{key}/decompress"

    {name,
     fn precompressed ->
       {:ok, _} = ExCodecs.decode(:blosc2, Map.fetch!(precompressed, String.to_atom(key)), [])
     end}
  end

Benchee.run(
  decompress_blosc2_jobs,
  before_scenario: fn {_cname, _shuffle, pattern_name} ->
    data = ExCodecs.BenchHelper.generate_data(:medium, pattern_name)

    for {key, opts} <- blosc2_configs, into: %{} do
      {:ok, compressed} = ExCodecs.encode(:blosc2, data, opts)
      {String.to_atom(key), compressed}
    end
  end,
  inputs: blosc2_inputs,
  time: 3,
  warmup: 1,
  memory_time: 1,
  formatters: [
    {Benchee.Formatters.Console, comparison: false},
    {Benchee.Formatters.HTML, file: Path.join(results_path, "blosc2_decompression.html")}
  ],
  save: [path: Path.join(results_path, "blosc2_decompression.benchee")]
)

IO.puts("\n--- Phase 5: Compression ratios ---\n")

ratios = ExCodecs.BenchHelper.compute_all_ratios()
ExCodecs.BenchHelper.print_ratios(ratios)

IO.puts("\nBenchmark complete. Results saved to #{results_path}/")
