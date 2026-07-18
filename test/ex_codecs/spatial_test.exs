defmodule ExCodecs.SpatialTest do
  use ExUnit.Case, async: true

  doctest ExCodecs.Spatial

  alias ExCodecs.Spatial
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}

  defmodule CatalogSpatialCodec do
    def encode(%PointCloud{}, []), do: {:ok, "catalog-spatial"}
    def decode("catalog-spatial", []), do: {:ok, PointCloud.new([])}
  end

  describe "available_formats/0" do
    test "lists supported formats" do
      formats = Spatial.available_formats()
      assert Enum.all?([:ply, :spatial_binary, :gsplat], &(&1 in formats))
      assert Spatial.supports?(:ply)
      refute Spatial.supports?(:sog)
    end

    test "spatial formats participate in the shared catalog" do
      assert :ply in ExCodecs.available_codecs()
      spatial = ExCodecs.available_codecs(:spatial)
      assert Enum.all?([:gsplat, :ply, :spatial_binary], &(&1 in spatial))
      assert ExCodecs.supports?(:ply)

      assert {:ok, info} = ExCodecs.codec_info(:ply)
      assert info.category == :spatial
      assert info.interface == :spatial
    end

    test "registered spatial extensions are discovered and dispatched" do
      format = :"spatial_test_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        ExCodecs.CodecRegistry.unregister(format)
      end)

      assert :ok =
               ExCodecs.CodecRegistry.register(
                 format,
                 CatalogSpatialCodec,
                 :spatial,
                 :spatial
               )

      assert format in Spatial.available_formats()
      assert Spatial.supports?(format)

      assert {:ok, "catalog-spatial"} =
               Spatial.encode(PointCloud.new([]), format: format)

      assert {:ok, %PointCloud{points: []}} =
               Spatial.decode("catalog-spatial", format: format)
    end

    test "an unavailable spatial catalog entry returns codec_unavailable" do
      format = :"unavailable_spatial_test_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        ExCodecs.CodecRegistry.unregister(format)
      end)

      assert :ok =
               ExCodecs.CodecRegistry.register_unavailable(format, :spatial, :spatial)

      refute Spatial.supports?(format)

      assert {:error, %ExCodecs.Error{reason: :codec_unavailable, codec: ^format}} =
               Spatial.decode("payload", format: format)
    end
  end

  describe "encode/decode" do
    test "PLY via Spatial API" do
      cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0)])
      assert {:ok, bin} = Spatial.encode(cloud, format: :ply)
      assert {:ok, decoded} = Spatial.decode(bin, format: :ply)
      assert length(decoded.points) == 1
    end

    test "registry API rejects spatial structs and points at Spatial" do
      cloud = PointCloud.new([Point.new(0.0, 1.0, 2.0, color: {9, 8, 7})])

      assert {:error, %ExCodecs.Error{reason: :invalid_data}} =
               ExCodecs.encode(cloud, format: :ply)

      assert {:ok, bin} = Spatial.encode(cloud, format: :ply)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.decode(bin, format: :ply)

      assert {:ok, decoded} = Spatial.decode(bin, format: :ply)
      assert hd(decoded.points).color == {9, 8, 7}

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.encode(:ply, bin)

      assert {:error, %ExCodecs.Error{reason: :invalid_options}} =
               ExCodecs.decode(:ply, bin)
    end

    test "stream decode and encode" do
      cloud =
        PointCloud.new([
          Point.new(0.0, 0.0, 0.0),
          Point.new(1.0, 1.0, 1.0)
        ])

      assert {:ok, bin} = Spatial.encode(cloud, format: :ply)

      points =
        Spatial.stream_decode(bin, format: :ply)
        |> Enum.to_list()

      assert length(points) == 2
      assert {:ok, bin2} = Spatial.stream_encode(points, format: :ply)
      assert {:ok, _} = Spatial.decode(bin2, format: :ply)
    end

    test "stream_encode Gaussian cloud via gsplat" do
      gs = [Gaussian.new({1.0, 2.0, 3.0})]
      assert {:ok, bin} = ExCodecs.stream_encode(gs, format: :gsplat)
      assert {:ok, %GaussianCloud{}} = Spatial.decode(bin, format: :gsplat)
    end
  end

  test "loads example PLY fixtures" do
    path = Path.join([:code.priv_dir(:ex_codecs), "examples", "spatial", "cube_corners.ply"])
    assert {:ok, cloud} = Spatial.decode(File.read!(path), format: :ply)
    assert length(cloud.points) == 4

    gpath = Path.join([:code.priv_dir(:ex_codecs), "examples", "spatial", "two_gaussians.ply"])
    assert {:ok, %GaussianCloud{gaussians: gs}} = Spatial.decode(File.read!(gpath), format: :ply)
    assert length(gs) == 2
  end
end
