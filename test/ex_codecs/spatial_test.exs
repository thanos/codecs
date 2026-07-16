defmodule ExCodecs.SpatialTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial
  alias ExCodecs.Spatial.{Gaussian, GaussianCloud, Point, PointCloud}

  describe "available_formats/0" do
    test "lists supported formats" do
      assert :ply in Spatial.available_formats()
      assert :gsplat in Spatial.available_formats()
      assert Spatial.supports?(:ply)
      refute Spatial.supports?(:sog)
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
