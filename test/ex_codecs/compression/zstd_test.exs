defmodule ExCodecs.Compression.ZstdTest do
  use ExUnit.Case, async: true

  @moduletag :doctest
  doctest ExCodecs.Compression.Zstd

  alias ExCodecs.Compression.Zstd

  describe "encode/2" do
    test "compresses data with default level" do
      data = String.duplicate("AAAA", 256)
      assert {:ok, compressed} = Zstd.encode(data, [])
      assert is_binary(compressed)
      assert byte_size(compressed) < byte_size(data)
    end

    test "round-trips data at every level 1..22" do
      data = String.duplicate("The quick brown fox jumps over the lazy dog. ", 64)

      for level <- 1..22 do
        assert {:ok, compressed} = Zstd.encode(data, level: level)
        assert {:ok, ^data} = Zstd.decode(compressed, [])
        assert byte_size(compressed) < byte_size(data)
      end
    end

    test "higher levels produce smaller or equal output" do
      # Random data is poorly compressible; use repetitive payload so buckets matter.
      data = String.duplicate("AAAA", 5_000)
      {:ok, c1} = Zstd.encode(data, level: 1)
      {:ok, c19} = Zstd.encode(data, level: 19)
      assert byte_size(c19) <= byte_size(c1)
    end

    test "level buckets produce distinct frames for compressible data" do
      # Varied compressible payload so numeric levels diverge.
      data =
        for i <- 1..8_000, into: <<>> do
          <<rem(i, 997)::32, "PATTERN-REPEAT">>
        end

      {:ok, l1} = Zstd.encode(data, level: 1)
      {:ok, l3} = Zstd.encode(data, level: 3)
      {:ok, l15} = Zstd.encode(data, level: 15)

      distinct = MapSet.new([l1, l3, l15])
      assert MapSet.size(distinct) >= 2

      for frame <- [l1, l3, l15] do
        assert {:ok, ^data} = Zstd.decode(frame, [])
      end
    end

    test "level effectiveness: higher levels produce smaller or equal output for compressible data" do
      data = String.duplicate("Hello, World! ", 10_000)
      {:ok, c1} = Zstd.encode(data, level: 1)
      {:ok, c9} = Zstd.encode(data, level: 9)
      assert byte_size(c9) <= byte_size(c1)
    end

    test "handles empty data" do
      assert {:ok, compressed} = Zstd.encode("", [])
      assert {:ok, ""} = Zstd.decode(compressed, [])
    end

    test "handles single byte data" do
      assert {:ok, compressed} = Zstd.encode(<<42>>, [])
      assert {:ok, <<42>>} = Zstd.decode(compressed, [])
    end

    test "handles large data" do
      data = :crypto.strong_rand_bytes(100_000)
      assert {:ok, compressed} = Zstd.encode(data, [])
      assert {:ok, decompressed} = Zstd.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for invalid level" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Zstd.encode("data", level: 0)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Zstd.encode("data", level: 23)
    end

    test "handles repeated data efficiently" do
      data = String.duplicate("AAAA", 10_000)
      assert {:ok, compressed} = Zstd.encode(data, [])
      assert byte_size(compressed) < byte_size(data) / 10
    end

    test "round-trips highly compressible data" do
      data = :binary.copy(<<0>>, 1_000_000)
      assert {:ok, compressed} = Zstd.encode(data, [])
      assert {:ok, decompressed} = Zstd.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "decode/2" do
    test "decompresses data" do
      data = :crypto.strong_rand_bytes(1024)
      {:ok, compressed} = Zstd.encode(data, [])
      assert {:ok, decompressed} = Zstd.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for invalid data" do
      assert {:error, _} = Zstd.decode("not compressed", [])
    end

    test "rejects decompress when max_output_size is too small" do
      data = String.duplicate("AAAA", 256)
      {:ok, compressed} = Zstd.encode(data, [])

      assert {:error, %ExCodecs.Error{reason: :output_limit_exceeded}} =
               Zstd.decode(compressed, max_output_size: 8)
    end

    test "rejects invalid max_output_size" do
      {:ok, compressed} = Zstd.encode("hi", [])

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Zstd.decode(compressed, max_output_size: 0)
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Zstd.__codec_info__()
      assert info.name == :zstd
      assert info.category == :compression
      assert info.native? == true
      assert info.streaming? == false
      assert info.configurable? == true
    end
  end
end
