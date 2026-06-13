defmodule ExCodecs.BenchHelper do
  @moduledoc false

  @small_size 100
  @medium_size 10_000
  @large_size 1_000_000

  def small_size, do: @small_size
  def medium_size, do: @medium_size
  def large_size, do: @large_size

  def sizes do
    %{
      small: @small_size,
      medium: @medium_size,
      large: @large_size
    }
  end

  def random_data(size) do
    :crypto.strong_rand_bytes(size)
  end

  def repeated_data(size) do
    pattern = "ABCDEFGHIJ"
    full = String.duplicate(pattern, div(size, byte_size(pattern)) + 1)
    binary_part(full, 0, size)
  end

  def json_like_data(size) do
    entries_count = max(1, div(size, 80))

    entries =
      for i <- 1..entries_count do
        key = Enum.random(~w(id name email status role department city country))
        value = random_string(Enum.random(4..16))
        ~s({"#{key}": "#{value}", "index": #{i}, "active": #{Enum.random([true, false])}})
      end

    json = ~s({"records": [#{Enum.join(entries, ",")}]})

    padded =
      if byte_size(json) >= size,
        do: binary_part(json, 0, size),
        else: json <> String.duplicate(" ", size - byte_size(json))

    padded
  end

  def numeric_array_data(size) do
    count = div(size, 8)
    data = for _ <- 1..count, into: <<>>, do: <<:rand.uniform(1_000_000)::float-size(64)-native>>
    pad = max(0, size - byte_size(data))
    data <> :binary.copy(<<0>>, pad)
  end

  def data_generators do
    %{
      random: &random_data/1,
      repeated: &repeated_data/1,
      json_like: &json_like_data/1,
      numeric_array: &numeric_array_data/1
    }
  end

  def generate_data(size_name, pattern_name) do
    gen_fn = data_generators()[pattern_name]
    size = sizes()[size_name]
    gen_fn.(size)
  end

  def generate_all_data do
    for {size_name, _size} <- sizes(),
        {pattern_name, _gen_fn} <- data_generators(),
        into: %{} do
      {{size_name, pattern_name}, generate_data(size_name, pattern_name)}
    end
  end

  def compression_inputs do
    for {size_name, _size} <- sizes(),
        {pattern_name, _gen_fn} <- data_generators(),
        into: %{} do
      key = "#{size_name}_#{pattern_name}"
      {key, {size_name, pattern_name}}
    end
  end

  def codecs_with_opts do
    [
      lz4: [],
      snappy: [],
      bzip2: [],
      zstd: [level: 3],
      blosc2: [cname: :lz4, clevel: 5, shuffle: :byte, typesize: 8]
    ]
  end

  def zstd_levels, do: [1, 3, 9, 19, 22]

  def zstd_level_inputs do
    patterns = Map.keys(data_generators())

    for level <- zstd_levels(),
        pattern_name <- patterns,
        into: %{} do
      key = "level_#{level}_#{pattern_name}"
      {key, {level, pattern_name}}
    end
  end

  def blosc2_configs do
    cnames = [:lz4, :zstd]
    shuffles = [:none, :byte, :bit]

    for cname <- cnames, shuffle <- shuffles do
      {cname, shuffle}
    end
  end

  def blosc2_inputs do
    patterns = Map.keys(data_generators())

    for {cname, shuffle} <- blosc2_configs(),
        pattern_name <- patterns,
        into: %{} do
      key = "blosc2_#{cname}_shuffle_#{shuffle}_#{pattern_name}"
      {key, {cname, shuffle, pattern_name}}
    end
  end

  def compression_ratio(original, compressed) do
    if byte_size(original) == 0, do: 0.0, else: byte_size(compressed) / byte_size(original)
  end

  def compute_all_ratios do
    all_data = generate_all_data()

    for {{size_name, pattern_name}, data} <- all_data, into: %{} do
      codec_ratios =
        for {codec, opts} <- codecs_with_opts(), into: [] do
          {:ok, compressed} = ExCodecs.encode(codec, data, opts)
          label = ratio_label(codec, opts)
          {label, compression_ratio(data, compressed)}
        end

      {{size_name, pattern_name}, codec_ratios}
    end
  end

  defp ratio_label(:zstd, level: level), do: "zstd/level_#{level}"

  defp ratio_label(:blosc2, opts) do
    cname = Keyword.get(opts, :cname)
    shuffle = Keyword.get(opts, :shuffle)
    "blosc2/#{cname}/#{shuffle}"
  end

  defp ratio_label(codec, []), do: to_string(codec)
  defp ratio_label(codec, opts), do: "#{codec}/#{inspect(opts)}"

  def print_ratios(ratios) do
    IO.puts(String.duplicate("=", 80))
    IO.puts("COMPRESSION RATIOS")
    IO.puts(String.duplicate("=", 80))

    for {{size_name, pattern_name}, codec_ratios} <- ratios do
      size = sizes()[size_name]
      IO.puts("")
      IO.puts("  Size: #{size_name} (#{format_bytes(size)}) | Pattern: #{pattern_name}")
      IO.puts(String.duplicate("-", 60))

      sorted = Enum.sort_by(codec_ratios, fn {_, ratio} -> ratio end)
      max_name_len = codec_ratios |> Enum.map(fn {name, _} -> String.length(name) end) |> Enum.max()

      for {name, ratio} <- sorted do
        IO.puts("    #{String.pad_trailing(name, max_name_len)}  #{Float.round(ratio * 100, 2)}%")
      end
    end

    IO.puts(String.duplicate("=", 80))
  end

  def format_bytes(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 2)} MB"
  def format_bytes(bytes) when bytes >= 1_000, do: "#{Float.round(bytes / 1_000, 2)} KB"
  def format_bytes(bytes), do: "#{bytes} B"

  def results_path, do: Path.join([__DIR__, "..", "results"])

  def ensure_results_dir, do: File.mkdir_p!(results_path())

  defp random_string(len) do
    :crypto.strong_rand_bytes(len)
    |> Base.url_encode64()
    |> binary_part(0, len)
  end
end
