%% Copyright (c) 2011-2014, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

%% Cowboy supports versions 7 through 17 of the Websocket drafts.
%% It also supports RFC6455, the proposed standard for Websocket.
-module(transport_tcp).

-export([start_link/4, init/4]).
-export([handler_loop/3]).

-type close_code() :: 1000..4999.
-export_type([close_code/0]).

-type frame() :: close | ping | pong
	| {text | binary | close | ping | pong, iodata()}
	| {close, close_code(), iodata()}.
-export_type([frame/0]).

-type opcode() :: 0 | 1 | 2 | 8 | 9 | 10.
-type frag_state() :: undefined
	| {nofin, opcode(), binary()} | {fin, opcode(), binary()}.
-type terminate_reason() :: {normal | error | remote, atom()}
	| {remote, close_code(), binary()}.

-record(state, {
	env :: any(),
	socket = undefined :: inet:socket(),
	transport = undefined :: module(),
	handler :: module(),
	key = undefined :: undefined | binary(),
	timeout = infinity :: timeout(),
	timeout_ref = undefined :: undefined | reference(),
	messages = undefined :: undefined | {atom(), atom(), atom()},
	hibernate = false :: boolean(),
	frag_state = undefined :: frag_state(),
	utf8_state = <<>> :: binary()
}).


start_link(Ref, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
	{ok, Pid}.

init(Ref, Socket, Transport, _Opts = [{handler, Handler}, {handler_opts, HandlerOpts}]) ->
	ok = ranch:accept_ack(Ref),
	State = #state{env=[], messages=Transport:messages(),
	socket=Socket, transport=Transport, handler=Handler},
	handler_init(State, HandlerOpts).

