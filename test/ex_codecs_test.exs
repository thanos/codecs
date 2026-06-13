defmodule ExCodecsTest do
  use ExUnit.Case, async: true

  describe "encode/3 with :zstd" do
    test "compresses binary data" do
      data = String.duplicate("AAAA", 256)
      assert {:ok, compressed} = ExCodecs.encode(:zstd, data)
      assert is_binary(compressed)
      assert byte_size(compressed) < byte_size(data)
    end

    test "compresses with custom level" do
      data = String.duplicate("AAAA", 256)
      assert {:ok, c1} = ExCodecs.encode(:zstd, data, level: 1)
      assert {:ok, c22} = ExCodecs.encode(:zstd, data, level: 22)
      assert is_binary(c1)
      assert is_binary(c22)
    end

    test "handles empty data" do
      assert {:ok, compressed} = ExCodecs.encode(:zstd, "")
      assert {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == ""
    end

    test "handles small data" do
      assert {:ok, compressed} = ExCodecs.encode(:zstd, "a")
      assert {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == "a"
    end
  end

  describe "decode/3 with :zstd" do
    test "decompresses zstd-compressed data" do
      data = :crypto.strong_rand_bytes(1024)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      assert {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == data
    end
  end

  describe "encode/decode round-trip" do
    test "zstd round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      {:ok, decompressed} = ExCodecs.decode(:zstd, compressed)
      assert decompressed == data
    end

    test "lz4 round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.encode(:lz4, data)
      {:ok, decompressed} = ExCodecs.decode(:lz4, compressed)
      assert decompressed == data
    end

    test "snappy round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.encode(:snappy, data)
      {:ok, decompressed} = ExCodecs.decode(:snappy, compressed)
      assert decompressed == data
    end

    test "bzip2 round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.encode(:bzip2, data)
      {:ok, decompressed} = ExCodecs.decode(:bzip2, compressed)
      assert decompressed == data
    end

    test "blosc2 round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.encode(:blosc2, data)
      {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      assert decompressed == data
    end

    test "blosc2 round-trip with zstd" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = ExCodecs.encode(:blosc2, data, cname: :zstd, clevel: 5, shuffle: :byte)
      {:ok, decompressed} = ExCodecs.decode(:blosc2, compressed)
      assert decompressed == data
    end
  end

  describe "error handling" do
    test "unsupported codec returns error" do
      result = ExCodecs.encode(:unknown_codec, "data")
      assert match?({:error, %ExCodecs.Error{reason: :unsupported_codec}}, result)
    end

    test "invalid data type returns error for encode" do
      assert {:error, %ExCodecs.Error{reason: :invalid_data}} = ExCodecs.encode(:zstd, 123)
    end

    test "invalid data type returns error for decode" do
      assert {:error, %ExCodecs.Error{reason: :invalid_data}} = ExCodecs.decode(:zstd, 123)
    end

    test "invalid options return error for zstd" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.encode(:zstd, "data", level: 99)
    end

    test "invalid options return error for bzip2" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.encode(:bzip2, "data", block_size: 20)
    end

    test "decompressing invalid data returns error" do
      result = ExCodecs.decode(:zstd, "not compressed data")
      assert match?({:error, %ExCodecs.Error{}}, result)
    end

    test "decode with unsupported codec returns error" do
      result = ExCodecs.decode(:unknown_codec, <<1, 2, 3>>)
      assert match?({:error, %ExCodecs.Error{reason: :unsupported_codec}}, result)
    end
  end

  describe "available_codecs/0" do
    test "returns list of available codecs" do
      codecs = ExCodecs.available_codecs()
      assert is_list(codecs)
      assert :zstd in codecs
    end
  end

  describe "supports?/1" do
    test "returns true for supported codecs" do
      assert ExCodecs.supports?(:zstd) == true
      assert ExCodecs.supports?(:lz4) == true
      assert ExCodecs.supports?(:snappy) == true
      assert ExCodecs.supports?(:bzip2) == true
      assert ExCodecs.supports?(:blosc2) == true
    end

    test "returns false for unknown codecs" do
      assert ExCodecs.supports?(:nonexistent) == false
    end
  end

  describe "codec_info/1" do
    test "returns info for zstd" do
      assert {:ok, info} = ExCodecs.codec_info(:zstd)
      assert info.name == :zstd
      assert info.category == :compression
    end

    test "returns error for unknown codec" do
      assert {:error, :unsupported_codec} = ExCodecs.codec_info(:nonexistent)
    end
  end

  describe "encode with non-binary data" do
    test "returns error for integer" do
      assert {:error, %ExCodecs.Error{}} = ExCodecs.encode(:zstd, 42)
    end

    test "returns error for list" do
      assert {:error, %ExCodecs.Error{}} = ExCodecs.encode(:zstd, [1, 2, 3])
    end

    test "returns error for nil" do
      assert {:error, %ExCodecs.Error{}} = ExCodecs.encode(:zstd, nil)
    end
  end

  describe "decode with non-binary data" do
    test "returns error for integer" do
      assert {:error, %ExCodecs.Error{}} = ExCodecs.decode(:zstd, 42)
    end

    test "returns error for list" do
      assert {:error, %ExCodecs.Error{}} = ExCodecs.decode(:zstd, [1, 2, 3])
    end
  end
end