# Benchmarking Methodology

This guide explains how to benchmark ExCodecs codecs, establish reproducible results, and interpret the data to make informed decisions.

## Why Benchmark

Codec performance varies dramatically based on:

- **Input data characteristics**: text vs. binary, entropy, redundancy patterns, element size.
- **Data size**: small payloads (under 1 KB) have different profiles than large payloads (over 100 MB).
- **Hardware**: CPU architecture, cache sizes, memory bandwidth, number of cores.
- **System load**: concurrent compression operations, BEAM scheduler contention, dirty scheduler availability.

Choosing a codec based on marketing numbers or synthetic benchmarks is unreliable. You must benchmark with your actual data on your actual hardware.

## Setting Up Benchmarks

ExCodecs uses [Benchee](https://github.com/bencheeorg/benchee) for benchmarking. The dependency is already configured for the `:bench` Mix environment:

```elixir
# In mix.exs
{:benchee, "~> 1.3", only: :bench},
{:benchee_html, "~>> 1.0", only: :bench}
```

### Creating a Benchmark

Benchmarks live in the `bench/` directory. The benchmark path is included in the `:bench` environment:

```elixir
# In mix.exs
defp elixirc_paths(:bench), do: ["lib", "bench"]
```

Create a benchmark file:

```elixir
# bench/compression_benchmark.exs
input_small = :crypto.strong_rand_bytes(1024)        # 1 KB
input_medium = :crypto.strong_rand_bytes(1024 * 1024) # 1 MB
input_large = :crypto.strong_rand_bytes(10 * 1024 * 1024) # 10 MB

# For realistic data, use your actual production data:
# input_json = File.read!("bench/data/sample.json")
# input_floats = File.read!("bench/data/float_array.bin")

Benchee.run(
  %{
    "zstd_encode" => fn input -> ExCodecs.encode(:zstd, input) end,
    "lz4_encode" => fn input -> ExCodecs.encode(:lz4, input) end,
    "snappy_encode" => fn input -> ExCodecs.encode(:snappy, input) end,
    "bzip2_encode" => fn input -> ExCodecs.encode(:bzip2, input) end,
    "blosc2_encode" => fn input -> ExCodecs.encode(:blosc2, input) end
  },
  inputs: %{
    "1 KB" => input_small,
    "1 MB" => input_medium,
    "10 MB" => input_large
  },
  time: 10,
  memory_time: 2,
  warmup: 5
)
```

Run it:

```bash
MIX_ENV=bench mix run bench/compression_benchmark.exs
```

### Benchmarking with Options

Test different configuration levels:

```elixir
Benchee.run(
  %{
    "zstd_l1" => fn input -> ExCodecs.encode(:zstd, input, level: 1) end,
    "zstd_l3" => fn input -> ExCodecs.encode(:zstd, input, level: 3) end,
    "zstd_l9" => fn input -> ExCodecs.encode(:zstd, input, level: 9) end,
    "zstd_l15" => fn input -> ExCodecs.encode(:zstd, input, level: 15) end,
    "zstd_l22" => fn input -> ExCodecs.encode(:zstd, input, level: 22) end
  },
  inputs: %{
    "1 MB" => input_medium
  },
  time: 30,
  warmup: 10
)
```

### Benchmarking Decompression

Decompression benchmarks require pre-compressed data:

```elixir
{:ok, zstd_data} = ExCodecs.encode(:zstd, input, level: 3)
{:ok, lz4_data} = ExCodecs.encode(:lz4, input)
{:ok, snappy_data} = ExCodecs.encode(:snappy, input)

Benchee.run(
  %{
    "zstd_decode" => fn _ -> ExCodecs.decode(:zstd, zstd_data) end,
    "lz4_decode" => fn _ -> ExCodecs.decode(:lz4, lz4_data) end,
    "snappy_decode" => fn _ -> ExCodecs.decode(:snappy, snappy_data) end
  },
  inputs: %{
    "1 MB" => :ok
  },
  time: 10,
  warmup: 5
)
```

## What to Measure

### Throughput (MB/s)

The primary metric for codec performance. Measures how many megabytes of input data are processed per second.

- **Compression throughput**: MB/s of original data compressed per second.
- **Decompression throughput**: MB/s of compressed data decompressed per second.

Higher is better. Benchee reports iterations per second; convert to MB/s:

```
Throughput (MB/s) = (input_size_bytes / 1024 / 1024) * iterations_per_second
```

### Compression Ratio

The ratio of original size to compressed size:

```
Ratio = original_size_bytes / compressed_size_bytes
```

Or as a percentage of original size:

```
Percentage = (compressed_size_bytes / original_size_bytes) * 100
```

Measure this alongside throughput:

```elixir
{:ok, compressed} = ExCodecs.encode(:zstd, data, level: 3)

ratio = byte_size(data) / byte_size(compressed)
percentage = (byte_size(compressed) / byte_size(data)) * 100

IO.puts("Original: #{byte_size(data)} bytes")
IO.puts("Compressed: #{byte_size(compressed)} bytes")
IO.puts("Ratio: #{Float.round(ratio, 2)}:1 (#{Float.round(percentage, 1)}%)")
```

### Memory Usage

Use Benchee's `memory_time` option to measure memory allocation:

```elixir
Benchee.run(
  %{"zstd_encode" => fn input -> ExCodecs.encode(:zstd, input) end},
  inputs: %{"1 MB" => input_medium},
  time: 10,
  memory_time: 2  # Measure memory for 2 seconds
)
```

Note: Benchee measures BEAM memory allocations. NIF memory allocations (which is where most codec memory is used) are not captured by Benchee. For NIF memory, use OS-level tools:

```bash
# Watch process memory during compression
ps -o rss= -p <beam_pid>
```

### Latency Distribution

For latency-sensitive applications, measure the distribution of individual operation times:

```elixir
Benchee.run(
  %{
    "zstd_encode" => fn input -> ExCodecs.encode(:zstd, input) end,
    "lz4_encode" => fn input -> ExCodecs.encode(:lz4, input) end
  },
  inputs: %{"1 KB" => input_small},
  time: 10,
  warmup: 5
)
```

Look at the p99 (99th percentile) latency, not just the average. For real-time systems, the tail latency matters more than the mean.

## Reproducibility

Reproducible benchmarks are essential for comparing results across different systems and over time.

### Control the Environment

1. **Pin the codec versions.** The versions of `zstd`, `lz4_flex`, `snap`, and `bzip2` crates in `Cargo.toml` determine the actual algorithm implementations. Record these versions.

```toml
# native/ex_codecs_native/Cargo.toml
zstd = "0.13"
lz4_flex = "0.11"
snap = "1.1"
bzip2 = "0.4"
```

2. **Use fixed input data.** Generate test data deterministically or use a fixed seed:

```elixir
# Deterministic random data
:rand.seed(:default, 42)
input = :rand.bytes(1024 * 1024)

# Or use production data
input = File.read!("bench/data/production_sample.json")
```

3. **Report system details.** Record:
   - CPU model and clock speed
   - Number of cores and dirty schedulers
   - OTP version
   - Elixir version
   - OS and architecture
   - Whether the NIF is precompiled or compiled locally

```elixir
System.shell("uname -a")
System.build_info()
System.otp_release()
```

4. **Warm up the system.** Always include a warmup phase. The first few iterations may be slower due to JIT compilation (if applicable), cache population, and lazy loading.

5. **Isolate the benchmark.** Run on a quiet system with minimal background processes. Close browsers, stop unnecessary services, and avoid running other workloads concurrently.

### Benchee Configuration for Reproducibility

```elixir
Benchee.run(
  %{...},
  time: 30,        # Run each scenario for 30 seconds
  warmup: 10,      # Warm up for 10 seconds before measuring
  memory_time: 2,  # Measure memory for 2 seconds
  save: [path: "bench/results/compression.json"],  # Save results
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "bench/results/compression.html"}
  ]
)
```

### Comparing Across Runs

Save benchmark results and compare them:

```elixir
# Run 1
Benchee.run(%{...}, save: [path: "bench/run1.json"])

# Run 2 (after changes)
Benchee.run(%{...}, load: "bench/run1.json")
```

## Benchmarking Anti-Patterns

### Measuring the Wrong Thing

Do not measure function call overhead instead of actual compression. Always use realistic data sizes:

```elixir
# BAD: Too small, overhead dominates
input = "hello"

# GOOD: Representative of your actual data
input = File.read!("bench/data/production_sample.json")
```

### Ignoring Data Characteristics

Different data types compress differently. Always benchmark with data that matches your production workload:

| Data Type      | Zstd L3 Ratio | LZ4 L1 Ratio |
|---------------|----------------|---------------|
| English text   | 3.0:1          | 2.0:1         |
| JSON           | 2.8:1          | 1.9:1         |
| Float64 array  | 2.0:1          | 1.5:1         |
| Random bytes   | 1.0:1          | 1.0:1         |

Results from one data type do not generalize to another.

### Averaging Away Tail Latency

For latency-sensitive applications, the average (mean) is misleading. Two codecs with similar average latency may have very different p99 latency:

```
Codec A: mean 0.5ms, p99 0.8ms, max 1.2ms
Codec B: mean 0.5ms, p99 5.0ms, max 50ms
```

Codec A is better for real-time systems despite the same mean.

### Not Measuring Memory

For concurrent systems, memory usage can be as important as speed. A fast codec that allocates large buffers under concurrent load can cause GC pressure or OOM errors.

### Benchmarking Compression Only

Decompression speed matters as much as compression speed for read-heavy workloads. Always benchmark both directions.

## Recommended Benchmark Suite

Create a comprehensive benchmark suite that covers these scenarios:

### 1. Compression Throughput by Codec and Data Size

```elixir
# bench/throughput.exs
sizes = [
  {"1 KB", :crypto.strong_rand_bytes(1024)},
  {"10 KB", :crypto.strong_rand_bytes(10 * 1024)},
  {"100 KB", :crypto.strong_rand_bytes(100 * 1024)},
  {"1 MB", :crypto.strong_rand_bytes(1024 * 1024)},
  {"10 MB", :crypto.strong_rand_bytes(10 * 1024 * 1024)}
]

codecs = [:zstd, :lz4, :snappy, :bzip2, :blosc2]

for {size_name, data} <- sizes do
  Benchee.run(
    Enum.into(codecs, %{}, fn codec ->
      {"#{codec}_#{size_name}", fn _ -> ExCodecs.encode(codec, data) end}
    end),
    time: 10,
    warmup: 5
  )
end
```

### 2. Zstd Level Sweep

```elixir
# bench/zstd_levels.exs
input = File.read!("bench/data/sample.json")

Benchee.run(
  Enum.into(1..22, %{}, fn level ->
    {"zstd_l#{level}", fn _ -> ExCodecs.encode(:zstd, input, level: level) end}
  end),
  time: 5,
  warmup: 2
)
```

### 3. Decompression Throughput by Codec

```elixir
# bench/decompression.exs
input = File.read!("bench/data/sample.json")

compressed = %{
  zstd: elem(ExCodecs.encode(:zstd, input), 1),
  lz4: elem(ExCodecs.encode(:lz4, input), 1),
  snappy: elem(ExCodecs.encode(:snappy, input), 1),
  bzip2: elem(ExCodecs.encode(:bzip2, input), 1)
}

Benchee.run(
  Enum.into(compressed, %{}, fn {codec, data} ->
    {"#{codec}_decode", fn _ -> ExCodecs.decode(codec, data) end}
  end),
  time: 10,
  warmup: 5
)
```

### 4. Blosc2 Configuration Sweep

```elixir
# bench/blosc2_configs.exs
input = File.read!("bench/data/float_array.bin")  # float64 array

configs = [
  {"blosc2_lz4_none", [cname: :lz4, clevel: 5, shuffle: :none]},
  {"blosc2_lz4_byte", [cname: :lz4, clevel: 5, shuffle: :byte, typesize: 8]},
  {"blosc2_zstd_none", [cname: :zstd, clevel: 5, shuffle: :none]},
  {"blosc2_zstd_byte", [cname: :zstd, clevel: 5, shuffle: :byte, typesize: 8]},
  {"blosc2_zstd_bit", [cname: :zstd, clevel: 5, shuffle: :bit, typesize: 8]}
]

Benchee.run(
  Enum.into(configs, %{}, fn {name, opts} ->
    {name, fn _ -> ExCodecs.encode(:blosc2, input, opts) end}
  end),
  time: 10,
  warmup: 5
)
```

### 5. Ratio Comparison

```elixir
# bench/ratios.exs
input = File.read!("bench/data/sample.json")

for codec <- [:zstd, :lz4, :snappy, :bzip2, :blosc2] do
  {:ok, compressed} = ExCodecs.encode(codec, input)
  ratio = Float.round(byte_size(input) / byte_size(compressed), 2)
  IO.puts("#{codec}: #{byte_size(input)} -> #{byte_size(compressed)} (#{ratio}:1)")
end

# Zstd levels
for level <- [1, 3, 5, 9, 14, 19, 22] do
  {:ok, compressed} = ExCodecs.encode(:zstd, input, level: level)
  ratio = Float.round(byte_size(input) / byte_size(compressed), 2)
  IO.puts("zstd_l#{level}: #{byte_size(compressed)} bytes (#{ratio}:1)")
end
```

## Interpreting Results

### The Speed-Ratio Tradeoff

Plot compression ratio vs. speed for each codec and configuration:

```
Ratio
5.0 |                                    * Bzip2-9
    |                           * Zstd-19
4.0 |                      * Zstd-9
    |                 * Zstd-5
3.0 |            * Zstd-3
    |       * Zstd-1
2.0 |    * LZ4-1   * Snappy
    |
1.0 +----------------------------------------- Speed
     500 MB/s                    10 MB/s
```

Choose the point that meets your requirements. If you need >3:1 ratio and >100 MB/s, Zstd level 5 is a good choice. If you need >500 MB/s, LZ4 or Snappy are your options.

### Context Matters

A benchmark result is only meaningful in context. Always state:

1. What data you used (type, size, entropy).
2. What hardware you ran on (CPU, cores, memory).
3. What versions of everything (Elixir, OTP, ExCodecs, underlying libraries).
4. What configuration you used (codec options).

### When to Re-Benchmark

Re-benchmark when:

- You upgrade ExCodecs or any dependency.
- You change hardware or deployment environment.
- You change your data format or typical payload size.
- You change the number of concurrent compression operations.

## Summary

1. Benchmark with your actual data and hardware. Synthetic benchmarks are not reliable.
2. Measure throughput, ratio, memory, and tail latency. Do not focus on only one metric.
3. Use Benchee with adequate warmup and measurement time.
4. Record your environment for reproducibility.
5. Test both compression and decompression. Read-heavy workloads should prioritize decompression speed.
6. Test multiple data sizes. Performance characteristics change as data size increases.
7. Avoid averaging away tail latency. Use p99 and max for latency-sensitive systems.