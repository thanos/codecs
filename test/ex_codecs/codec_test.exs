defmodule ExCodecs.CodecTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Codec

  describe "Codec struct" do
    test "has required fields" do
      codec = %Codec{
        name: :zstd,
        category: :compression,
        module: ExCodecs.Compression.Zstd,
        native?: true,
        streaming?: true,
        configurable?: true,
        version: "1.5.6"
      }

      assert codec.name == :zstd
      assert codec.category == :compression
      assert codec.module == ExCodecs.Compression.Zstd
      assert codec.native? == true
      assert codec.streaming? == true
      assert codec.configurable? == true
      assert codec.version == "1.5.6"
    end

    test "has default values" do
      codec = %Codec{name: :test}
      assert codec.category == nil
      assert codec.module == nil
      assert codec.native? == nil
      assert codec.streaming? == nil
      assert codec.configurable? == nil
      assert codec.version == nil
    end
  end

  describe "validates?/1" do
    test "returns true for valid codec modules" do
      assert Codec.validates?(ExCodecs.Compression.Zstd) == true
      assert Codec.validates?(ExCodecs.Compression.Lz4) == true
      assert Codec.validates?(ExCodecs.Compression.Snappy) == true
      assert Codec.validates?(ExCodecs.Compression.Bzip2) == true
      assert Codec.validates?(ExCodecs.Compression.Blosc2) == true
    end

    test "returns false for invalid module" do
      assert Codec.validates?(NonexistentModule) == false
    end

    test "returns false for module without encode/decode" do
      assert Codec.validates?(Enum) == false
    end
  end
end
