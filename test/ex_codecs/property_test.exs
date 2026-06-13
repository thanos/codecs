defmodule ExCodecs.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "zstd round-trip preserves data" do
    check all(data <- binary(min: 0, max: 10_000)) do
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == data
    end
  end

  property "lz4 round-trip preserves data" do
    check all(data <- binary(min: 1, max: 10_000)) do
      {:ok, compressed} = ExCodecs.encode(:lz4, data)
      {:ok, decompressed} = ExCodecs.decode(:lz4, compressed)
      assert decompressed == data
    end
  end

  property "snappy round-trip preserves data" do
    check all(data <- binary(min: 1, max: 10_000)) do
      {:ok, compressed} = ExCodecs.encode(:snappy, data)
      {:ok, decompressed} = ExCodecs.decode(:snappy, compressed)
      assert decompressed == data
    end
  end

  property "bzip2 round-trip preserves data" do
    check all(data <- binary(min: 1, max: 10_000)) do
      {:ok, compressed} = ExCodecs.encode(:bzip2, data)
      {:ok, decompressed} = ExCodecs.decode(:bzip2, compressed)
      assert decompressed == data
    end
  end

  property "blosc2 round-trip preserves data (random)" do
    check all(size <- integer(8..10_000)) do
      data = :crypto.strong_rand_bytes(size)
      {:ok, compressed} = ExCodecs.encode(:blosc2, data)
      {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      assert decompressed == data
    end
  end

  property "compression reduces size for repeated data" do
    check all(
            byte <- string(Enum.take(?a..?z, 1), min_length: 1, max_length: 1),
            count <- integer(100..10_000)
          ) do
      data = String.duplicate(byte, count)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      assert byte_size(compressed) < byte_size(data)
    end
  end

  property "zstd round-trip preserves zero-filled data" do
    check all(size <- integer(1..100_000)) do
      data = :binary.copy(<<0>>, size)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == data
    end
  end

  property "lz4 round-trip preserves zero-filled data" do
    check all(size <- integer(1..100_000)) do
      data = :binary.copy(<<0>>, size)
      {:ok, compressed} = ExCodecs.encode(:lz4, data)
      {:ok, decompressed} = ExCodecs.decode(:lz4, compressed)
      assert decompressed == data
    end
  end

  property "blosc2 round-trip preserves zero-filled data" do
    check all(size <- integer(1..50_000)) do
      data = :binary.copy(<<0>>, size)
      {:ok, compressed} = ExCodecs.encode(:blosc2, data, shuffle: :none, typesize: 1)
      {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      assert decompressed == data
    end
  end

  property "bzip2 round-trip preserves zero-filled data" do
    check all(size <- integer(1..100_000)) do
      data = :binary.copy(<<0>>, size)
      {:ok, compressed} = ExCodecs.encode(:bzip2, data)
      {:ok, decompressed} = ExCodecs.decode(:bzip2, compressed)
      assert decompressed == data
    end
  end

  property "snappy round-trip preserves zero-filled data" do
    check all(size <- integer(1..100_000)) do
      data = :binary.copy(<<0>>, size)
      {:ok, compressed} = ExCodecs.encode(:snappy, data)
      {:ok, decompressed} = ExCodecs.decode(:snappy, compressed)
      assert decompressed == data
    end
  end

  property "zstd round-trip preserves repeated-string data" do
    check all(size <- integer(1..50_000)) do
      data = String.duplicate("ab", div(size, 2) + 1)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == data
    end
  end

  property "lz4 round-trip preserves repeated-string data" do
    check all(size <- integer(1..50_000)) do
      data = String.duplicate("ab", div(size, 2) + 1)
      {:ok, compressed} = ExCodecs.encode(:lz4, data)
      {:ok, decompressed} = ExCodecs.decode(:lz4, compressed)
      assert decompressed == data
    end
  end

  property "codec_info is consistent for all codecs" do
    check all(
            codec <-
              one_of([
                constant(:zstd),
                constant(:lz4),
                constant(:snappy),
                constant(:bzip2),
                constant(:blosc2)
              ])
          ) do
      {:ok, info} = ExCodecs.codec_info(codec)
      assert info.name == codec
      assert info.category == :compression
      assert is_boolean(info.native?)
      assert is_boolean(info.streaming?)
      assert is_boolean(info.configurable?)
    end
  end
end
