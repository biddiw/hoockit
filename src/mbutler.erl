-module(mbutler).
-behavior(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%% PUBLIC API
start_link() ->
    gen_server:start_link({local, mbutler}, ?MODULE, [], []).


init(State) ->
	{ok, [{submap, maps:new()}, {retmap, maps:new()} | State]}.


%% Handlers

handle_call(state, _From, State) ->
	{reply, proplists:get_value(submap, State), State};

handle_call({subscribe, Client, {_PacketId, TopicTable}}, From, State) ->
	SubMap = proplists:get_value(submap, State),
	
	NewSubMap = lists:foldl(fun({Topic, QoS}, Map) -> update_sub(Topic, {Client, QoS}, Map) end,
							SubMap , TopicTable),	
	io:format("Mbutler: ~p / ~p subscribes - ~p ~n", [Client, From, TopicTable]),
	io:format("Map ~p ~n", [NewSubMap]),
	{reply, ok, [{submap, NewSubMap} | proplists:delete(submap,State)]};

handle_call({unsubscribe, Client, {_PacketId, FilterList}}, From, State) ->
	SubMap = proplists:get_value(submap, State),
	
	NewSubMap = lists:foldl(fun(Topic, Map) -> remove_sub(Topic, Client, Map) end, SubMap , FilterList),	
	io:format("Mbutler: ~p / ~p unsubscribe - ~p ~n", [Client, From, FilterList]),
	io:format("Map ~p ~n", [NewSubMap]),
	{reply, ok, [{submap, NewSubMap} | proplists:delete(submap,State)]};

handle_call(_Msg, _From, State) ->
	{reply, ok, State}.

	
handle_cast({Operation = publish, Source, MApdu = {Retain, PacketId, Topic, Payload}}, State) ->
	RetMap = proplists:get_value(retmap, State),
	
	io:format("Mbutler: ~p publishes - ~p ~n", [Source, Topic]),
	F = fun(Filter, SubscList, Hits) ->
			case hck_lib:match(Topic, Filter) of
				false ->
					io:format("sub No match or empty"),
					Hits; % nothing to do
					
				true when is_list(SubscList) ->
					% forward message to client session for delivery
					lists:foldl(fun({Dest, QoS}, Count) ->
									NewPacketId = if (QoS =:= 0) -> undefined;
													 true ->
														if PacketId =:= undefined ->
																10;
															true ->
																PacketId
														end
												  end,
									gen_fsm:send_all_state_event(Dest, {Operation, {QoS, Topic, NewPacketId, Payload}}), Count+1 end,
								0, SubscList),
					Hits+1;
								
				Value ->
						io:format("publish error ~p ~n", [Value]),
						Hits % map error
			end
	end,
	
	Matchs = maps:fold(F, 0, proplists:get_value(submap, State)),
	NewRetMap = if (Retain == false) ->
						RetMap;
					
					true ->
						update_retain(MApdu, RetMap)
			    end,
	io:format("Matchs count ~p ~n", [Matchs]),
	{noreply, [{retmap, NewRetMap} | proplists:delete(retmap,State)]};

handle_cast({publish_retain, Dest, FilterTable}, State) when is_list(FilterTable) ->

	[Matchs] = [ begin
					F = fun(Topic, {PacketId, Payload}, Hits) ->
							case hck_lib:match(Topic, Filter) of
								false ->
									io:format("retain no match or empty"),
									Hits; % nothing to do
									
								true ->
									io:format("Mbutler: publishes retain ~p with ~p ~n", [Topic, Payload]),
									% forward message to client session for delivery
									NewPacketId = if (QoS =:= 0) -> undefined;
														true ->
															if PacketId =:= undefined ->
																	10;
																true ->
																	PacketId
															end
												  end,
									gen_fsm:send_all_state_event(Dest, {publish, {QoS, Topic, NewPacketId, Payload}}),
									Hits+1
							end
					end,
					maps:fold(F, 0, proplists:get_value(retmap, State))
				end
				|| {Filter, QoS} <- FilterTable],
	io:format("Retain matchs count ~p ~n", [Matchs]),
	{noreply, State};

handle_cast({Operation = broom, Client}, State) ->
	io:format("Mbutler: ~p - ~p ~n", [Operation, Client]),
	NewSubMap = remove_sub(all, Client, proplists:get_value(submap, State)),
	{noreply, [{submap, NewSubMap} | proplists:delete(submap,State)]};

handle_cast(Msg, State) ->
	io:format("Mbutler: received - ~p ~n", [Msg]),
	%SubMap = proplists:get_value(submap, State),
	{noreply, State}.

handle_info(Event, State) ->
	io:format("Handle info unknow event is ~p ~n", [Event]),
	{noreply, State}.


terminate(_Reason, _State) ->
	ok.

    
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%----------------------------------------------------------------------------
%% Subscription Map Operations
%%----------------------------------------------------------------------------

update_sub(Topic, Instance = {Client, _QoS}, Map) ->
	case maps:find(Topic, Map) of
		error ->
			maps:put(Topic, [Instance], Map);
			
		{ok, SubscList} ->
			NewSubscList = lists:keydelete(Client, 1, SubscList),
			maps:update(Topic, [Instance | NewSubscList], Map)
	end.

remove_sub(all, Client, Map) ->
	maps:fold(fun(Topic, SubscList, CurMap) ->
					NewSubscList = lists:keydelete(Client, 1, SubscList),
					maps:update(Topic, NewSubscList, CurMap)
			  end, Map, Map);

remove_sub(Topic, Client, Map) ->
	case maps:find(Topic, Map) of
		error ->
			Map;
			
		{ok, SubscList} ->
			NewSubscList = lists:keydelete(Client, 1, SubscList),
			maps:update(Topic, NewSubscList, Map)
	end.

%%----------------------------------------------------------------------------
%% Subscription Map Operations
%%----------------------------------------------------------------------------
update_retain({_Retain, _PacketId, Topic, _Payload = <<>>}, Map) ->
	io:format("update retain no payload ~p ~n", [Map]),

	case maps:find(Topic, Map) of
		error ->
			Map;
			
		{ok, _} ->
			maps:remove(Topic, Map)
	end;

update_retain({_Retain, PacketId, Topic, Payload}, Map) ->
	io:format("update retain  payload ~p ~p ~n", [Map, Payload]),

	case maps:find(Topic, Map) of
		error ->
			maps:put(Topic, {PacketId, Payload}, Map);
			
		{ok, _} ->
			maps:update(Topic, {PacketId, Payload}, Map)
	end.

