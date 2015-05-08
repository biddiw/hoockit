-module(mqtt_session).
-behavior(gen_fsm).

-include("napdu.hrl").

-export([start_link/1]).
-export([init/1, terminate/3, code_change/4]).
-export([idle/2, connected/2, publishing/2, publishing_once/2, cleaning/2]).
-export([handle_event/3, handle_sync_event/4, handle_info/3]).
         


%%% PUBLIC API
start_link(Args) ->
    gen_fsm:start_link(?MODULE, Args, []).


init(Data) ->
	{ok, idle, Data}.

%% FSM Handlers

handle_info({zmq, _Socket, _Msg, _Flag}, State, Data) ->
	{next_state, State, Data};


handle_info({napdu, NApdu}, State, Data) ->
	io:format("Handle info current state is ~p ~n", [State]),
	gen_fsm:send_event(self(), NApdu),
	{next_state, State, Data};

handle_info(Event, State, Data) ->
	io:format("Unknown Handle info current state is ~p ~n - Event ~p ~n", [State, Event]),
	{next_state, State, Data}.


%%
%% State IDLE
%%

idle(NApdu = ?CONNECT_PACKET(MQTTData), Data) ->
	Transport = proplists:get_value(transport, Data),
	
	%#mqtt_packet_connect{proto_ver  = ProtoVer,
     %                    username   = Login,
      %                   password   = Passwd,
       %                  clean_sess = CleanSess,
        %                 keep_alive = KeepAlive,
         %                client_id  = ClientId} = MQTTData,

	io:format("Idle: Received Binary ~p ~n  MQTTData ~p ~n", [NApdu, MQTTData]),
	io:format("Transport ~p ~n", [Transport]),
	Reply = napdu:serialise(?CONNACK_PACKET(?CONNACK_ACCEPT)),
	Transport ! {reply, Reply},
	{next_state, connected, Data}.

	
%%
%% State CONNECTED
%%

connected(NApdu = ?PACKET(?DISCONNECT), Data) ->
	Transport = proplists:get_value(transport, Data),
	io:format("Connected: - Event is ~p ~n", [NApdu]),
	gen_server:cast(mbutler, {broom, self()}),
	Transport ! {reply, <<>>},
    {next_state, idle, Data};

connected(NApdu = ?PACKET(?PINGREQ), Data) ->
	Transport = proplists:get_value(transport, Data),
	io:format("Connected: - Event is ~p ~n", [NApdu]),
	Reply = napdu:serialise(?PACKET(?PINGRESP)),
	Transport ! {reply, Reply},
	{next_state, connected, Data};

connected(_NApdu = ?SUBSCRIBE_PACKET(PacketId, TopicTable), Data) ->
	Transport = proplists:get_value(transport, Data),
	
	io:format("Connected: - Subscription : PacketId is ~p - Topics : ~p ~n", [PacketId, TopicTable]),
	Reply = case hck_lib:parse(TopicTable) of
		{error, []} ->
						<<"error">>;
						
		{ok, FilterTable} ->
						gen_server:call(mbutler, {subscribe, self(), {PacketId, FilterTable}}),
						gen_server:cast(mbutler, {publish_retain, self(), FilterTable}),
						% Grant best QoS
						napdu:serialise(?SUBACK_PACKET(PacketId, [?QOS_2]));

		_ ->
						<<"error">>
	end,
	Transport ! {reply, Reply},
	{next_state, connected, Data};

connected(_NApdu = ?UNSUBSCRIBE_PACKET(PacketId, TopicSet), Data) ->
	Transport = proplists:get_value(transport, Data),
	
	io:format("Connected: - Unsubscribe PacketId is ~p - Topics : ~p ~n", [PacketId, TopicSet]),
	gen_server:call(mbutler, {unsubscribe, self(), {PacketId, TopicSet}}),
	Reply = napdu:serialise(?UNSUBACK_PACKET(PacketId)),
	Transport ! {reply, Reply},
	{next_state, connected, Data};
						
connected(NApdu = ?PUBLISH_APDU(Retain, ?QOS_0, PacketId, Topic, Payload), Data) ->	
	io:format("Connected: - Event is ~p ~n", [NApdu]),
	gen_server:cast(mbutler, {publish, self(), {Retain, PacketId, Topic, Payload}}),
	{next_state, connected, Data};

