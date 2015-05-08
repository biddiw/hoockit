%%-----------------------------------------------------------------------------
%% Copyright (c) 2012-2015, Feng Lee <feng@emqtt.io>
%% 
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%% 
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.
%%------------------------------------------------------------------------------

-module(hck_lib).

-author('samir.sow@biddiw.com').

-import(lists, [reverse/1]).

%% ------------------------------------------------------------------------
%% Topic semantics and usage
%% ------------------------------------------------------------------------
%% A topic must be at least one character long.
%%
%% Topic names are case sensitive. For example, ACCOUNTS and Accounts are two different topics.
%%
%% Topic names can include the space character. For example, Accounts payable is a valid topic.
%%
%% A leading "/" creates a distinct topic. For example, /finance is different from finance. /finance matches "+/+" and "/+", but not "+".
%%
%% Do not include the null character (Unicode \x0000) in any topic.
%%
%% The following principles apply to the construction and content of a topic tree:
%%
%% The length is limited to 64k but within that there are no limits to the number of levels in a topic tree.
%%
%% There can be any number of root nodes; that is, there can be any number of topic trees.
%% ------------------------------------------------------------------------

-export([match/2, parse/1, validate/1, words/1]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec match(binary(), binary()) -> boolean().

-spec validate({name | filter, binary()}) -> boolean().

-endif.

%%----------------------------------------------------------------------------

-define(MAX_TOPIC_LEN, 65535).

%% ------------------------------------------------------------------------
%% Match Topic. B1 is Topic Name, B2 is Topic Filter.
%% ------------------------------------------------------------------------
match(Name, Filter) when is_binary(Name) and is_binary(Filter) ->
	match(words(Name), words(Filter));
match([], []) ->
	true;
match([H|T1], [H|T2]) ->
	match(T1, T2);
match([<<$$, _/binary>>|_], ['+'|_]) ->
    false;
match([_H|T1], ['+'|T2]) ->
	match(T1, T2);
match([<<$$, _/binary>>|_], ['#']) ->
    false;
match(_, ['#']) ->
	true;
match([_H1|_], [_H2|_]) ->
	false;
match([_H1|_], []) ->
	false;
match([], [_H|_T2]) ->
	false.
	
%%
%% ------------------------------------------------------------------------
%% Control Subscription Filter Table 
%% ------------------------------------------------------------------------

parse(TopicTable) when is_list(TopicTable) ->
	FilterTable = [ X ||  {Topic, _QoS} = X  <- TopicTable, validate({filter, Topic})],
	if length(TopicTable) == length(FilterTable)  ->
		{ok, FilterTable};
		
		true ->
			{error, []}
	end.
	
%%
%% ------------------------------------------------------------------------
%% Validate Topic 
%% ------------------------------------------------------------------------
validate({_, <<>>}) ->
	false;
validate({_, Topic}) when is_binary(Topic) and (size(Topic) > ?MAX_TOPIC_LEN) ->
	false;
validate({filter, Topic}) when is_binary(Topic) ->
	validate2(words(Topic));
validate({name, Topic}) when is_binary(Topic) ->
	Words = words(Topic),
	validate2(Words) and (not include_wildcard(Words)).

validate2([]) ->
    true;
validate2(['#']) -> % end with '#'
    true;
validate2(['#'|Words]) when length(Words) > 0 -> 
    false; 
validate2([''|Words]) ->
    validate2(Words);
validate2(['+'|Words]) ->
    validate2(Words);
validate2([W|Words]) ->
    case validate3(W) of
        true -> validate2(Words);
        false -> false
    end.

validate3(<<>>) ->
    true;
validate3(<<C/utf8, _Rest/binary>>) when C == $#; C == $+; C == 0 ->
    false;
validate3(<<_/utf8, Rest/binary>>) ->
    validate3(Rest).

include_wildcard([])        -> false;
include_wildcard(['#'|_T])  -> true;
include_wildcard(['+'|_T])  -> true;
include_wildcard([ _ | T])  -> include_wildcard(T).

%% ------------------------------------------------------------------------
%% Split Topic to Words
%% ------------------------------------------------------------------------
words(Topic) when is_binary(Topic) ->
    [word(W) || W <- binary:split(Topic, <<"/">>, [global])].

word(<<>>)    -> '';
word(<<"+">>) -> '+';
word(<<"#">>) -> '#';
word(Bin)     -> Bin.


