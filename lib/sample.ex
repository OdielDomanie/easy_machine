defmodule SampleSM do
  @moduledoc """
  ![SampleSM](sample.svg)
  """
  use EasyMachine, svg_file: true

  @init_state :init
  def init_data, do: nil

  def action_j(data, _event), do: {data, :some_command}
  def action_k(data, _event), do: {data, :some_other_command}
  def query_fun(_data, _event), do: :no

  state :init do
    :init_event -> :state_a \\ &action_j/2
  end

  state :state_a do
    :event_x ->
      :state_a \\ &action_k/2

    :event_y ->
      query &query_fun/2 do
        :yes -> :state_a
        :no -> :state_b \\ &action_k/2
      end
  end

  state :state_b do
    :event_x -> :state_a
  end
end

sm = SampleSM.state_machine()
{sm, :some_command} = EasyMachine.event(sm, :init_event)
{sm, :some_other_command} = EasyMachine.event(sm, :event_y)
[:state_b] = EasyMachine.current_state(sm)
