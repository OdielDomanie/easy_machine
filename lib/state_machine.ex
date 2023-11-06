defmodule StateMachine do
  @moduledoc """
  Documentation for `StateMachine`.


  ## Example
    ```
    iex> defmodule M do
    ...>   use StateMachine
    ...>
    ...>   def init_state, do: :init
    ...>   def init_data, do: nil
    ...>
    ...>   def action_j(data, _event), do: {data, :some_command}
    ...>   def action_k(data, _event), do: {data, :some_other_command}
    ...>   def query_fun(_data, _event), do: :no
    ...>
    ...>   state :init do
    ...>     :init_event -> :state_a \\\\ &action_j/2
    ...>   end
    ...> 
    ...>   state :state_a do
    ...>     :event_x -> :state_a \\\\ &action_k/2
    ...>     :event_y -> 
    ...>       query &query_fun/2 do
    ...>         :yes -> :state_a
    ...>         :no -> :state_b \\\\ &action_k/2
    ...>       end
    ...>   end
    ...> 
    ...>   state :state_b do
    ...>     :event_x -> :state_a
    ...>   end
    ...>   
    ...> end
    iex> sm = M.state_machine()
    iex> {sm, :some_command} = StateMachine.event(sm, :init_event)
    iex> {sm, :some_other_command} = StateMachine.event(sm, :event_y)
    iex> StateMachine.current_state(sm)
    :state_b
    ```
  """

  @type state_machine :: {compiled_transitions, current_state :: state, data :: any}

  @type compiled_transitions ::
          (state, data :: term, event :: any -> {state, data :: term, command :: term})

  @type machine_spec :: {init_state :: state, [transition]}

  @type state :: atom | [atom]

  @type state_transition ::
          {curr_state :: state_pattern, next_state :: state_pattern, event_match}

  @type transition ::
          {action | nil, state_transition}
          | {:conditional, curr_state :: state_pattern, event_match, query,
             [{match :: Macro.t(), action | nil, next_state :: state_pattern}, ...]}

  # @type state_pattern :: atom | {:var, atom} | [atom | {:var, atom}]
  @type state_pattern :: Macro.t()
  @type event_match :: Macro.t()

  @type action :: (data :: any, event :: any -> {data :: any, command :: term})
  @type query :: (data :: any, event :: any -> term)

  defmacro __using__(_) do
    quote do
      import StateMachine
      @transitions []
      @before_compile StateMachine
    end
  end

  defmacro compile_transitions do
    transitions = Module.get_attribute(__CALLER__.module, :transitions)
    StateMachine.compile(transitions)
  end

  defmacro __before_compile__(_env) do
    quote do
      StateMachine.compile_transitions()

      def state_machine do
        {&transition/3, init_state(), init_data()}
      end

      def machine_spec do
        {init_state(), @transitions}
      end

      # IO.inspect(Module.get_definition(M, {:transition, 3}))
    end
  end

  def current_state(sm) do
    {_compiled_transitions, current_state, _data} = sm
    current_state
  end

  defmacro state(state_pattern, do: cases) do
    transitions =
      for arrow_stmnt <- cases do
        {:->, _, [[event_match], right]} = arrow_stmnt

        transition =
          case right do
            {:\\, _, [next_state, action]} ->
              state_transition = {state_pattern, next_state, event_match}
              {action, state_transition}

            {:query, _, [query_fun, [do: arrow_stmnts]]} ->
              query_match_action_nextstate =
                for arrow_stmnt <- arrow_stmnts do
                  {:->, _, [[event_match], right]} = arrow_stmnt

                  {next_state, action} =
                    case right do
                      {:\\, _, [next_state, action]} -> {next_state, action}
                      next_state -> {next_state, nil}
                    end

                  {event_match, action, next_state}
                end

              {
                :conditional,
                state_pattern,
                event_match,
                query_fun,
                query_match_action_nextstate
              }

            next_state ->
              state_transition = {state_pattern, next_state, event_match}
              {nil, state_transition}
          end

        quote do
          @transitions @transitions ++ [unquote(Macro.escape(transition))]
        end
      end

    quote do
      (unquote_splicing(transitions))
    end
  end

  @spec event(state_machine, term) :: {state_machine, command :: term}
  def event(sm, event) do
    {transitions, state, data} = sm

    {state, data, command} = transitions.(state, data, event)

    sm = {transitions, state, data}

    {sm, command}
  end

  @spec compile([transition]) :: Macro.output()
  def compile(transitions) do
    transition_fun_defs =
      for transition <- transitions do
        case transition do
          {action, {curr_state, next_state, event_match}} ->
            {event_pattern, event_guard} = split_match_guard(event_match)

            action =
              case action do
                nil -> quote do: fn data, _event -> {data, nil} end
                action -> action
              end

            quote do
              def transition(unquote(curr_state), data, unquote(event_pattern) = event)
                  when unquote(event_guard) do
                {data, command} = unquote(action).(data, event)
                {unquote(next_state), data, command}
              end
            end

          {:conditional, curr_state, event_match, query, query_match_action_nextstate} ->
            {event_pattern, event_guard} = split_match_guard(event_match)

            macroed_query_match_action_nextstate =
              for {match, action, next_state} <- query_match_action_nextstate do
                action =
                  case action do
                    nil -> quote do: fn data, _event -> {data, nil} end
                    action -> action
                  end

                quote do
                  unquote(match) ->
                    {data, command} =
                      unquote(action).(
                        # Macro.var(data, __MODULE__),
                        # Macro.var(event, __MODULE__)
                        data,
                        event
                      )

                    # {unquote(next_state), Macro.var(data, __MODULE__),
                    #  Macro.var(command, __MODULE__)}
                    {unquote(next_state), data, command}
                end
                |> List.first()
              end

            quote do
              def transition(unquote(curr_state), data, unquote(event_pattern) = event)
                  when unquote(event_guard) do
                case unquote(query).(data, event),
                  do: unquote(macroed_query_match_action_nextstate)
              end
            end
        end
      end

    quote do
      (unquote_splicing(transition_fun_defs))
    end
  end

  defp split_match_guard({:when, _, [pattern, guard]}), do: {pattern, guard}
  defp split_match_guard(pattern), do: {pattern, true}

  # defp var_to_macro(var) when is_atom(var), do: var

  # defp var_to_macro({:var, var}) do
  #   Macro.var(var, __MODULE__)
  # end

  # defp var_to_macro(vars) when is_list(vars) do
  #   macroed_vars = Enum.map(vars, &var_to_macro/1)

  #   quote do
  #     [
  #       unquote_splicing(macroed_vars)
  #     ]
  #   end
  # end
end
