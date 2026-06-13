defmodule ExCodecs.Compression.Lz4Test do
  use ExUnit.Case, async: true

  alias ExCodecs.Compression.Lz4

  describe "encode/2" do
    test "compresses data" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = Lz4.encode(data, [])
      assert is_binary(compressed)
    end

    test "compresses data with custom level" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, _c} = Lz4.encode(data, level: 1)
      assert {:ok, _c} = Lz4.encode(data, level: 4)
    end

    test "handles empty data" do
      assert {:ok, compressed} = Lz4.encode("", [])
      assert {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == ""
    end

    test "returns error for invalid level" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Lz4.encode("data", level: 0)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Lz4.encode("data", level: 17)
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = Lz4.encode(data, [])
      {:ok, decompressed} = Lz4.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Lz4.__codec_info__()
      assert info.name == :lz4
      assert info.category == :compression
      assert info.configurable? == true
    end
  end
end
