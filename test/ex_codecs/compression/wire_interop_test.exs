defmodule ExCodecs.Compression.WireInteropTest do
  use ExUnit.Case, async: true

  @moduletag :wire_interop

  @fixture_root Path.expand("../../fixtures", __DIR__)

  describe "zstd CLI golden frame" do
    test "decompresses level3.bin from zstd(1)" do
      src = File.read!(Path.join(@fixture_root, "zstd/level3.src"))
      bin = File.read!(Path.join(@fixture_root, "zstd/level3.bin"))

      assert {:ok, ^src} = ExCodecs.decode(:zstd, bin)
    end
  end

  describe "bzip2 CLI golden stream" do
    test "decompresses default.bin from bzip2(1)" do
      src = File.read!(Path.join(@fixture_root, "bzip2/default.src"))
      bin = File.read!(Path.join(@fixture_root, "bzip2/default.bin"))

      assert {:ok, ^src} = ExCodecs.decode(:bzip2, bin)
    end
  end

  describe "lz4_flex size-prepended golden" do
    test "decompresses size_prepended.bin from lz4_flex" do
      src = File.read!(Path.join(@fixture_root, "lz4/size_prepended.src"))
      bin = File.read!(Path.join(@fixture_root, "lz4/size_prepended.bin"))

      assert {:ok, ^src} = ExCodecs.decode(:lz4, bin)
    end
  end

  describe "snap raw golden" do
    test "decompresses raw.bin from snap::raw" do
      src = File.read!(Path.join(@fixture_root, "snappy/raw.src"))
      bin = File.read!(Path.join(@fixture_root, "snappy/raw.bin"))

      assert {:ok, ^src} = ExCodecs.decode(:snappy, bin)
    end
  end
end
