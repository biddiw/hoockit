-module(tcp_handler).

-include("napdu.hrl").

-export([tcp_init/2]).
-export([tcp_handle/2]).
-export([tcp_info/2]).
-export([tcp_terminate/2]).


tcp_init(_TransportName, _Opts) ->
	%erlang:start_timer(1000, self(), <<"Hello!">>),
	{ok, Pid} = mqtt_session:start_link([{transport, self()}]),
	State = napdu:init([
        {max_clientid_len, 1024},
        {max_packet_size, 16#ffff}
    ]),
	{ok, [{session, Pid}, State]}.


tcp_handle({text, Msg}, State) ->
	{reply, {text, << "That's what she said! ", Msg/binary >>}, State};

tcp_handle({binary, Msg}, State = [{session, Pid}, ApduInfo]) ->

	{ok, NApdu, Rest} = napdu:parse(Msg, ApduInfo),
	io:format("Message is ~p Rest : ~p ~n ", [Msg, Rest]),

	gen_fsm:send_event(Pid, NApdu),
	{ok, State};

tcp_handle(Data, State) ->
io:format("Received ~p ~n", [Data]),
	{ok, State}.


tcp_info({timeout, _Ref, Msg}, State) ->
	erlang:start_timer(1000, self(), <<"How' you doin'?">>),
	{reply, {text, Msg}, State};

tcp_info({reply, <<"error">>}, State = [{session, Pid}, _]) ->
io:format("Info Rep : Error ~n"),
	gen_fsm:send_all_state_event(Pid, stop),
	{reply, {close, <<>>}, State};

tcp_info({reply, Reply}, State) ->
io:format("Info Rep : ~p ~n", [Reply]),
	{reply, {binary, Reply}, State};

tcp_info(Info, State) ->
io:format("Default Info: ~p ~n", [Info]),
	{ok, State}.

tcp_terminate(_Reason, _State) ->
	ok.
