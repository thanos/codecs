defmodule ExCodecs.CodecRegistryTest do
  use ExUnit.Case, async: false

  alias ExCodecs.CodecRegistry

  setup do
    CodecRegistry.start_link([])
    :ok
  end

  describe "register/3" do
    test "registers a valid codec module" do
      assert :ok = CodecRegistry.register(:zstd, ExCodecs.Compression.Zstd, :compression)
      assert {:ok, {ExCodecs.Compression.Zstd, :compression, _}} = CodecRegistry.lookup(:zstd)
    end

    test "returns error for invalid module" do
      assert {:error, {:invalid_codec_module, NonexistentModule}} =
               CodecRegistry.register(:fake, NonexistentModule, :compression)
    end

    test "returns error for module missing encode/2" do
      defmodule NoEncode do
        def decode(_data, _opts), do: {:ok, ""}
      end

      assert {:error, {:invalid_codec_module, NoEncode}} =
               CodecRegistry.register(:no_encode, NoEncode, :compression)
    end

    test "returns error for module missing decode/2" do
      defmodule NoDecode do
        def encode(_data, _opts), do: {:ok, ""}
      end

      assert {:error, {:invalid_codec_module, NoDecode}} =
               CodecRegistry.register(:no_decode, NoDecode, :compression)
    end
  end

  describe "register_unavailable/2" do
    test "registers codec as unavailable" do
      assert :ok = CodecRegistry.register_unavailable(:future_codec, :compression)
      assert {:ok, {nil, :compression, info}} = CodecRegistry.lookup(:future_codec)
      assert info.module == nil
      assert info.native? == false
    end

    test "unavailable codec is not in available_codecs" do
      CodecRegistry.register_unavailable(:unavail, :compression)
      refute :unavail in CodecRegistry.available_codecs()
    end

    test "unavailable codec shows in all_codecs" do
      CodecRegistry.register_unavailable(:unavail, :compression)
      assert :unavail in CodecRegistry.all_codecs()
    end
  end

  describe "lookup/1" do
    test "returns error for unknown codec" do
      assert {:error, :unsupported_codec} = CodecRegistry.lookup(:nonexistent)
    end
  end

  describe "available_codecs/0" do
    test "returns list of available codec names" do
      CodecRegistry.register(:zstd, ExCodecs.Compression.Zstd, :compression)
      CodecRegistry.register(:lz4, ExCodecs.Compression.Lz4, :compression)
      codecs = CodecRegistry.available_codecs()
      assert :zstd in codecs
      assert :lz4 in codecs
    end
  end

  describe "all_codecs/0" do
    test "returns all codecs including unavailable" do
      CodecRegistry.register(:zstd, ExCodecs.Compression.Zstd, :compression)
      CodecRegistry.register_unavailable(:future_codec, :compression)
      all = CodecRegistry.all_codecs()
      assert :zstd in all
      assert :future_codec in all
    end
  end

  describe "supports?/1" do
    test "returns true for available codecs" do
      CodecRegistry.register(:zstd, ExCodecs.Compression.Zstd, :compression)
      assert CodecRegistry.supports?(:zstd) == true
    end

    test "returns false for unavailable codecs" do
      CodecRegistry.register_unavailable(:future_codec, :compression)
      assert CodecRegistry.supports?(:future_codec) == false
    end

    test "returns false for unknown codecs" do
      assert CodecRegistry.supports?(:nonexistent) == false
    end
  end

  describe "codec_info/1" do
    test "returns info for registered codec" do
      CodecRegistry.register(:zstd, ExCodecs.Compression.Zstd, :compression)
      assert {:ok, info} = CodecRegistry.codec_info(:zstd)
      assert info.name == :zstd
      assert info.category == :compression
      assert info.module == ExCodecs.Compression.Zstd
    end

    test "returns error for unknown codec" do
      assert {:error, :unsupported_codec} = CodecRegistry.codec_info(:nonexistent)
    end
  end

  describe "codecs_by_category/1" do
    test "returns codecs in a category" do
      CodecRegistry.register(:zstd, ExCodecs.Compression.Zstd, :compression)
      CodecRegistry.register(:lz4, ExCodecs.Compression.Lz4, :compression)
      codecs = CodecRegistry.codecs_by_category(:compression)
      assert length(codecs) >= 2
      names = Enum.map(codecs, & &1.name)
      assert :zstd in names
      assert :lz4 in names
    end

    test "returns empty list for unknown category" do
      assert [] = CodecRegistry.codecs_by_category(:nonexistent)
    end
  end
end
