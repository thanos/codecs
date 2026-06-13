defmodule ExCodecs.Compression.CodecVersionTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Compression.{Blosc2, Bzip2, Lz4, Snappy, Zstd}
  alias ExCodecs.Error

  describe "codec_info/0 for all codecs" do
    test "zstd returns complete info" do
      info = Zstd.__codec_info__()
      assert info.name == :zstd
      assert info.category == :compression
      assert info.module == Zstd
      assert info.native? == true
      assert info.streaming? == true
      assert info.configurable? == true
      assert is_binary(info.version)
    end

    test "lz4 returns complete info" do
      info = Lz4.__codec_info__()
      assert info.name == :lz4
      assert info.category == :compression
      assert info.module == Lz4
      assert info.native? == true
      assert info.configurable? == true
      assert is_binary(info.version)
    end

    test "snappy returns complete info" do
      info = Snappy.__codec_info__()
      assert info.name == :snappy
      assert info.category == :compression
      assert info.module == Snappy
      assert info.native? == true
      assert info.configurable? == false
      assert is_binary(info.version)
    end

    test "bzip2 returns complete info" do
      info = Bzip2.__codec_info__()
      assert info.name == :bzip2
      assert info.category == :compression
      assert info.module == Bzip2
      assert info.native? == true
      assert info.configurable? == true
      assert is_binary(info.version)
    end

    test "blosc2 returns complete info" do
      info = Blosc2.__codec_info__()
      assert info.name == :blosc2
      assert info.category == :compression
      assert info.module == Blosc2
      assert info.native? == true
      assert info.streaming? == true
      assert info.configurable? == true
      assert is_binary(info.version)
    end
  end

  describe "compression error paths" do
    test "zstd returns error for corrupt data" do
      assert {:error, _} = ExCodecs.decode(:zstd, <<0, 1, 2, 3>>)
    end

    test "lz4 returns error for corrupt data" do
      assert {:error, _} = ExCodecs.decode(:lz4, <<0, 1, 2, 3>>)
    end

    test "snappy returns error for corrupt data" do
      assert {:error, _} = ExCodecs.decode(:snappy, <<0, 1, 2, 3>>)
    end

    test "bzip2 returns error for corrupt data" do
      assert {:error, _} = ExCodecs.decode(:bzip2, <<0, 1, 2, 3>>)
    end

    test "blosc2 returns error for corrupt data" do
      assert {:error, _} = ExCodecs.decode(:blosc2, <<0, 1, 2, 3>>)
    end

    test "blosc2 returns error for invalid magic" do
      assert {:error, %Error{reason: :invalid_data}} =
               ExCodecs.decode(:blosc2, <<0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>)
    end

    test "blosc2 validates cname option" do
      data = :crypto.strong_rand_bytes(1024)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:blosc2, data, cname: :invalid)
    end

    test "blosc2 validates clevel option" do
      data = :crypto.strong_rand_bytes(1024)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:blosc2, data, clevel: 10)
    end

    test "blosc2 validates shuffle option" do
      data = :crypto.strong_rand_bytes(1024)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:blosc2, data, shuffle: :invalid)
    end

    test "blosc2 validates typesize option" do
      data = :crypto.strong_rand_bytes(1024)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:blosc2, data, typesize: 0)
    end

    test "zstd invalid level returns error" do
      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:zstd, "data", level: 0)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:zstd, "data", level: 23)
    end

    test "bzip2 invalid block_size returns error" do
      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:bzip2, "data", block_size: 0)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:bzip2, "data", block_size: 10)
    end

    test "bzip2 invalid work_factor returns error" do
      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:bzip2, "data", work_factor: 251)
    end

    test "lz4 invalid level returns error" do
      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:lz4, "data", level: 0)

      assert {:error, %Error{reason: :invalid_options}} =
               ExCodecs.encode(:lz4, "data", level: 17)
    end
  end

  describe "compression category" do
    test "Compression.available_codecs returns list" do
      codecs = ExCodecs.Compression.available_codecs()
      assert is_list(codecs)
      assert length(codecs) >= 5
      assert Enum.any?(codecs, &(&1.name == :zstd))
    end

    test "Compression.compress delegates to encode" do
      data = String.duplicate("AAAA", 256)
      {:ok, c1} = ExCodecs.Compression.compress(:zstd, data)
      {:ok, c2} = ExCodecs.encode(:zstd, data)
      assert c1 == c2
    end

    test "Compression.decompress delegates to decode" do
      data = :crypto.strong_rand_bytes(1024)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      {:ok, d1} = ExCodecs.Compression.decompress(:zstd, compressed)
      {:ok, d2} = ExCodecs.decode(:zstd, compressed)
      assert d1 == d2
    end
  end
end
