defmodule ExCodecs.CodecTest do
  use ExUnit.Case, async: true

  doctest ExCodecs.Codec

  alias ExCodecs.Codec

  describe "Codec struct" do
    test "defaults interface to :binary" do
      codec = %Codec{name: :test}
      assert codec.interface == :binary
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
