defmodule ExCodecs.Spatial.Codec.BinaryTest do
  use ExUnit.Case, async: true

  alias ExCodecs.Spatial.Codec.Binary
  alias ExCodecs.Spatial.{Point, PointCloud}

  test "round-trips colored points with normals" do
    cloud =
      PointCloud.new([
        Point.new(1.0, 2.0, 3.0, color: {10, 20, 30}, normal: {0.0, 1.0, 0.0}),
        Point.new(4.0, 5.0, 6.0, color: {40, 50, 60}, normal: {1.0, 0.0, 0.0})
      ])

    assert {:ok, bin} = Binary.encode(cloud)
    assert String.starts_with?(bin, "EXCP")
    assert {:ok, decoded} = Binary.decode(bin)
    assert length(decoded.points) == 2
    assert hd(decoded.points).color == {10, 20, 30}
    assert hd(decoded.points).normal == {0.0, 1.0, 0.0}
  end

  test "round-trips RGBA" do
    cloud = PointCloud.new([Point.new(0, 0, 0, color: {1, 2, 3, 4})])
    assert {:ok, bin} = Binary.encode(cloud)
    assert {:ok, decoded} = Binary.decode(bin)
    assert hd(decoded.points).color == {1, 2, 3, 4}
  end

  test "rejects bad magic" do
    assert {:error, %{reason: :invalid_data}} =
             Binary.decode(<<"XXXX", 0, 1, 0, 0, 0, 0, 0, 0, 0, 0>>)
  end

  test "stream_decode from file yields points incrementally" do
    cloud =
      PointCloud.new([
        Point.new(1.0, 2.0, 3.0, color: {10, 20, 30}),
        Point.new(4.0, 5.0, 6.0, color: {40, 50, 60})
      ])

    assert {:ok, bin} = Binary.encode(cloud)

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_excp_stream_#{System.unique_integer([:positive])}.excp"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, bin)

    points = Binary.stream_decode(path, source: :file) |> Enum.to_list()
    assert length(points) == 2
    assert hd(points).color == {10, 20, 30}

    # :auto path detection
    assert [%Point{}, %Point{}] =
             Binary.stream_decode(path) |> Enum.to_list()
  end

  test "stream_decode from truncated file yields invalid_data" do
    cloud = PointCloud.new([Point.new(1.0, 2.0, 3.0), Point.new(4.0, 5.0, 6.0)])
    assert {:ok, bin} = Binary.encode(cloud)
    # Header (16) + one incomplete xyz record
    truncated = binary_part(bin, 0, 20)

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_excp_trunc_#{System.unique_integer([:positive])}.excp"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, truncated)

    assert [{:error, %{reason: :invalid_data, codec: :spatial_binary}}] =
             Binary.stream_decode(path, source: :file) |> Enum.to_list()
  end

  test "stream_decode missing file yields io_error" do
    assert [{:error, %{reason: :io_error, codec: :spatial_binary}}] =
             Binary.stream_decode("/no/such/ex_codecs.excp", source: :file) |> Enum.to_list()
  end

  test "stream_encode_to_file with schema round-trips" do
    points = [
      Point.new(1.0, 2.0, 3.0, color: {10, 20, 30}),
      Point.new(4.0, 5.0, 6.0, color: {40, 50, 60})
    ]

    path =
      Path.join(
        System.tmp_dir!(),
        "ex_codecs_excp_enc_#{System.unique_integer([:positive])}.excp"
      )

    on_exit(fn -> File.rm(path) end)

    assert :ok = Binary.stream_encode_to_file(points, path, schema: [:color])
    assert {:ok, <<"EXCP", _::binary>> = bin} = File.read(path)
    assert {:ok, decoded} = Binary.decode(bin)
    assert length(decoded.points) == 2
    assert hd(decoded.points).color == {10, 20, 30}
  end

  test "stream_encode_to_file requires schema" do
    assert {:error, %{reason: :invalid_options}} =
             Binary.stream_encode_to_file([Point.new(0, 0, 0)], "x.excp")
  end
end
