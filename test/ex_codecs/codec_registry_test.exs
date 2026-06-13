defmodule ExCodecs.CodecRegistryTest do
  use ExUnit.Case, async: false

  alias ExCodecs.CodecRegistry

  setup do
    Code.ensure_compiled(ExCodecs.Native)
    :ok
  end

  describe "available_codecs/0" do
    test "returns list of registered codecs" do
      codecs = CodecRegistry.available_codecs()
      assert is_list(codecs)
      assert :zstd in codecs
      assert :lz4 in codecs
      assert :snappy in codecs
      assert :bzip2 in codecs
      assert :blosc2 in codecs
    end
  end

  describe "supports?/1" do
    test "returns true for supported codecs" do
      assert CodecRegistry.supports?(:zstd) == true
      assert CodecRegistry.supports?(:lz4) == true
    end

    test "returns false for unsupported codecs" do
      assert CodecRegistry.supports?(:nonexistent) == false
    end
  end

  describe "codec_info/1" do
    test "returns codec info for known codec" do
      assert {:ok, info} = CodecRegistry.codec_info(:zstd)
      assert info.name == :zstd
      assert info.category == :compression
    end

    test "returns error for unknown codec" do
      assert {:error, :unsupported_codec} = CodecRegistry.codec_info(:nonexistent)
    end
  end

  describe "codecs_by_category/1" do
    test "returns compression codecs" do
      codecs = CodecRegistry.codecs_by_category(:compression)
      assert is_list(codecs)
      assert length(codecs) >= 5
    end
  end
end
