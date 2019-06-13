defmodule Struct do
  @default_constructor :struct
  require Parser

  def fields(struct) do
    Enum.map(struct.__meta__, fn {field, _} -> field end)
  end

  defmacro __using__(opts) do
    opts =
      cond do
        is_atom(opts) ->
          [name: opts]

        is_list(opts) ->
          opts

        true ->
          raise "argument must be atom (constructor name) or keyword list (opts)"
      end

    inherits = opts[:inherits] || nil
    constructor_name = opts[:constructor_name] || @default_constructor

    quote do
      import unquote(__MODULE__)

      Module.put_attribute(__MODULE__, :bgr_struct, true)
      Module.register_attribute(__MODULE__, :bgr_struct_fields, accumulate: true)
      Module.put_attribute(__MODULE__, :bgr_struct_inherits, unquote(inherits))
      Module.put_attribute(__MODULE__, :bgr_struct_constructor, unquote(constructor_name))
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro field(name, type \\ :any, opts \\ [default: nil]) do
    quote do
      @bgr_struct_fields {unquote(name), {unquote(type), unquote(opts)}}
    end
  end

  defmacro __before_compile__(env) do
    inherits = Module.get_attribute(env.module, :bgr_struct_inherits) || nil
    fields = Module.get_attribute(env.module, :bgr_struct_fields) || []
    constructor_name = Module.get_attribute(env.module, :bgr_struct_constructor)

    meta =
      cond do
        is_nil(inherits) -> fields
        Parser.has_meta?(inherits) -> inherits.__meta__ ++ fields
        Parser.is_struct(inherits) -> struct_to_meta(inherits) ++ fields
        true -> struct_to_meta(struct(inherits)) ++ fields
      end

    quote do
      def __meta__, do: unquote(meta)
      defstruct unquote(meta_to_struct(meta))
      unquote(defconstructor(constructor_name))

      @behaviour Access
      def fetch(struct, key), do: Map.fetch(struct, key)

      def get(struct, key, default \\ nil) do
        case struct do
          %{^key => value} -> value
          _else -> default
        end
      end

      def put(struct, key, val) do
        if Map.has_key?(struct, key) do
          Map.put(struct, key, val)
        else
          struct
        end
      end

      def delete(struct, key) do
        put(struct, key, %__MODULE__{}[key])
      end

      def get_and_update(struct, key, fun) when is_function(fun, 1) do
        current = get(struct, key)

        case fun.(current) do
          {get, update} ->
            {get, put(struct, key, update)}

          :pop ->
            {current, delete(struct, key)}

          other ->
            raise "the given function must return a two-element tuple or :pop, got: #{
                    inspect(other)
                  }"
        end
      end

      def pop(struct, key, default \\ nil) do
        val = get(struct, key, default)
        updated = delete(struct, key)
        {val, updated}
      end

      defimpl Enumerable, for: unquote(env.module) do
        defp to_list(enumerable) do
          list =
            enumerable
            |> Map.from_struct()
            |> Map.to_list()

          [{:__struct__, unquote(env.module)} | list]
        end

        def slice(enumerable) do
          Enumerable.List.slice(to_list(enumerable))
        end

        def count(enumerable) do
          Enumerable.List.count(to_list(enumerable))
        end

        def member?(enumerable, element) do
          Enumerable.List.member?(to_list(enumerable), element)
        end

        def reduce(enumerable, acc, fun) do
          Enumerable.List.reduce(to_list(enumerable), acc, fun)
        end
      end
    end
  end

  defp struct_to_meta(struct) do
    Enum.map(Map.from_struct(struct), fn {key, value} ->
      {key, {:any, [default: value]}}
    end)
  end

  defp meta_to_struct(meta) do
    Enum.reduce(meta, [], fn {name, {type, opts}}, acc ->
      default =
        if is_nil(opts[:default]),
          do: Macro.escape(Parser.default_by_type(type)),
          else: opts[:default]

      acc ++ [{name, default}]
    end)
  end

  def defconstructor(name) do
    quote do
      def unquote(name)(map_or_kwlist \\ %{}) do
        Parser.parse(map_or_kwlist, {:struct, __MODULE__})
      end
    end
  end
end
