defmodule Sample2SM do
  use StateMachine, svg_file: true

  @init_state :init
  def init_data, do: nil

  def action_j(data, _event), do: {data, :some_command}
  def action_k(data, _event), do: {data, :some_other_command}
  def query_fun(_data, _event), do: :no

  state :init do
    :init_event -> [:state_a, :orth_x] \\ &action_j/2
  end

  state [:state_a, orth] do
    :event_x ->
      [:state_a, orth] \\ &action_k/2

    :event_y ->
      query &query_fun/2 do
        :yes -> [:state_a, orth]
        :no -> :state_b \\ &action_k/2
      end
  end

  state :state_b do
    :event_x -> [:state_a, :orth_y]
  end
end

# sm = Sample2SM.state_machine()
# {sm, :some_command} = StateMachine.event(sm, :init_event)
# {sm, :some_other_command} = StateMachine.event(sm, :event_y)
# :state_b = StateMachine.current_state(sm)
