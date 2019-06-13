defmodule TestParser do
  use Parser
  def parse(%BSON.ObjectId{} = value, :string) do
    BSON.ObjectId.encode!(value)
  end

  def parse(value, :object_id) when is_binary(value) do
    BSON.ObjectId.decode!(value)
  end
end

defmodule TestStruct do
  use Struct
  field(:id)
  field(:value)
end

defmodule NestedStruct do
  use Struct
  field(:id)
  field(:value)
  field(:nested, {:struct, TestStruct})
end

defmodule ArrayStruct do
  use Struct
  field(:array, {:array, {:struct, TestStruct}})
  field(:value, :integer)
end

defmodule MapStruct do
  use Struct
  field(:map, {:map, {:string, {:struct, NestedStruct}}})
  field(:map2, {:map, {:string, :string}})
end

defmodule ObjectIdStruct do
  use Struct, parser: TestParser
  field(:id, :object_id)
end

defmodule Struct.Test do
  use ExUnit.Case

  test "'fields' function" do
    assert Struct.fields(TestStruct) == [:value, :id]
  end

  test "can transform map to struct" do
    assert %{"id" => "test", "value" => "value"}
           |> TestStruct.struct() == %TestStruct{id: "test", value: "value"}
  end

  test "can transform nested schema" do
    assert %{
             "id" => "test",
             "value" => "value",
             "nested" => %{"id" => "nested", "value" => "nested value"}
           }
           |> NestedStruct.struct() ==
             %NestedStruct{
               id: "test",
               value: "value",
               nested: %TestStruct{id: "nested", value: "nested value"}
             }
  end

  test "can transform array schema" do
    assert %{
             "value" => "value",
             "array" => [%{"id" => "nested", "value" => "nested value"}]
           }
           |> ArrayStruct.struct() ==
             %ArrayStruct{value: nil, array: [%TestStruct{id: "nested", value: "nested value"}]}
  end

  test "can transform map struct" do
    assert %MapStruct{} == %MapStruct{map: %{}}
    assert MapStruct.struct() == %MapStruct{map: %{}}
  end

  test "object id" do
    object_id = BSON.ObjectId.new(1, 1, 1, 1)
    id = BSON.ObjectId.encode!(object_id)

    assert ObjectIdStruct.struct(%{
             id: id
           }) == %ObjectIdStruct{
             id: object_id
           }
  end
end
