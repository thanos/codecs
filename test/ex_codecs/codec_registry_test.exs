defmodule ExCodecs.CodecRegistryTest do
  use ExUnit.Case, async: false

  alias ExCodecs.CodecRegistry

  setup do
    # Use the application-owned registry; clean up any names we register.
    names =
      for i <- 1..20 do
        :"registry_test_#{System.unique_integer([:positive])}_#{i}"
      end

    on_exit(fn ->
      Enum.each(names, &CodecRegistry.unregister/1)
    end)

    {:ok, names: names}
  end

  describe "register/3" do
    test "registers a valid codec module", %{names: [name | _]} do
      assert :ok = CodecRegistry.register(name, ExCodecs.Compression.Zstd, :compression)
      assert {:ok, {ExCodecs.Compression.Zstd, :compression, _}} = CodecRegistry.lookup(name)
    end

    test "returns error for invalid module", %{names: [name | _]} do
      assert {:error, {:invalid_codec_module, NonexistentModule}} =
               CodecRegistry.register(name, NonexistentModule, :compression)
    end

    test "returns error for module missing encode/2", %{names: [name | _]} do
      defmodule NoEncode do
        def decode(_data, _opts), do: {:ok, ""}
      end

      assert {:error, {:invalid_codec_module, NoEncode}} =
               CodecRegistry.register(name, NoEncode, :compression)
    end

    test "returns error for module missing decode/2", %{names: [name | _]} do
      defmodule NoDecode do
        def encode(_data, _opts), do: {:ok, ""}
      end

      assert {:error, {:invalid_codec_module, NoDecode}} =
               CodecRegistry.register(name, NoDecode, :compression)
    end
  end

  describe "register_unavailable/2" do
    test "registers codec as unavailable", %{names: [name | _]} do
      assert :ok = CodecRegistry.register_unavailable(name, :compression)
      assert {:ok, {nil, :compression, info}} = CodecRegistry.lookup(name)
      assert info.module == nil
      assert info.native? == false
    end

    test "unavailable codec is not in available_codecs", %{names: [name | _]} do
      CodecRegistry.register_unavailable(name, :compression)
      refute name in CodecRegistry.available_codecs()
    end

    test "unavailable codec shows in all_codecs", %{names: [name | _]} do
      CodecRegistry.register_unavailable(name, :compression)
      assert name in CodecRegistry.all_codecs()
    end
  end

  describe "lookup/1" do
    test "returns error for unknown codec" do
      assert {:error, :unsupported_codec} = CodecRegistry.lookup(:nonexistent_codec_xyz)
    end
  end

  describe "available_codecs/0" do
    test "includes built-in codecs from application start" do
      codecs = CodecRegistry.available_codecs()
      assert :zstd in codecs
      assert :lz4 in codecs
      assert :ply in codecs
      assert :spatial_binary in codecs
      assert :gsplat in codecs
    end

    test "filters available codecs by category" do
      spatial = CodecRegistry.available_codecs(:spatial)
      assert Enum.all?([:gsplat, :ply, :spatial_binary], &(&1 in spatial))
      assert :zstd in CodecRegistry.available_codecs(:compression)
      refute :ply in CodecRegistry.available_codecs(:compression)
    end
  end

  describe "all_codecs/0" do
    test "returns all codecs including unavailable", %{names: [name | _]} do
      CodecRegistry.register_unavailable(name, :compression)
      all = CodecRegistry.all_codecs()
      assert :zstd in all
      assert name in all
    end
  end

  describe "supports?/1" do
    test "returns true for available codecs" do
      assert CodecRegistry.supports?(:zstd) == true
    end

    test "returns false for unavailable codecs", %{names: [name | _]} do
      CodecRegistry.register_unavailable(name, :compression)
      assert CodecRegistry.supports?(name) == false
    end

    test "returns false for unknown codecs" do
      assert CodecRegistry.supports?(:nonexistent_codec_xyz) == false
    end
  end

  describe "codec_info/1" do
    test "returns info for registered codec" do
      assert {:ok, info} = CodecRegistry.codec_info(:zstd)
      assert info.name == :zstd
      assert info.category == :compression
      assert info.module == ExCodecs.Compression.Zstd
    end

    test "returns error for unknown codec" do
      assert {:error, :unsupported_codec} = CodecRegistry.codec_info(:nonexistent_codec_xyz)
    end

    test "returns interface metadata for spatial formats" do
      assert {:ok, info} = CodecRegistry.codec_info(:ply)
      assert info.category == :spatial
      assert info.interface == :spatial
      assert info.configurable?
      assert info.version == "PLY 1.0"
    end
  end

  describe "codecs_by_category/1" do
    test "returns codecs in a category" do
      codecs = CodecRegistry.codecs_by_category(:compression)
      assert length(codecs) >= 2
      names = Enum.map(codecs, & &1.name)
      assert :zstd in names
      assert :lz4 in names
    end

    test "returns empty list for unknown category" do
      assert [] = CodecRegistry.codecs_by_category(:nonexistent_category_xyz)
    end

    test "returns shared-catalog spatial entries" do
      codecs = CodecRegistry.codecs_by_category(:spatial)
      names = Enum.map(codecs, & &1.name)
      assert Enum.all?([:gsplat, :ply, :spatial_binary], &(&1 in names))
      assert Enum.all?(codecs, &(&1.interface == :spatial))
    end
  end

  describe "unregister/1" do
    test "removes a codec entry", %{names: [name | _]} do
      assert :ok = CodecRegistry.register_unavailable(name, :compression)
      assert :ok = CodecRegistry.unregister(name)
      assert {:error, :unsupported_codec} = CodecRegistry.lookup(name)
    end
  end
end
