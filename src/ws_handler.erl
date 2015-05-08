-module(ws_handler).
-behaviour(cowboy_websocket_handler).

-include("napdu.hrl").

-export([init/3]).
-export([websocket_init/3]).
-export([websocket_handle/3]).
-export([websocket_info/3]).
-export([websocket_terminate/3]).


init({tcp, http}, _Req, _Opts) ->
	{upgrade, protocol, cowboy_websocket}.

websocket_init(_TransportName, Req, _Opts) ->
	%erlang:start_timer(1000, self(), <<"Hello!">>),
	{ok, Pid} = mqtt_session:start_link([{transport, self()}]),
	State = napdu:init([
        {max_clientid_len, 1024},
        {max_packet_size, 16#ffff}
    ]),
	{ok, Req, [{session, Pid}, State]}.


websocket_handle({text, Msg}, Req, State) ->
	{reply, {text, << "That's what she said! ", Msg/binary >>}, Req, State};

websocket_handle({binary, Msg}, Req, State = [{session, Pid}, ApduInfo]) ->

	{ok, NApdu, Rest} = napdu:parse(Msg, ApduInfo),
	io:format("Message is ~p Rest : ~p ~n ", [Msg, Rest]),

	gen_fsm:send_event(Pid, NApdu),
	{ok, Req, State};

websocket_handle(Data, Req, State) ->
io:format("Received ~p ~n", [Data]),
	{ok, Req, State}.


websocket_info({timeout, _Ref, Msg}, Req, State) ->
	erlang:start_timer(1000, self(), <<"How' you doin'?">>),
	{reply, {text, Msg}, Req, State};

websocket_info({reply, <<"error">>}, Req, State = [{session, Pid}, _]) ->
io:format("Info Rep : Error ~n"),
	gen_fsm:send_all_state_event(Pid, stop),
	{reply, {close, <<>>}, Req, State};

websocket_info({reply, Reply}, Req, State) ->
io:format("Info Rep : ~p ~n", [Reply]),
	{reply, {binary, Reply}, Req, State};

websocket_info(Info, Req, State) ->
io:format("Default Info: ~p ~n", [Info]),
	{ok, Req, State}.

websocket_terminate(_Reason, _Req, _State) ->
	ok.
