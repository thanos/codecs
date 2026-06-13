defmodule ExCodecs.Compression.Blosc2Test do
  use ExUnit.Case, async: true

  alias ExCodecs.Compression.Blosc2

  describe "encode/2" do
    test "compresses data with default options" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = Blosc2.encode(data, [])
      assert is_binary(compressed)
    end

    test "compresses data with zstd codec" do
      data = :crypto.strong_rand_bytes(4096)

      assert {:ok, compressed} =
               Blosc2.encode(data, cname: :zstd, clevel: 5)

      assert {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end

    test "compresses data with different shuffle modes" do
      data = :crypto.strong_rand_bytes(4096)

      for shuffle <- [:none, :byte, :bit] do
        assert {:ok, compressed} =
                 Blosc2.encode(data, shuffle: shuffle)

        assert {:ok, decompressed} = Blosc2.decode(compressed, [])
        assert decompressed == data
      end
    end

    test "validates cname option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", cname: :invalid)
    end

    test "validates clevel option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", clevel: 10)
    end

    test "validates shuffle option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", shuffle: :invalid)
    end

    test "validates typesize option" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Blosc2.encode("data", typesize: 0)
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = Blosc2.encode(data, [])
      {:ok, decompressed} = Blosc2.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Blosc2.__codec_info__()
      assert info.name == :blosc2
      assert info.category == :compression
      assert info.configurable? == true
    end
  end
end
