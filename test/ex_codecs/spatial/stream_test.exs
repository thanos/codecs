defmodule ExCodecs.Spatial.StreamTest do
  use ExUnit.Case, async: true

  doctest ExCodecs.Spatial.Stream

  alias ExCodecs.Spatial
  alias ExCodecs.Spatial.{Gaussian, Point, PointCloud}

  test "stream encode empty clouds" do
    assert {:ok, ply} = Spatial.stream_encode([], format: :ply)
    assert {:ok, %PointCloud{points: []}} = Spatial.decode(ply, format: :ply)

    assert {:ok, bin} = Spatial.stream_encode([], format: :spatial_binary)
    assert {:ok, %PointCloud{points: []}} = Spatial.decode(bin, format: :spatial_binary)

    assert {:ok, gspl} = Spatial.stream_encode([], format: :gsplat)
    assert {:ok, %{gaussians: []}} = Spatial.decode(gspl, format: :gsplat)
  end

  test "stream decode unsupported format yields error" do
    assert [{:error, %{reason: :unsupported_codec}}] =
             Spatial.stream_decode(<<>>, format: :sog) |> Enum.to_list()
  end

  test "stream encode rejects non-spatial items" do
    assert {:error, %{reason: :invalid_data}} =
             Spatial.stream_encode([:nope], format: :ply)
  end

  test "stream decode spatial_binary and gsplat binaries" do
    cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0)])
    {:ok, bin} = Spatial.encode(cloud, format: :spatial_binary)

    points = Spatial.stream_decode(bin, format: :spatial_binary) |> Enum.to_list()
    assert length(points) == 1

    gs = [Gaussian.new({0.0, 0.0, 0.0})]
    {:ok, gbin} = Spatial.stream_encode(gs, format: :gsplat)
    items = Spatial.stream_decode(gbin, format: :gsplat) |> Enum.to_list()
    assert length(items) == 1
  end

  test "encode rejects wrong type for format" do
    cloud = PointCloud.new([Point.new(0, 0, 0)])
    assert {:error, %{codec: :gsplat}} = Spatial.encode(cloud, format: :gsplat)

    gcloud = Spatial.GaussianCloud.new([Gaussian.new({0, 0, 0})])

    assert {:error, %{codec: :spatial_binary}} =
             Spatial.encode(gcloud, format: :spatial_binary)

    assert {:error, %{reason: :unsupported_codec}} =
             Spatial.encode(cloud, format: :unknown)

    assert {:error, %{reason: :invalid_data}} = Spatial.encode(:nope, format: :ply)
    assert {:error, %{reason: :invalid_data}} = Spatial.decode(123, format: :ply)
  end

  test "registry decode with format: points at Spatial category" do
    assert {:error, %{reason: :invalid_options, message: message}} =
             ExCodecs.decode(<<"ply\n">>, format: :ply)

    assert message =~ "ExCodecs.Spatial.decode"
  end

  test "top-level stream helpers still delegate to Spatial" do
    cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0)])
    {:ok, bin} = Spatial.encode(cloud, format: :ply)
    assert [%Point{}] = ExCodecs.stream_decode(bin, format: :ply) |> Enum.to_list()
  end

  test "encode_to_file with schema streams EXCP" do
    alias ExCodecs.Spatial.Stream, as: SpatialStream

    points = [Point.new(1.0, 2.0, 3.0, color: {1, 2, 3})]

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_stream_enc_#{System.unique_integer([:positive])}.excp"
      )

    on_exit(fn -> File.rm(path) end)

    assert :ok =
             SpatialStream.encode_to_file(points, path,
               format: :spatial_binary,
               schema: [:color]
             )

    assert [%Point{color: {1, 2, 3}}] =
             Spatial.stream_decode(path, format: :spatial_binary, source: :file) |> Enum.to_list()
  end

  test "encode_to_file schema requires EXCP or GSPL format" do
    alias ExCodecs.Spatial.Stream, as: SpatialStream

    assert {:error, %{reason: :invalid_options}} =
             SpatialStream.encode_to_file([Point.new(0, 0, 0)], "x.ply",
               format: :ply,
               schema: []
             )
  end
end
