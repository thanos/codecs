defmodule ExCodecs.Compression.ZstdTest do
  use ExUnit.Case, async: true

  describe "encode/2" do
    test "compresses data with default level" do
      data = String.duplicate("AAAA", 256)
      assert {:ok, compressed} = ExCodecs.Compression.Zstd.encode(data, [])
      assert is_binary(compressed)
      assert byte_size(compressed) < byte_size(data)
    end

    test "compresses data with custom level" do
      data = :crypto.strong_rand_bytes(1024)

      for level <- 1..22 do
        assert {:ok, _compressed} = ExCodecs.Compression.Zstd.encode(data, level: level)
      end
    end

    test "handles empty data" do
      assert {:ok, compressed} = ExCodecs.Compression.Zstd.encode("", [])
      assert {:ok, ""} = ExCodecs.Compression.Zstd.decode(compressed, [])
    end

    test "handles single byte data" do
      assert {:ok, compressed} = ExCodecs.Compression.Zstd.encode(<<42>>, [])
      assert {:ok, <<42>>} = ExCodecs.Compression.Zstd.decode(compressed, [])
    end

    test "handles large data" do
      data = :crypto.strong_rand_bytes(100_000)
      assert {:ok, compressed} = ExCodecs.Compression.Zstd.encode(data, [])
      assert {:ok, decompressed} = ExCodecs.Compression.Zstd.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for invalid level" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.Compression.Zstd.encode("data", level: 0)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.Compression.Zstd.encode("data", level: 23)
    end

    test "handles repeated data efficiently" do
      data = String.duplicate("AAAA", 10000)
      assert {:ok, compressed} = ExCodecs.Compression.Zstd.encode(data, [])
      assert byte_size(compressed) < byte_size(data) / 10
    end

    test "higher levels produce smaller output" do
      data = :crypto.strong_rand_bytes(10000)
      {:ok, c1} = ExCodecs.Compression.Zstd.encode(data, level: 1)
      {:ok, c19} = ExCodecs.Compression.Zstd.encode(data, level: 19)
      assert byte_size(c19) <= byte_size(c1)
    end
  end

  describe "decode/2" do
    test "decompresses data" do
      data = :crypto.strong_rand_bytes(1024)
      {:ok, compressed} = ExCodecs.Compression.Zstd.encode(data, [])
      assert {:ok, decompressed} = ExCodecs.Compression.Zstd.decode(compressed, [])
      assert decompressed == data
    end

    test "returns error for invalid data" do
      assert {:error, _} = ExCodecs.Compression.Zstd.decode("not compressed", [])
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = ExCodecs.Compression.Zstd.__codec_info__()
      assert info.name == :zstd
      assert info.category == :compression
      assert info.native? == true
      assert info.streaming? == true
      assert info.configurable? == true
    end
  end

  describe "round-trip property" do
    test "zstd round-trip preserves random data" do
      for _ <- 1..50 do
        size = :rand.uniform(10000)
        data = :crypto.strong_rand_bytes(size)
        {:ok, compressed} = ExCodecs.Compression.Zstd.encode(data, [])
        {:ok, decompressed} = ExCodecs.Compression.Zstd.decode(compressed, [])
        assert decompressed == data
      end
    end
  end
end
