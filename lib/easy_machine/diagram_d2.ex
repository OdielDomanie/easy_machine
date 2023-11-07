defmodule EasyMachine.DiagramD2 do
  @spec to_d2(EasyMachine.machine_spec()) :: String.t()
  def to_d2(sm_spec) do
    {init_state, transitions} = sm_spec

    all_possible_states = [init_state | enumerate_states(transitions)] |> Enum.uniq()

    d2 = "#{state_to_d2(init_state)}\n"

    for transition <- transitions, into: d2 do
      case transition do
        {action, {{curr_pattern, cur_guard}, next_state, event_match}} ->
          for possible_curr_state <- all_possible_states, into: "" do
            quote do
              case unquote(possible_curr_state) do
                unquote(curr_pattern) = actual_curr_state when unquote(cur_guard) ->
                  _ = unquote(curr_pattern)
                  actual_next_state = unquote(next_state)
                  {:ok, actual_curr_state, actual_next_state}

                _ ->
                  :nomatch
              end
            end
            |> Code.eval_quoted()
            |> elem(0)
            |> case do
              {:ok, actual_curr_state, actual_next_state} ->
                "#{state_to_d2(actual_curr_state)} -> #{state_to_d2(actual_next_state)}: #{ast_to_d2(event_match)}" <>
                  case action do
                    nil -> ""
                    action -> "\\n#{ast_to_d2(action)}"
                  end <>
                  "\n\n"

              :nomatch ->
                ""
            end
          end

        {:conditional, {curr_pattern, cur_guard}, event_match, query, match_act_nextstate} ->
          for possible_curr_state <- all_possible_states, into: "" do
            query_node = "query_" <> ast_to_d2(possible_curr_state)

            curr_to_query =
              "#{query_node}: #{ast_to_d2(query)}\n" <>
                "#{query_node}.shape: diamond\n" <>
                "#{query_node}.width: 1\n" <>
                "#{query_node}.style.bold: false\n" <>
                "#{state_to_d2(possible_curr_state)} -> #{query_node}: #{ast_to_d2(event_match)}\n\n"

            query_to_nexts =
              for {match, action, next_state} <- match_act_nextstate, into: "" do
                quote do
                  case unquote(possible_curr_state) do
                    unquote(curr_pattern) = actual_curr_state when unquote(cur_guard) ->
                      _ = unquote(curr_pattern)
                      actual_next_state = unquote(next_state)
                      {:ok, actual_curr_state, actual_next_state}

                    _ ->
                      :nomatch
                  end
                end
                |> Code.eval_quoted()
                |> elem(0)
                |> case do
                  {:ok, _actual_curr_state, actual_next_state} ->
                    # query_to_next
                    "#{query_node} -> " <>
                      "#{state_to_d2(actual_next_state)}: " <>
                      "#{ast_to_d2(match)}" <>
                      case action do
                        nil -> ""
                        action -> "\\n#{ast_to_d2(action)}"
                      end <>
                      "\n"

                  :nomatch ->
                    ""
                end
              end

            if query_to_nexts != "" do
              curr_to_query <> query_to_nexts
            else
              ""
            end
          end
      end <>
        "\n"
    end
  end

  defp state_to_d2({state, _}) do
    state
    |> Enum.map(&ast_to_d2/1)
    |> Enum.join(".")
  end

  defp state_to_d2(state) do
    state
    |> Enum.map(&ast_to_d2/1)
    |> Enum.join(".")
  end

  defp ast_to_d2(ast) do
    ast
    |> Macro.to_string()
    |> String.replace(~r|[^a-zA-Z_/&]|, fn char -> "\\" <> char end)
  end

  if Mix.env() == :dev do
    def svg(d2) do
      {:ok, %Rambo{status: 0, out: svg, err: _err}} =
        Rambo.run("d2", ["--theme", "200", "--dark-theme", "200", "-", "-"], in: d2, log: false)

      svg
    end
  end

  @type concrete_state :: nonempty_maybe_improper_list(atom, [variable :: Macro.t()])
  @type var_state :: {match_current :: Macro.t(), nonempty_list(pattern_next :: Macro.t())}

  def enumerate_states(transitions) do
    var_states = var_states(transitions)

    concrete_states = conc_states(var_states)

    matching_var_states =
      for conc_state <- concrete_states,
          {{curr_state_pattern, curr_state_guard}, pattern_next} <- var_states do
        quote do
          case unquote(conc_state) do
            unquote(curr_state_pattern) when unquote(curr_state_guard) ->
              _ = unquote(conc_state)
              _ = unquote(curr_state_pattern)
              {:ok, unquote(pattern_next)}

            _no_match ->
              :no_match
          end
        end
        |> Code.eval_quoted()
        |> elem(0)
      end

    matching_var_states
    |> Enum.filter(fn v -> v != :no_match end)
    |> Enum.map(fn {:ok, v} -> v end)

    # |> IO.inspect()
  end

  def var_states(transitions) do
    for transition <- transitions do
      case transition do
        {_action, {{curr_state_pattern, guard}, next_state_pattern, _event_match}} ->
          [{{curr_state_pattern, guard}, next_state_pattern}]

        {:conditional, {curr_state_patter, guard}, _event_match, _query,
         query_match_act_nextstate} ->
          for {_query_match, _action, next_state_pattern} <- query_match_act_nextstate do
            {{curr_state_patter, guard}, next_state_pattern}
          end
      end
    end
    |> Enum.concat()
  end

  def conc_states(var_states) do
    for {{curr_state_pattern, _guard}, next_state_pattern} <- var_states do
      conc_curr_state = Enum.take_while(curr_state_pattern, &is_atom/1)
      conc_next_state = Enum.take_while(next_state_pattern, &is_atom/1)
      [conc_curr_state, conc_next_state]
    end
    |> Enum.concat()
    |> Enum.reject(&(&1 == []))
  end
end
