defmodule ExCodecs.Compression.Bzip2Test do
  use ExUnit.Case, async: true

  alias ExCodecs.Compression.Bzip2

  describe "encode/2" do
    test "compresses data with default block size" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = Bzip2.encode(data, [])
      assert is_binary(compressed)
    end

    test "compresses data with custom block size" do
      data = :crypto.strong_rand_bytes(1024)

      for bs <- 1..9 do
        assert {:ok, _c} = Bzip2.encode(data, block_size: bs)
      end
    end

    test "handles empty data" do
      assert {:ok, compressed} = Bzip2.encode("", [])
      assert {:ok, decompressed} = Bzip2.decode(compressed, [])
      assert decompressed == ""
    end

    test "returns error for invalid block size" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Bzip2.encode("data", block_size: 0)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Bzip2.encode("data", block_size: 10)
    end

    test "returns error for invalid work factor" do
      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               Bzip2.encode("data", work_factor: 251)
    end
  end

  describe "decode/2" do
    test "round-trip preserves data" do
      data = :crypto.strong_rand_bytes(4096)
      {:ok, compressed} = Bzip2.encode(data, [])
      {:ok, decompressed} = Bzip2.decode(compressed, [])
      assert decompressed == data
    end
  end

  describe "__codec_info__/0" do
    test "returns codec metadata" do
      info = Bzip2.__codec_info__()
      assert info.name == :bzip2
      assert info.category == :compression
      assert info.configurable? == true
    end
  end
end
