defmodule StateMachine.DiagramD2 do
  @spec to_d2(StateMachine.machine_spec()) :: String.t()
  def to_d2(sm_spec) do
    {init_state, transitions} = sm_spec

    d2 = "#{ast_to_d2(init_state)}\n"

    for transition <- transitions, into: d2 do
      case transition do
        {action, {curr_state, next_state, event_match}} ->
          "#{ast_to_d2(curr_state)}" <>
            " -> " <>
            "#{ast_to_d2(next_state)}: " <>
            "#{ast_to_d2(event_match)}" <>
            case action do
              nil -> ""
              action -> "\\n#{ast_to_d2(action)}"
            end <>
            "\n"

        {:conditional, curr_state, event_match, query, match_act_nextstate} ->
          query_node = "query_" <> (System.unique_integer() |> to_string)

          curr_to_query =
            "#{query_node}: " <>
              "#{ast_to_d2(query)}\n" <>
              "#{query_node}.shape: diamond\n" <>
              "#{query_node}.width: 1\n" <>
              "#{query_node}.style.bold: false\n" <>
              "#{ast_to_d2(curr_state)}" <>
              " -> " <>
              "#{query_node}:" <>
              "#{ast_to_d2(event_match)}\n"

          for {match, act, next_state} <- match_act_nextstate, into: curr_to_query do
            "#{query_node} -> " <>
              "#{ast_to_d2(next_state)}: " <>
              "#{ast_to_d2(match)}" <>
              case act do
                nil -> ""
                action -> "\\n#{ast_to_d2(action)}"
              end <>
              "\n"
          end
      end <>
        "\n"
    end
  end

  defp ast_to_d2(ast) do
    ast
    |> Macro.to_string()
    |> String.replace(~r|[^a-zA-Z_/&]|, fn char -> "\\" <> char end)
  end
end
