defmodule ExCodecs.CompressionTest do
  use ExUnit.Case, async: true

  doctest ExCodecs.Compression

  describe "available_codecs/0" do
    test "returns compression codecs" do
      codecs = ExCodecs.Compression.available_codecs()
      assert is_list(codecs)
      assert length(codecs) >= 5
    end
  end

  describe "compress/3" do
    test "delegates to encode" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, c1} = ExCodecs.Compression.compress(:zstd, data)
      assert {:ok, c2} = ExCodecs.encode(:zstd, data)
      assert c1 == c2
    end
  end

  describe "decompress/3" do
    test "delegates to decode" do
      data = :crypto.strong_rand_bytes(1024)
      {:ok, compressed} = ExCodecs.encode(:zstd, data)
      assert {:ok, d1} = ExCodecs.Compression.decompress(:zstd, compressed)
      assert {:ok, d2} = ExCodecs.decode(:zstd, compressed)
      assert d1 == d2
    end
  end
end
