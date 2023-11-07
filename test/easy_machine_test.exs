defmodule EasyMachineTest do
  use ExUnit.Case
  doctest EasyMachine

  test "state machine" do
    defmodule EasyMachineTest.M do
      use EasyMachine

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

    sm = EasyMachineTest.M.state_machine()
    assert {sm, :some_command} = EasyMachine.event(sm, :init_event)
    assert {sm, :some_other_command} = EasyMachine.event(sm, :event_y)
    assert [:state_b] == EasyMachine.current_state(sm)
  end

  test "state machine with complex states" do
    defmodule EasyMachineTest.M2 do
      use EasyMachine

      @init_state :init
      def init_data, do: nil

      def action_j(data, _event), do: {data, :some_command}
      def action_k(data, _event), do: {data, :some_other_command}
      def query_fun(_data, _event), do: :no

      state :init do
        :init_event -> [:state_a, :sub_state_x] \\ &action_j/2
      end

      state [:state_a, sub_state] do
        :event_x ->
          [:state_a, sub_state] \\ &action_k/2

        :event_y ->
          query &query_fun/2 do
            :yes -> [:state_a, :sub_state_y]
            :no -> :state_b \\ &action_k/2
          end
      end

      state :state_b do
        :event_x -> [:state_a, :sub_state_y]
      end
    end

    sm = EasyMachineTest.M2.state_machine()
    assert {sm, :some_command} = EasyMachine.event(sm, :init_event)
    assert [:state_a, :sub_state_x] = EasyMachine.current_state(sm)

    assert {sm, :some_other_command} = EasyMachine.event(sm, :event_x)
    assert [:state_a, :sub_state_x] == EasyMachine.current_state(sm)

    assert {sm, :some_other_command} = EasyMachine.event(sm, :event_y)
    assert [:state_b] == EasyMachine.current_state(sm)

    assert {sm, nil} = EasyMachine.event(sm, :event_x)
    assert [:state_a, :sub_state_y] == EasyMachine.current_state(sm)
  end

  test "state machine with complex guarded states" do
    defmodule EasyMachineTest.M3 do
      use EasyMachine

      @init_state :init
      def init_data, do: nil

      def action_j(data, _event), do: {data, :some_command}
      def action_k(data, _event), do: {data, :some_other_command}
      def query_fun(_data, _event), do: :no

      state :init do
        :init_event -> [:state_a, :sub_state_x] \\ &action_j/2
      end

      state [:state_a, sub_state] do
        :event_x ->
          [:state_a, sub_state] \\ &action_k/2

        :event_y ->
          query &query_fun/2 do
            :yes -> [:state_a, :sub_state_y]
            :no -> [:state_b, :substate] \\ &action_k/2
          end
      end

      state [:state_b, substate] when substate != :substate do
        :event_x -> [:state_b, substate]
      end

      state [:state_b, substate] when substate in [:substate] do
        :event_x -> [:state_a, :sub_state_y]
      end
    end

    sm = EasyMachineTest.M3.state_machine()
    assert {sm, :some_command} = EasyMachine.event(sm, :init_event)
    assert [:state_a, :sub_state_x] = EasyMachine.current_state(sm)

    assert {sm, :some_other_command} = EasyMachine.event(sm, :event_x)
    assert [:state_a, :sub_state_x] == EasyMachine.current_state(sm)

    assert {sm, :some_other_command} = EasyMachine.event(sm, :event_y)
    assert [:state_b, :substate] == EasyMachine.current_state(sm)

    assert {sm, nil} = EasyMachine.event(sm, :event_x)
    assert [:state_a, :sub_state_y] == EasyMachine.current_state(sm)
  end
end
