defmodule ExCodecs.Spatial.Metadata do
  @moduledoc """
  Free-form metadata for spatial clouds.

  ## Fields

    * `:entries` — `%{optional(String.t()) => term()}` arbitrary format or
      application values; defaults to `%{}`. String keys are the public API
      convention.
    * `:comments` — `[String.t()]` ordered human-readable comments; defaults
      to `[]`. No encoding beyond Elixir UTF-8 string conventions is imposed.
    * `:source` — `String.t() | nil` source file, URI, sensor, or producer
      identifier; defaults to `nil`.
    * `:created_at` — `DateTime.t() | nil` creation instant; defaults to `nil`.
      Use a timezone-aware `DateTime`, conventionally UTC.

  ## Example

      iex> created_at = ~U[2026-07-16 12:00:00Z]
      iex> ExCodecs.Spatial.Metadata.new(
      ...>   entries: %{"coordinate_system" => "ENU"},
      ...>   comments: ["Captured after calibration"],
      ...>   source: "sensor://roof-lidar",
      ...>   created_at: created_at
      ...> )
      %ExCodecs.Spatial.Metadata{
        entries: %{"coordinate_system" => "ENU"},
        comments: ["Captured after calibration"],
        source: "sensor://roof-lidar",
        created_at: ~U[2026-07-16 12:00:00Z]
      }
  """

  @typedoc """
  Spatial metadata. See the module documentation for every field, its default,
  units or conventions, and a construction example.
  """
  @type t :: %__MODULE__{
          entries: %{optional(String.t()) => term()},
          comments: [String.t()],
          source: String.t() | nil,
          created_at: DateTime.t() | nil
        }

  defstruct entries: %{},
            comments: [],
            source: nil,
            created_at: nil

  @doc """
  Builds metadata from options.

  ## Arguments

    * `opts` — a keyword list with:
      * `:entries` — an enumerable accepted by `Map.new/1`, conventionally a
        map with string keys; defaults to `%{}`.
      * `:comments` — `[String.t()]`; defaults to `[]`.
      * `:source` — `String.t() | nil`; defaults to `nil`.
      * `:created_at` — `DateTime.t() | nil`; defaults to `nil`.

  ## Returns

  `%Metadata{}`

  ## Raises

  * `FunctionClauseError` if `opts` is not a keyword list.
  * `Protocol.UndefinedError` if `:entries` is not enumerable.
  * `ArgumentError` if an enumerable entry cannot be converted to a map pair.

  ## Examples

      iex> m = ExCodecs.Spatial.Metadata.new(comments: ["hi"], entries: %{"k" => 1})
      iex> m.comments
      ["hi"]
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      entries: Map.new(Keyword.get(opts, :entries, %{})),
      comments: Keyword.get(opts, :comments, []),
      source: Keyword.get(opts, :source),
      created_at: Keyword.get(opts, :created_at)
    }
  end

  @doc """
  Puts a string key into `entries`.

  ## Arguments

    * `meta` — `%Metadata{}`
    * `key` — `String.t()` key.
    * `value` — `term()` to store, replacing an existing value.

  ## Returns

  Updated `%Metadata{}`

  ## Raises

  * `FunctionClauseError` unless `meta` is `%Metadata{}` and `key` is a binary.
  * `BadMapError` if a manually constructed metadata value has a non-map
    `:entries` field.

  ## Examples

      iex> m = ExCodecs.Spatial.Metadata.put(ExCodecs.Spatial.Metadata.new(), "a", 1)
      iex> ExCodecs.Spatial.Metadata.get(m, "a")
      1
  """
  @spec put(t(), String.t(), term()) :: t()
  def put(%__MODULE__{} = meta, key, value) when is_binary(key) do
    %{meta | entries: Map.put(meta.entries, key, value)}
  end

  @doc """
  Appends a comment string.

  ## Arguments

    * `meta` — `%Metadata{}`
    * `comment` — `String.t()` appended after existing comments.

  ## Returns

  Updated `%Metadata{}`

  ## Raises

  * `FunctionClauseError` unless `meta` is `%Metadata{}` and `comment` is a
    binary.
  * `ArgumentError` if a manually constructed metadata value has an improper
    `:comments` list.

  ## Examples

      iex> m = ExCodecs.Spatial.Metadata.add_comment(ExCodecs.Spatial.Metadata.new(), "x")
      iex> m.comments
      ["x"]
  """
  @spec add_comment(t(), String.t()) :: t()
  def add_comment(%__MODULE__{} = meta, comment) when is_binary(comment) do
    %{meta | comments: meta.comments ++ [comment]}
  end

  @doc """
  Fetches an entry by string key.

  ## Arguments

    * `meta` — `%Metadata{}`
    * `key` — `String.t()` to look up.
    * `default` — `term()` returned when the key is absent; defaults to `nil`.

  ## Returns

  Stored value or `default`

  ## Raises

  * `FunctionClauseError` unless `meta` is `%Metadata{}` and `key` is a binary.
  * `BadMapError` if a manually constructed metadata value has a non-map
    `:entries` field.

  ## Examples

      iex> ExCodecs.Spatial.Metadata.get(ExCodecs.Spatial.Metadata.new(), "missing", :nope)
      :nope
  """
  @spec get(t(), String.t(), term()) :: term()
  def get(%__MODULE__{entries: entries}, key, default \\ nil) when is_binary(key) do
    Map.get(entries, key, default)
  end
end