connected(NApdu = ?PUBLISH_APDU(Retain, ?QOS_1, PacketId, Topic, Payload), Data) ->	
	Transport = proplists:get_value(transport, Data),

	io:format("Connected: - Event is ~p ~n", [NApdu]),
	gen_server:cast(mbutler, {publish, self(), {Retain, PacketId, Topic, Payload}}),
	Reply = napdu:serialise(?PUBACK_PACKET(?PUBACK, PacketId)),
	Transport ! {reply, Reply},
	{next_state, connected, Data};

connected(NApdu = ?PUBLISH_APDU(Retain, ?QOS_2, PacketId, Topic, Payload), Data) ->	
	Transport = proplists:get_value(transport, Data),
	
	io:format("Connected: - Event is ~p ~n", [NApdu]),
	gen_server:cast(mbutler, {publish, self(), {Retain, PacketId, Topic, Payload}}),
	Reply = napdu:serialise(?PUBACK_PACKET(?PUBREC, PacketId)),
	Transport ! {reply, Reply},
	{next_state, publishing, Data};

connected(Event, Data) ->
	io:format("Connected: Event is ~p ~n", [Event]),
	{next_state, connected, Data}.


%%
%% State PUBLISHING
%%

publishing(?PUBACK_PACKET(?PUBREL, PacketId), Data) ->
	Transport = proplists:get_value(transport, Data),

	io:format("State is publishing PUBREL ~n"),
	Reply = napdu:serialise(?PUBACK_PACKET(?PUBCOMP, PacketId)),
	Transport ! {reply, Reply},
	{next_state, connected, Data};

publishing(?PUBACK_PACKET(?PUBACK, _PacketId), Data) ->
	io:format("State is publishing PUBACK ~n"),
	{next_state, connected, Data};

publishing(Event, Data) ->
	io:format("State is publishing other ~p ~n", [Event]),
	{next_state, connected, Data}.
	
publishing_once(?PUBACK_PACKET(?PUBREC, PacketId), Data) ->
	Transport = proplists:get_value(transport, Data),

	io:format("State is publishing_once PUBREC ~n"),
	Reply = napdu:serialise(?PUBACK_PACKET(?PUBREL, PacketId)),
	Transport ! {reply, Reply},
	{next_state, publishing_once, Data};

publishing_once(?PUBACK_PACKET(?PUBCOMP, _PacketId), Data) ->
	io:format("State is publishing_once PUBCOMP ~n"),
	{next_state, connected, Data};

publishing_once(Event, Data) ->
	io:format("State is publishing_once other ~p ~n", [Event]),
	{next_state, connected, Data}.


cleaning(_Event, Data) ->
	io:format("State is cleaning ~n"),
	%gen_server:cast(Master, {done, self()}),
	{next_state, cleaning, Data}.

handle_event({publish, {QoS = ?QOS_1, Topic, PacketId, Payload}}, _State, Data) ->
	Transport = proplists:get_value(transport, Data),

	NApdu = napdu:serialise(?PUBLISH_PACKET(QoS, Topic, PacketId, Payload)),
	Transport ! {reply, NApdu},
	{next_state, publishing, Data};
	
handle_event({publish, {QoS = ?QOS_2, Topic, PacketId, Payload}}, _State, Data) ->
	Transport = proplists:get_value(transport, Data),

	NApdu = napdu:serialise(?PUBLISH_PACKET(QoS, Topic, PacketId, Payload)),
	Transport ! {reply, NApdu},
	{next_state, publishing_once, Data};

handle_event({publish, {QoS, Topic, PacketId, Payload}}, State, Data) ->
	Transport = proplists:get_value(transport, Data),

	NApdu = napdu:serialise(?PUBLISH_PACKET(QoS, Topic, PacketId, Payload)),
	Transport ! {reply, NApdu},
	{next_state, State, Data};

handle_event(stop, _State, Data) ->
	io:format("Handle event stop ~n"),
	gen_server:cast(mbutler, {broom, self()}),
	{stop, normal, Data};

handle_event(_Event, State, Data) ->
	io:format("Handle event state is ~p ~n", [State]),
	{next_state, State, Data}.


handle_sync_event(Event, _From, State, Data) ->
    io:format("Unexpected event: ~p~n", [Event]),
    {next_state, State, Data}.

    
terminate(_Reason, _State, _) ->
	io:format("Terminate ~n").

    
code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.
