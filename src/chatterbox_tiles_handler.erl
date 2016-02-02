-module(chatterbox_tiles_handler).

-include_lib("chatterbox/include/http2.hrl").

-export([spawn_handle/4,
         handle/4]).

-define(WIDTH, 500).
-define(HEIGHT, 414).

spawn_handle(Pid, StreamId, Headers, ReqBody) ->
    Handler = fun() ->
        handle(Pid, StreamId, Headers, ReqBody)
    end,
    spawn_link(Handler).

handle(ConnPid, StreamId, Headers, _ReqBody) ->
    lager:debug("handle(~p, ~p, ~p, _)", [ConnPid, StreamId, Headers]),
    Path = proplists:get_value(<<":path">>, Headers),
    case binary:split(Path, <<"?">>) of
        [_, EncodedQS] ->
            case qsp:decode(EncodedQS) of
                #{<<"x">> := X, <<"y">> := Y} = DecodedQS ->
                    Latency = maps:get(<<"latency">>, DecodedQS, <<"0">>),
                    timer:sleep(binary_to_integer(Latency)),
                    [{_, Binary}] = ets:lookup(tiles, {binary_to_integer(X), binary_to_integer(Y)}),
                    http2_connection:send_body(ConnPid, StreamId, Binary);
                DecodedQS ->
                    Latency = maps:get(<<"latency">>, DecodedQS, <<"0">>),
                    tiles_page(ConnPid, StreamId, Latency)
            end;
        _ ->
            tiles_page(ConnPid, StreamId, <<"0">>)
    end.

tiles_page(ConnPid, StreamId, Latency) ->
    ResponseHeaders = [{<<":status">>,<<"200">>},
                       {<<"content-type">>, <<"text/html">>}],
    http2_connection:send_headers(ConnPid, StreamId, ResponseHeaders),

    CacheBust = os:system_time(nano_seconds),
    Imgs = [[[io_lib:format("<img width=32 height=32 src='/gophertiles?x=~p&y=~p&cachebust=~p&latency=~s'>", [X, Y, CacheBust, Latency])
             || X <- lists:seq(0, trunc(?WIDTH / 32))] | "<br/>\n"]
           || Y <- lists:seq(0, trunc(?HEIGHT / 32))],
    Data = <<"<html><body>A grid of 180 tiled images is below. Compare:<br/>\n", (links())/binary, "<br/>\n", (list_to_binary(Imgs))/binary, "</body></html>">>,

    http2_connection:send_body(ConnPid, StreamId, Data).

links() ->
    <<"<br/>[<a href='/?latency=0'>HTTP/2, 0 latency</a>]<br>[<a href='/?latency=30'>HTTP/2, 30ms latency</a>]<br>[<a href='/?latency=200'>HTTP/2, 200ms latency</a>]<br>[<a href='/?latency=1000'>HTTP/2, 1s latency</a>]<br>">>.