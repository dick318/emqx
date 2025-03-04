%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% Define the default actions.
-module(emqx_web_hook_actions).

-export([ on_resource_create/2
        , on_get_resource_status/2
        , on_resource_destroy/2
        ]).

-export([ on_action_create_data_to_webserver/2
        , on_action_data_to_webserver/2
        ]).

-export_type([action_fun/0]).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("emqx_rule_engine/include/rule_actions.hrl").

-type(action_fun() :: fun((Data :: map(), Envs :: map()) -> Result :: any())).

-type(url() :: binary()).

-define(RESOURCE_TYPE_WEBHOOK, 'web_hook').
-define(RESOURCE_CONFIG_SPEC, #{
    url => #{order => 1,
             type => string,
             format => url,
             required => true,
             title => #{en => <<"Request URL">>,
                        zh => <<"请求 URL"/utf8>>},
             description => #{en => <<"The URL of the server that will receive the Webhook requests.">>,
                              zh => <<"用于接收 Webhook 请求的服务器的 URL。"/utf8>>}},
    connect_timeout => #{order => 2,
                         type => string,
                         default => <<"5s">>,
                         title => #{en => <<"Connect Timeout">>,
                                    zh => <<"连接超时时间"/utf8>>},
                         description => #{en => <<"Connect Timeout In Seconds">>,
                                          zh => <<"连接超时时间"/utf8>>}},
    request_timeout => #{order => 3,
                         type => string,
                         default => <<"5s">>,
                         title => #{en => <<"Request Timeout">>,
                                    zh => <<"请求超时时间"/utf8>>},
                         description => #{en => <<"Request Timeout In Seconds">>,
                                          zh => <<"请求超时时间"/utf8>>}},
    pool_size => #{order => 4,
                   type => number,
                   default => 8,
                   title => #{en => <<"Pool Size">>, zh => <<"连接池大小"/utf8>>},
                   description => #{en => <<"Connection Pool">>,
                                    zh => <<"连接池大小"/utf8>>}
                },
    enable_pipelining => #{order => 5,
                           type => boolean,
                           default => true,
                           title => #{en => <<"Enable Pipelining">>, zh => <<"Enable Pipelining"/utf8>>},
                           description => #{en => <<"Whether to enable HTTP Pipelining">>,
                                            zh => <<"是否开启 HTTP Pipelining"/utf8>>}
                },
    cacertfile => #{order => 6,
                    type => file,
                    default => <<"">>,
                    title => #{en => <<"CA Certificate File">>,
                               zh => <<"CA 证书文件"/utf8>>},
                    description => #{en => <<"CA Certificate file">>,
                                     zh => <<"CA 证书文件"/utf8>>}},
    keyfile => #{order => 7,
                 type => file,
                 default => <<"">>,
                 title =>#{en => <<"SSL Key">>,
                           zh => <<"SSL Key"/utf8>>},
                 description => #{en => <<"Your ssl keyfile">>,
                                  zh => <<"SSL 私钥"/utf8>>}},
    certfile => #{order => 8,
                  type => file,
                  default => <<"">>,
                  title => #{en => <<"SSL Cert">>,
                             zh => <<"SSL Cert"/utf8>>},
                  description => #{en => <<"Your ssl certfile">>,
                                   zh => <<"SSL 证书"/utf8>>}},
    verify => #{order => 9,
                type => boolean,
                default => false,
                title => #{en => <<"Verify Server Certfile">>,
                           zh => <<"校验服务器证书"/utf8>>},
                description => #{en => <<"Whether to verify the server certificate. By default, the client will not verify the server's certificate. If verification is required, please set it to true.">>,
                                 zh => <<"是否校验服务器证书。 默认客户端不会去校验服务器的证书，如果需要校验，请设置成true。"/utf8>>}},
    server_name_indication => #{order => 10,
                                type => string,
                                title => #{en => <<"Server Name Indication">>,
                                           zh => <<"服务器名称指示"/utf8>>},
                                description => #{en => <<"Specify the hostname used for peer certificate verification, or set to disable to turn off this verification.">>,
                                                 zh => <<"指定用于对端证书验证时使用的主机名，或者设置为 disable 以关闭此项验证。"/utf8>>}}
}).

