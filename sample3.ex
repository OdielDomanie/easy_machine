defmodule Sample3SM do
  use EasyMachine, svg_file: true

  @init_state :init
  def init_data, do: nil

  def action_j(data, _event), do: {data, :some_command}
  def action_k(data, _event), do: {data, :some_other_command}
  def query_fun(_data, _event), do: :no

  state :init do
    :init_event -> [:state_a, :sub_state_x] \\ &action_j/2
  end

  state [:state_a | sub_state] do
    :event_x ->
      [:state_a | sub_state] \\ &action_k/2

    :event_y ->
      query &query_fun/2 do
        :yes -> [:state_a, :sub_state_y]
        :no -> [:state_b, :substate] \\ &action_k/2
      end
  end

  state [some_state, :substate | rest] do
    :event_x -> [some_state, :substate]
  end
end
