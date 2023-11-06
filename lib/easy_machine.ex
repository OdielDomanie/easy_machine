defmodule EasyMachine do
  @moduledoc """
  Documentation for `EasyMachine`.

  ## Example
    ```
    iex> defmodule M do
    ...>   use EasyMachine
    ...>
    ...>   @init_state :init
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
    iex> {sm, :some_command} = EasyMachine.event(sm, :init_event)
    iex> {sm, :some_other_command} = EasyMachine.event(sm, :event_y)
    iex> EasyMachine.current_state(sm)
    :state_b
    ```

  """

  @type state_machine :: {compiled_transitions, current_state :: state, data :: any}

  @type compiled_transitions ::
          (state, data :: term, event :: any -> {state, data :: term, command :: term})

  @type machine_spec :: {init_state :: state, [transition]}

  @type state :: atom | [atom]

  @type state_transition ::
          {curr_state :: state_match, next_state :: state_pattern, event_match}

  @type transition ::
          {action | nil, state_transition}
          | {:conditional, curr_state :: state_match, event_match, query,
             [{match :: Macro.t(), action | nil, next_state :: state_pattern}, ...]}

  # @type state_pattern :: atom | {:var, atom} | [atom | {:var, atom}]
  @type state_match :: {[atom | Macro.t()], guard :: Macro.t()}
  @type state_pattern :: [atom | Macro.t()]
  @type event_match :: Macro.t()

  @type action :: (data :: any, event :: any -> {data :: any, command :: term})
  @type query :: (data :: any, event :: any -> term)

  def current_state(sm) do
    {_compiled_transitions, current_state, _data} = sm
    current_state
  end

  @spec event(state_machine, term) :: {state_machine, command :: term}
  def event(sm, event) do
    {transitions, state, data} = sm

    {state, data, command} = transitions.(state, data, event)

    sm = {transitions, state, data}

    {sm, command}
  end

  defmacro state(state_match, do: cases) do
    state_match = normalize_state_match(state_match)

    transitions =
      for {:->, meta, [[event_match], event_result]} <- cases do
        transition = parse_to_transition(state_match, event_match, event_result)

        line = meta[:line] || __CALLER__.line

        quote do
          @transitions @transitions ++
                         [{unquote(Macro.escape(transition)), unquote(line)}]
        end
      end

    quote do
      (unquote_splicing(transitions))
    end
  end

  defp normalize_state_match(state_match) do
    case state_match do
      sp when not is_list(sp) -> {[sp], quote(do: true)}
      {:when, _, [sp, guard]} when not is_list(sp) -> {[sp], guard}
      sp when is_list(sp) -> {sp, quote(do: true)}
      {:when, _, [sp, guard]} when is_list(sp) -> {sp, guard}
    end
  end

  defp parse_to_transition(sm, em, {:\\, _, [next_state, action]}) do
    next_state =
      cond do
        is_list(next_state) -> next_state
        not is_list(next_state) -> [next_state]
      end

    state_transition = {sm, next_state, em}
    {action, state_transition}
  end

  defp parse_to_transition(state_match, event_match, {:query, _, [query_fun, [do: arrow_stmnts]]}) do
    query_match_action_nextstate =
      for arrow_stmnt <- arrow_stmnts do
        {:->, _, [[query_match], right]} = arrow_stmnt

        {next_state, action} =
          case right do
            {:\\, _, [next_state, action]} -> {next_state, action}
            next_state -> {next_state, nil}
          end

        {query_match, action, next_state}
      end

    {
      :conditional,
      state_match,
      event_match,
      query_fun,
      query_match_action_nextstate
    }
  end

  defp parse_to_transition(sm, em, next_state) do
    state_transition = {sm, next_state, em}
    {nil, state_transition}
  end

  @doc false
  defmacro __using__(opts) do
    quote do
      @svg_file unquote(Keyword.get(opts, :svg_file, false))
      import EasyMachine
      @transitions []
      @before_compile EasyMachine
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      if not is_list(@init_state) do
        @init_state [@init_state]
      end

      EasyMachine.compile_transitions()

      def state_machine do
        {&transition/3, @init_state, init_data()}
      end

      def machine_spec do
        {@init_state, @transitions}
      end

      if @svg_file and Mix.env() == :dev do
        File.write!(
          __ENV__.file
          |> Path.dirname()
          |> Path.join(Path.basename(__ENV__.file, ".ex") <> ".svg"),
          {@init_state, @transitions |> Enum.unzip() |> elem(0)}
          |> EasyMachine.DiagramD2.to_d2()
          |> EasyMachine.DiagramD2.svg()
        )
      end

      # IO.inspect(Module.get_definition(__MODULE__, {:transition, 3}))
    end
  end

  @doc false
  defmacro compile_transitions do
    transitions = Module.get_attribute(__CALLER__.module, :transitions)
    EasyMachine.compile(transitions)
  end

  @spec compile([{transition, pos_integer}]) :: Macro.output()
  @doc false
  def compile(transitions) do
    transition_fun_defs =
      for {transition, line} <- transitions do
        transition_fun_def(transition, line)
      end

    quote do
      (unquote_splicing(transition_fun_defs))
    end
  end

  defp transition_fun_def(
         {action, {{curr_state, curr_state_guard}, next_state, event_match}},
         line
       ) do
    {event_pattern, event_guard} = split_match_guard(event_match)

    action =
      case action do
        nil -> quote do: fn data, _event -> {data, nil} end
        action -> action
      end

    quote line: line do
      def transition(unquote(curr_state), data, unquote(event_pattern) = event)
          when unquote(curr_state_guard) and unquote(event_guard) do
        {data, command} = unquote(action).(data, event)
        {unquote(next_state), data, command}
      end
    end
  end

  defp transition_fun_def(
         {:conditional, {curr_state, curr_state_guard}, event_match, query,
          query_match_action_nextstate},
         line
       ) do
    {event_pattern, event_guard} = split_match_guard(event_match)

    macroed_query_match_action_nextstate =
      for {match, action, next_state} <- query_match_action_nextstate do
        action =
          case action do
            nil -> quote do: fn data, _event -> {data, nil} end
            action -> action
          end

        quote line: line do
          unquote(match) ->
            {data, command} =
              unquote(action).(
                data,
                event
              )

            {unquote(next_state), data, command}
        end
        |> List.first()
      end

    quote line: line do
      def transition(unquote(curr_state), data, unquote(event_pattern) = event)
          when unquote(curr_state_guard) and unquote(event_guard) do
        case unquote(query).(data, event),
          do: unquote(macroed_query_match_action_nextstate)
      end
    end
  end

  defp split_match_guard({:when, _, [pattern, guard]}), do: {pattern, guard}
  defp split_match_guard(pattern), do: {pattern, true}
end