-define(ACTION_PARAM_RESOURCE, #{
    order => 0,
    type => string,
    required => true,
    title => #{en => <<"Resource ID">>,
               zh => <<"资源 ID"/utf8>>},
    description => #{en => <<"Bind a resource to this action">>,
                     zh => <<"给动作绑定一个资源"/utf8>>}
}).

-define(ACTION_DATA_SPEC, #{
            '$resource' => ?ACTION_PARAM_RESOURCE,
            method => #{
                order => 1,
                type => string,
                enum => [<<"POST">>, <<"DELETE">>, <<"PUT">>, <<"GET">>],
                default => <<"POST">>,
                title => #{en => <<"Method">>,
                           zh => <<"Method"/utf8>>},
                description => #{en => <<"HTTP Method.\n"
                                         "Note that: the Body option in the Action will be discarded in case of GET or DELETE method.">>,
                                 zh => <<"HTTP Method。\n"
                                         "注意：当方法为 GET 或 DELETE 时，动作中的 Body 选项会被忽略。"/utf8>>}},
            path => #{
                order => 2,
                type => string,
                required => false,
                default => <<"">>,
                title => #{en => <<"Path">>,
                           zh => <<"Path"/utf8>>},
                description => #{en => <<"The path part of the URL, support using ${Var} to get the field value output by the rule.">>,
                                 zh => <<"URL 的路径部分，支持使用 ${Var} 获取规则输出的字段值。\n"/utf8>>}
            },
            headers => #{
                order => 3,
                type => object,
                schema => #{},
                default => #{<<"content-type">> => <<"application/json">>},
                title => #{en => <<"Headers">>,
                           zh => <<"Headers"/utf8>>},
                description => #{en => <<"HTTP headers.">>,
                                 zh => <<"HTTP headers。"/utf8>>}},
            body => #{
                order => 4,
                type => string,
                input => textarea,
                required => false,
                default => <<"">>,
                title => #{en => <<"Body">>,
                           zh => <<"Body"/utf8>>},
                description => #{en => <<"The HTTP body supports the use of ${Var} to obtain the field value output by the rule.\n"
                                         "The content of the default HTTP request body is a JSON string composed of the keys and values of all fields output by the rule.">>,
                                 zh => <<"HTTP 请求体，支持使用 ${Var} 获取规则输出的字段值\n"
                                         "默认 HTTP 请求体的内容为规则输出的所有字段的键和值构成的 JSON 字符串。"/utf8>>}}
            }).

-resource_type(
    #{name => ?RESOURCE_TYPE_WEBHOOK,
      create => on_resource_create,
      status => on_get_resource_status,
      destroy => on_resource_destroy,
      params => ?RESOURCE_CONFIG_SPEC,
      title => #{en => <<"WebHook">>,
                 zh => <<"WebHook"/utf8>>},
      description => #{en => <<"WebHook">>,
                       zh => <<"WebHook"/utf8>>}
}).

-rule_action(#{name => data_to_webserver,
    category => data_forward,
    for => '$any',
    create => on_action_create_data_to_webserver,
    params => ?ACTION_DATA_SPEC,
    types => [?RESOURCE_TYPE_WEBHOOK],
    title => #{en => <<"Data to Web Server">>,
               zh => <<"发送数据到 Web 服务"/utf8>>},
    description => #{en => <<"Forward Messages to Web Server">>,
                     zh => <<"将数据转发给 Web 服务"/utf8>>}
}).

%%------------------------------------------------------------------------------
%% Actions for web hook
%%------------------------------------------------------------------------------

-spec(on_resource_create(binary(), map()) -> map()).
on_resource_create(ResId, Conf) ->
    {ok, _} = application:ensure_all_started(ehttpc),
    Options = pool_opts(Conf, ResId),
    PoolName = pool_name(ResId),
    case test_http_connect(Conf) of
        true -> ok;
        false -> error({error, check_http_connectivity_failed})
    end,
    start_resource(ResId, PoolName, Options),
    Conf#{<<"pool">> => PoolName, options => Options}.

