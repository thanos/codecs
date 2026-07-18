defmodule ExCodecs.Spatial.TypesTest do
  use ExUnit.Case, async: true

  doctest ExCodecs.Spatial.Gaussian
  doctest ExCodecs.Spatial.GaussianCloud
  doctest ExCodecs.Spatial.Metadata
  doctest ExCodecs.Spatial.Transform
  doctest ExCodecs.Spatial.PointCloud

  alias ExCodecs.Spatial.{
    Bounds,
    Gaussian,
    GaussianCloud,
    Metadata,
    Point,
    PointCloud,
    Transform
  }

  describe "PointCloud" do
    test "size, colored?, normals, add_point, with_bounds" do
      empty = PointCloud.new([])
      assert PointCloud.size(empty) == 0
      refute PointCloud.colored?(empty)
      refute PointCloud.has_normals?(empty)

      p1 = Point.new(0, 0, 0, color: {1, 2, 3}, normal: {0.0, 1.0, 0.0})
      p2 = Point.new(1, 1, 1, color: {4, 5, 6}, normal: {1.0, 0.0, 0.0})
      cloud = PointCloud.new([p1], compute_bounds: false)
      assert cloud.bounds == nil

      cloud = PointCloud.add_point(cloud, p2)
      assert PointCloud.size(cloud) == 2
      assert PointCloud.colored?(cloud)
      assert PointCloud.has_normals?(cloud)
      assert cloud.bounds.max_x == 1.0

      cloud = PointCloud.with_bounds(%{cloud | bounds: nil})
      assert %Bounds{} = cloud.bounds
    end
  end

  describe "GaussianCloud" do
    test "size and with_bounds" do
      cloud = GaussianCloud.new([Gaussian.new({1, 2, 3})], compute_bounds: false)
      assert GaussianCloud.size(cloud) == 1
      assert cloud.bounds == nil
      cloud = GaussianCloud.with_bounds(cloud)
      assert cloud.bounds.min_x == 1.0
    end
  end

  describe "Metadata" do
    test "put, get, add_comment" do
      meta = Metadata.new(source: "test")
      meta = Metadata.put(meta, "crs", "EPSG:4326")
      meta = Metadata.add_comment(meta, "hello")
      assert Metadata.get(meta, "crs") == "EPSG:4326"
      assert Metadata.get(meta, "missing", :default) == :default
      assert meta.comments == ["hello"]
      assert meta.source == "test"
    end
  end

  describe "Transform" do
    test "identity and new" do
      assert Transform.identity().scale == 1.0

      t =
        Transform.new(
          translation: {1, 2, 3},
          rotation: {0.5, 0.5, 0.5, 0.5},
          scale: 2
        )

      assert t.translation == {1.0, 2.0, 3.0}
      assert t.scale == 2.0
    end
  end
end
