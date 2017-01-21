%%%-------------------------------------------------------------------
%%% @author eokeke
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. Jan 2017 10:33 AM
%%%-------------------------------------------------------------------
-module(erlang_postmarkapp_request).
-author("eokeke").
-include("erlang_postmarkapp.hrl").

%% API
-export([
    get_default_headers/0,
    get_server_token/0,
    request/3,
    request/4,
    http_build_query/1
]).

-type requestMethod() :: delete | get | post | put.
-type queryParamValue() :: string() | integer() | atom() | float() | binary().
-type queryParam() :: {string(), queryParamValue()} | {binary(), queryParamValue()}.
-type resultKey() :: headers | body.
-type body() :: {json, list()} | {string, string()}.
-spec get_server_token() -> string().
-spec request(Method::requestMethod(), Endpoint::string(), Body::body()) ->
    [{resultKey(), list()}] | {error, integer(), term()} | {error, fail, string()}.
-spec request(Method::requestMethod(), Endpoint::string(), Body::string(), Headers::list()) ->
    [{resultKey(), list()}] | {error, integer(), term()} | {error, fail, string()}.
-spec http_build_query(QueryParams::queryParam()) -> string().

%% @spec get_server_token() -> string()
%% @doc returns the server token saved to the postmark ets table using the server_token key
get_server_token() ->
    case ets:lookup(?POSTMARK_ETS_TABLE, ?POSTMARK_ETS_SERVER_TOKEN_KEY) of
        [{?POSTMARK_ETS_SERVER_TOKEN_KEY, ServerToken}] -> ServerToken;
        _ -> ""
    end.

%% @doc returns the default request headers
get_default_headers() ->
    [
        {"Accept", ?POSTMARK_CONTENT_TYPE},
        {"X-Postmark-Server-Token", get_server_token()}
    ].

%% @spec request(Method::requestMethod(), Endpoint::string(), Body::body()) -> [{resultKey(), list()}] | {error, int(), term()} | {error, fail, string()}
%% @doc makes a request to the API appending the <code>Endpoint</code> to the base Url; Body is a proplist.
request(Method, Endpoint, Body) ->
    case Body of
        {json, Payload} ->
            request(Method, Endpoint, jsx:encode(Payload), get_default_headers());
        {string, Json} ->
            request(Method, Endpoint, Json, get_default_headers())
    end.

%% @spec request(Method::requestMethod(), Endpoint::string(), Body::string(), Headers::list()) -> [{resultKey(), list()}] | {error, integer(), term()} | {error, fail, string()}.
%% @doc makes a request to the API appending the <code>Endpoint</code> to the base Url.
request(Method, Endpoint, Payload, Headers) ->
    Url = string:join([?POSTMARK_REST_URL, Endpoint], "/"),
    ContentType = proplists:get_value("content-type", Headers, ?POSTMARK_CONTENT_TYPE),
    io:format("Request Url: ~p~n", [Url]),
    io:format("Request Headers: ~p~n", [Headers]),
    io:format("Request Body: ~p~n", [Payload]),
    case Method of
        get ->
            process_response(httpc:request(get, {Url, Headers}, [], []));
        _ ->
            io:format("Content-Type: ~p~n", [ContentType]),
            process_response(httpc:request(Method, {Url, Headers, ContentType, Payload}, ?POSTMARK_REQUEST_OPTS, []))
    end.

%% @doc processes the response from the <code>httpc:request/4</code> call, returning an appropriate response
process_response(HttpResponse) ->
    try HttpResponse of
        {ok, {{_HttpVersion, 200, _Phrase}, ResponseHeaders, []}} ->
            %% successfully got a response from the server
            [{headers, ResponseHeaders}, {body, []}];
        {ok, {{_HttpVersion, 200, _Phrase}, ResponseHeaders, Body}} ->
            %% successfully got a response from the server
            io:format("Response Body: ~p~n", [Body]),
            [{headers, ResponseHeaders}, {body, jsx:decode(list_to_binary(Body))}];
        {ok, {{_HttpVersion, HttpStatus, _Phrase}, _ResponseHeaders, Body}} ->
            %% the request did not succeed -- some other http status other than 200
            {error, HttpStatus, Body};
        {ok, {200, Body}} ->
            [{headers, []}, {body, jsx:decode(list_to_binary(Body))}];
        {ok, {StatusCode, Body}} ->
            io:format("~s:send() -> StatusCode: ~p ~p~n", [?MODULE, StatusCode, Body]),
            {error, StatusCode, Body};
        {error, Reason} ->
            io:format("error: ~p~n", [Reason]),
            {error, fail, Reason}
    catch
        error:badarg -> io:format("Error:badarg");
        error:Error -> io:format("Error: ~p~n", [Error])
    end.

%% @spec http_build_query(QueryParams::queryParam()) -> string().
%% @doc converts a list of query parameters to a query string
http_build_query(QueryParams) when is_list(QueryParams) ->
    ParamsList = lists:map(fun (Param) ->
        case Param of
            {Key, Value} ->
                if
                    is_binary(Value) ->
                        string:join([process_query_key(Key), http_uri:encode(binary_to_list(Value))], "=");
                    is_atom(Value) ->
                        string:join([process_query_key(Key), http_uri:encode(atom_to_list(Value))], "=");
                    true -> string:join([process_query_key(Key), http_uri:encode(Value)], "=")
                end;
            _ -> ""
        end
    end, QueryParams),
    string:join(ParamsList, "&");

%% @spec http_build_query(QueryParams::queryParam()) -> string().
%% @doc converts a list of query parameters to a query string
http_build_query(_) ->
    "".

%% @doc converts a query key to a format that can be used in a URL
process_query_key(Key) ->
    if
        is_list(Key) -> lists:flatten(Key);
        is_atom(Key) -> atom_to_list(Key);
        is_binary(Key) -> binary_to_list(Key);
        true -> Key
    end.