start_resource(ResId, PoolName, Options) ->
    case ehttpc_pool:start_pool(PoolName, Options) of
        {ok, _} ->
            ?LOG(info, "Initiated Resource ~p Successfully, ResId: ~p",
                 [?RESOURCE_TYPE_WEBHOOK, ResId]);
        {error, {already_started, _Pid}} ->
            on_resource_destroy(ResId, #{<<"pool">> => PoolName}),
            start_resource(ResId, PoolName, Options);
        {error, Reason} ->
            ?LOG(error, "Initiate Resource ~p failed, ResId: ~p, ~0p",
                 [?RESOURCE_TYPE_WEBHOOK, ResId, Reason]),
            error({{?RESOURCE_TYPE_WEBHOOK, ResId}, create_failed})
    end.

-spec(on_get_resource_status(binary(), map()) -> map()).
on_get_resource_status(_ResId, Conf) ->
    #{is_alive => test_http_connect(Conf)}.

-spec(on_resource_destroy(binary(), map()) -> ok | {error, Reason::term()}).
on_resource_destroy(ResId, #{<<"pool">> := PoolName}) ->
    ?LOG(info, "Destroying Resource ~p, ResId: ~p", [?RESOURCE_TYPE_WEBHOOK, ResId]),
    case ehttpc_pool:stop_pool(PoolName) of
        ok ->
            ?LOG(info, "Destroyed Resource ~p Successfully, ResId: ~p", [?RESOURCE_TYPE_WEBHOOK, ResId]);
        {error, Reason} ->
            ?LOG(error, "Destroy Resource ~p failed, ResId: ~p, ~p", [?RESOURCE_TYPE_WEBHOOK, ResId, Reason]),
            error({{?RESOURCE_TYPE_WEBHOOK, ResId}, destroy_failed})
    end.

%% An action that forwards publish messages to a remote web server.
-spec(on_action_create_data_to_webserver(Id::binary(), #{url() := string()}) -> {bindings(), NewParams :: map()}).
on_action_create_data_to_webserver(Id, Params) ->
    #{method := Method,
      path := Path,
      headers := Headers,
      body := Body,
      pool := Pool,
      request_timeout := RequestTimeout} = parse_action_params(Params),
    BodyTokens = emqx_rule_utils:preproc_tmpl(Body),
    PathTokens = emqx_rule_utils:preproc_tmpl(Path),
    Params.

on_action_data_to_webserver(Selected, _Envs =
                            #{?BINDING_KEYS := #{
                                'Id' := Id,
                                'Method' := Method,
                                'Headers' := Headers,
                                'PathTokens' := PathTokens,
                                'BodyTokens' := BodyTokens,
                                'Pool' := Pool,
                                'RequestTimeout' := RequestTimeout},
                              clientid := ClientID}) ->
    NBody = format_msg(BodyTokens, Selected),
    NPath = emqx_rule_utils:proc_tmpl(PathTokens, Selected),
    Req = create_req(Method, NPath, Headers, NBody),
    case ehttpc:request({Pool, ClientID}, Method, Req, RequestTimeout) of
        {ok, StatusCode, _} when StatusCode >= 200 andalso StatusCode < 300 ->
            emqx_rule_metrics:inc_actions_success(Id);
        {ok, StatusCode, _, _} when StatusCode >= 200 andalso StatusCode < 300 ->
            emqx_rule_metrics:inc_actions_success(Id);
        {ok, StatusCode, _} ->
            ?LOG(warning, "HTTP request failed with path: ~p status code: ~p", [NPath, StatusCode]),
            emqx_rule_metrics:inc_actions_error(Id);
        {ok, StatusCode, _, _} ->
            ?LOG(warning, "HTTP request failed with path: ~p status code: ~p", [NPath, StatusCode]),
            emqx_rule_metrics:inc_actions_error(Id);
        {error, Reason} ->
            ?LOG(error, "HTTP request failed path: ~p error: ~p", [NPath, Reason]),
            emqx_rule_metrics:inc_actions_error(Id)
    end.

format_msg([], Data) ->
    emqx_json:encode(Data);
format_msg(Tokens, Data) ->
     emqx_rule_utils:proc_tmpl(Tokens, Data).

%%------------------------------------------------------------------------------
%% Internal functions
%%------------------------------------------------------------------------------

create_req(Method, Path, Headers, _Body)
  when Method =:= get orelse Method =:= delete ->
    {Path, Headers};
create_req(_, Path, Headers, Body) ->
  {Path, Headers, Body}.

parse_action_params(Params = #{<<"url">> := URL}) ->
    {ok, #{path := CommonPath}} = emqx_http_lib:uri_parse(URL),
    Method = method(maps:get(<<"method">>, Params, <<"POST">>)),
    Headers = headers(maps:get(<<"headers">>, Params, #{})),
    NHeaders = ensure_content_type_header(Headers, Method),
    #{method => Method,
      path => merge_path(CommonPath, maps:get(<<"path">>, Params, <<>>)),
      headers => NHeaders,
      body => maps:get(<<"body">>, Params, <<>>),
      request_timeout => cuttlefish_duration:parse(str(maps:get(<<"request_timeout">>, Params, <<"5s">>))),
      pool => maps:get(<<"pool">>, Params)}.

ensure_content_type_header(Headers, Method) when Method =:= post orelse Method =:= put ->
    Headers;
ensure_content_type_header(Headers, _Method) ->
    lists:keydelete(<<"content-type">>, 1, Headers).

merge_path(CommonPath, <<>>) ->
    l2b(CommonPath);
merge_path(CommonPath, Path) ->
    Path1 = case Path of
                <<"/", Path0/binary>> -> Path0;
                _ -> Path
            end,
    l2b(filename:join(CommonPath, Path1)).

method(GET) when GET == <<"GET">>; GET == <<"get">> -> get;
method(POST) when POST == <<"POST">>; POST == <<"post">> -> post;
method(PUT) when PUT == <<"PUT">>; PUT == <<"put">> -> put;
method(DEL) when DEL == <<"DELETE">>; DEL == <<"delete">> -> delete.

headers(Headers) ->
    emqx_http_lib:normalise_headers(maps:to_list(Headers)).

str(Str) when is_list(Str) -> Str;
str(Atom) when is_atom(Atom) -> atom_to_list(Atom);
str(Bin) when is_binary(Bin) -> binary_to_list(Bin).

pool_opts(Params = #{<<"url">> := URL}, ResId) ->
    {ok, #{host := Host,
           port := Port,
           scheme := Scheme}} = emqx_http_lib:uri_parse(URL),
    PoolSize = maps:get(<<"pool_size">>, Params, 32),
    ConnectTimeout =
        cuttlefish_duration:parse(str(maps:get(<<"connect_timeout">>, Params, <<"5s">>))),
    TransportOpts0 =
        case Scheme =:= https of
            true  -> get_ssl_opts(Params, ResId);
            false -> []
        end,
    TransportOpts = emqx_misc:ipv6_probe(TransportOpts0),
    EnablePipelining = maps:get(<<"enable_pipelining">>, Params, true),
    Opts = case Scheme =:= https  of
               true  -> [{transport_opts, TransportOpts}, {transport, ssl}];
               false -> [{transport_opts, TransportOpts}]
           end,
    [{host, Host},
     {port, Port},
     {enable_pipelining, EnablePipelining},
     {pool_size, PoolSize},
     {pool_type, hash},
     {connect_timeout, ConnectTimeout},
     {retry, 5},
     {retry_timeout, 1000} | Opts].

pool_name(ResId) ->
    list_to_atom("webhook:" ++ str(ResId)).

get_ssl_opts(Opts, ResId) ->
    emqx_plugin_libs_ssl:save_files_return_opts(Opts, "rules", ResId).

test_http_connect(Conf) ->
    Url = fun() -> maps:get(<<"url">>, Conf) end,
    try
       emqx_rule_utils:http_connectivity(Url())
    of
       ok -> true;
       {error, _Reason} ->
           ?LOG(error, "check http_connectivity failed: ~p", [Url()]),
           false
    catch
        Err:Reason:ST ->
           ?LOG(error, "check http_connectivity failed: ~p, ~0p", [Conf, {Err, Reason, ST}]),
           false
    end.
l2b(L) when is_list(L) -> iolist_to_binary(L);
l2b(Any) -> Any.