%%%
%%% handler_init
%%%
-spec handler_init(#state{}, any()) ->
	{ok, any()} | {suspend, module(), atom(), [any()]}.

handler_init(State=#state{env=Env, transport=Transport, handler=Handler}, HandlerOpts) ->
	try Handler:tcp_init(Transport:name(), HandlerOpts) of
		{ok, HandlerState} ->
			handler_before_loop(State, HandlerState, <<>>);

		{ok, HandlerState, hibernate} ->
			handler_before_loop(State#state{hibernate=true}, HandlerState, <<>>);

		{ok, HandlerState, Timeout} ->
			handler_before_loop(State#state{timeout=Timeout}, HandlerState, <<>>);
			
		{ok, HandlerState, Timeout, hibernate} ->
			handler_before_loop(State#state{timeout=Timeout, hibernate=true},
								HandlerState, <<>>);
								
		{shutdown} ->
			{ok, [{result, closed}|Env]}

	catch Class:Reason ->
		Stacktrace = erlang:get_stacktrace(),
		erlang:Class([
			{reason, Reason},
			{mfa, {Handler, tcp_init, 3}},
			{stacktrace, Stacktrace},
			{opts, HandlerOpts}
		])
	end.

%%%
%%% handler_before_loop
%%%
-spec handler_before_loop(#state{}, any(), binary()) ->
	{ok, any()}
	| {suspend, module(), atom(), [any()]}.

handler_before_loop(State=#state{socket=Socket, transport=Transport, hibernate=true},
					HandlerState, SoFar) ->
	Transport:setopts(Socket, [{active, once}]),
	{suspend, ?MODULE, handler_loop, [State#state{hibernate=false},
	 HandlerState, SoFar]};
		
handler_before_loop(State=#state{socket=Socket, transport=Transport}, HandlerState, SoFar) ->
	Transport:setopts(Socket, [{active, once}]),
	handler_loop(State, HandlerState, SoFar).


%%%
%%% handler_loop
%%%
-spec handler_loop(#state{}, any(), binary()) ->
	{ok, any()}
	| {suspend, module(), atom(), [any()]}.

handler_loop(State=#state{socket=Socket, messages={OK, Closed, Error}, timeout_ref=TRef},
			 HandlerState, SoFar) ->
	receive
		{OK, Socket, Data} ->
			State2 = handler_loop_timeout(State),
			tcp_data(State2, HandlerState, << SoFar/binary, Data/binary >>);
				
		{Closed, Socket} ->
			handler_terminate(State, HandlerState, {error, closed});

		{Error, Socket, Reason} ->
			handler_terminate(State, HandlerState, {error, Reason});

		{timeout, TRef, ?MODULE} ->
			tcp_close(State, HandlerState, {normal, timeout});

		{timeout, OlderTRef, ?MODULE} when is_reference(OlderTRef) ->
			handler_loop(State, HandlerState, SoFar);

		Message ->
			handler_call(State, HandlerState, SoFar, tcp_info, Message,
						 fun handler_before_loop/3)
	end.

%%%
%%% handler_loop_timeout
%%%
-spec handler_loop_timeout(#state{}) -> #state{}.

handler_loop_timeout(State=#state{timeout=infinity}) ->
	State#state{timeout_ref=undefined};
	
handler_loop_timeout(State=#state{timeout=Timeout, timeout_ref=PrevRef}) ->
	_ = case PrevRef of undefined -> ignore; PrevRef ->
		erlang:cancel_timer(PrevRef) end,
	TRef = erlang:start_timer(Timeout, self(), ?MODULE),
	State#state{timeout_ref=TRef}.

%%%
%%% tcp_data
%%%
%%% All frames passing through this function are considered valid,
%%% with the only exception of text and close frames with a payload
%% which may still contain errors.
-spec tcp_data(#state{}, any(), binary()) ->
	{ok, any()} %% second param = env
	| {suspend, module(), atom(), [any()]}.

%% Need more data.
tcp_data(State, HandlerState, Data) ->
	handler_before_loop(State, HandlerState, Data).


%%%
%%% handle_call
%%%
-spec handler_call(#state{}, any(), binary(), atom(), any(), fun())
	-> {ok, any()} %%% second param Env
	| {suspend, module(), atom(), [any()]}.

handler_call(State=#state{handler=Handler}, HandlerState, RemainingData,
			 Callback, Message, NextState) ->
	try Handler:Callback(Message, HandlerState) of
		{ok, HandlerState2} ->
			NextState(State, HandlerState2, RemainingData);

		{ok, HandlerState2, hibernate} ->
			NextState(State#state{hibernate=true}, HandlerState2, RemainingData);

		{reply, Payload, HandlerState2} when is_list(Payload) ->
			case tcp_send_many(Payload, State) of
				{ok, State2} ->
					NextState(State2, HandlerState2, RemainingData);

				{shutdown, State2} ->
					handler_terminate(State2, HandlerState2, {normal, shutdown});

				{{error, _} = Error, State2} ->
					handler_terminate(State2, HandlerState2, Error)
			end;

		{reply, Payload, HandlerState2, hibernate}
				when is_list(Payload) ->
			case tcp_send_many(Payload, State) of
				{ok, State2} ->
					NextState(State2#state{hibernate=true}, HandlerState2,
							  RemainingData);
							  
				{shutdown, State2} ->
					handler_terminate(State2, HandlerState2, {normal, shutdown});
						
				{{error, _} = Error, State2} ->
					handler_terminate(State2, HandlerState2, Error)
			end;
			
		{reply, Payload, HandlerState2} ->
			case tcp_send(Payload, State) of
				{ok, State2} ->
					NextState(State2, HandlerState2, RemainingData);
					
				{shutdown, State2} ->
					handler_terminate(State2, HandlerState2,{normal, shutdown});
						
				{{error, _} = Error, State2} ->
					handler_terminate(State2, HandlerState2, Error)
			end;

		{reply, Payload, HandlerState2, hibernate} ->
			case tcp_send(Payload, State) of
				{ok, State2} ->
					NextState(State2#state{hibernate=true}, HandlerState2, RemainingData);

				{shutdown, State2} ->
					handler_terminate(State2, HandlerState2, {normal, shutdown});

				{{error, _} = Error, State2} ->
					handler_terminate(State2, HandlerState2, Error)
			end;
			
		{shutdown, HandlerState2} ->
			tcp_close(State, HandlerState2, {normal, shutdown})

	catch Class:Reason ->
		_ = tcp_close(State, HandlerState, {error, handler}),
		erlang:Class([
			{reason, Reason},
			{mfa, {Handler, Callback, 3}},
			{stacktrace, erlang:get_stacktrace()},
			{msg, Message},
			{state, HandlerState}
		])
	end.

%%%
%%% tcp_send
%%%
-spec tcp_send(frame(), #state{}) ->
	{ok, #state{}} | {shutdown, #state{}} | {{error, atom()}, #state{}}.

tcp_send(Type, State=#state{}) when Type =:= close ->
	{shutdown, State};
	% Error -> {Error, State}
	
tcp_send({_Type = close, _StatusCode, _Payload}, State=#state{}) ->
	{shutdown, State}.

%%%
%%% tcp_send_many
%%%
-spec tcp_send_many([frame()], #state{})
	-> {ok, #state{}} | {shutdown, #state{}} | {{error, atom()}, #state{}}.

tcp_send_many([], State) ->
	{ok, State};

tcp_send_many([Frame|Tail], State) ->
	case tcp_send(Frame, State) of
		{ok, State2} -> tcp_send_many(Tail, State2);
		{shutdown, State2} -> {shutdown, State2};
		{Error, State2} -> {Error, State2}
	end.

%%%
%%% tcp_close
%%%
-spec tcp_close(#state{}, any(), terminate_reason()) -> {ok, any()}. % last param is Env

tcp_close(State=#state{}, HandlerState, Reason) ->
	handler_terminate(State, HandlerState, Reason).

%%%
%%% handler_terminate
%%%
-spec handler_terminate(#state{}, any(), terminate_reason()) -> {ok, any()}. % last param is Env. 

handler_terminate(#state{env=Env, handler=Handler}, HandlerState, TerminateReason) ->
	try
		Handler:tcp_terminate(TerminateReason, HandlerState)
		
	catch Class:Reason ->
		erlang:Class([
			{reason, Reason},
			{mfa, {Handler, tcp_terminate, 3}},
			{stacktrace, erlang:get_stacktrace()},
			{state, HandlerState},
			{terminate_reason, TerminateReason}
		])
	end,
	{ok, [{result, closed}|Env]}.

