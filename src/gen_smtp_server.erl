%%% Copyright 2009 Andrew Thompson <andrew@hijacked.us>. All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%
%%%   1. Redistributions of source code must retain the above copyright notice,
%%%      this list of conditions and the following disclaimer.
%%%   2. Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in the
%%%      documentation and/or other materials provided with the distribution.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE FREEBSD PROJECT ``AS IS'' AND ANY EXPRESS OR
%%% IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
%%% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
%%% EVENT SHALL THE FREEBSD PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
%%% INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
%%% ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
%%% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

%% @doc A non-blocking tcp listener for SMTP connections. Based on the tcp_listener module by Serge
%% Aleynikov [http://www.trapexit.org/Building_a_Non-blocking_TCP_server_using_OTP_principles]

-module(gen_smtp_server).

-define(PORT, 2525).

%% External API
-export([
	start/3, start/2, start/1,
	stop/1, child_spec/3, sessions/1]).
-export_type([options/0]).

-type server_name() :: any().
-type options() ::
		[{domain, string()}
		 | {address, inet:ip4_address()}
		 | {port, inet:port_number()}
		 | {protocol, 'tcp' | 'ssl'}
		 | {ranch_opts, ranch:opts()}
		 | {sessionoptions, gen_smtp_server_session:options()}].

%% @doc Start the listener as a registered process with callback module `Module' with options `Options' linked to no process.
-spec start(ServerName :: server_name(),
			CallbackModule :: module(),
			Options :: [options()]) -> {'ok', pid()} | {'error', any()}.
start(ServerName, CallbackModule, Options) when is_list(Options) ->
	{ok, Transport, TransportOpts, ProtocolOpts} = convert_options(CallbackModule, Options),
	ranch:start_listener(
	  ServerName, Transport, TransportOpts, gen_smtp_server_session, ProtocolOpts).

child_spec(ServerName, CallbackModule, Options) ->
	{ok, Transport, TransportOpts, ProtocolOpts} = convert_options(CallbackModule, Options),
	ranch:child_spec(ServerName, Transport, TransportOpts, gen_smtp_server_session, ProtocolOpts).

convert_options(CallbackModule, Options) ->
	Transport = case proplists:get_value(protocol, Options, tcp) of
					tcp -> ranch_tcp;
					ssl -> ranch_ssl
				end,
	Family = proplists:get_value(family, Options, inet),
	Address = proplists:get_value(address, Options, {0, 0, 0, 0}),
	Port = proplists:get_value(port, Options, ?PORT),
	Hostname = proplists:get_calue(domain, Options, smtp_util:guess_FQDN()),
	ProtocolOpts = proplists:get_value(sessionoptions, Options, []),
	ProtocolOpts1 = [{callback, CallbackModule},
					 {hostname, Hostname}
					 | ProtocolOpts],
	RanchOpts = proplists:get_value(ranch_opts, Options, #{}),
	%% TODO: socket:?TCP_LISTEN_OPTIONS
	TransportOpts = RanchOpts#{
					  socket_opts =>
						  [{port, Port},
						   {ip, Address},
						   {packet, line},
						   {keepalive, true}
						   %% binary, {active, false}, {reuseaddr, true} - ranch defaults
						   | Family]},
	{ok, Transport, TransportOpts, ProtocolOpts1}.


%% @doc Start the listener with callback module `Module' with options `Options' linked to no process.
-spec start(CallbackModule :: module(), Options :: [options()]) -> {'ok', pid()} | 'ignore' | {'error', any()}.
start(CallbackModule, Options) when is_list(Options) ->
	start(?MODULE, CallbackModule, Options).

%% @doc Start the listener with callback module `Module' with default options linked to no process.
-spec start(CallbackModule :: atom()) -> {'ok', pid()} | 'ignore' | {'error', any()}.
start(CallbackModule) ->
	start(CallbackModule, []).

%% @doc Stop the listener pid() `Pid' with reason `normal'.
-spec stop(Name :: server_name()) -> 'ok'.
stop(Name) ->
	ranch:stop_listener(Name).

%% @doc Return the list of active SMTP session pids.
-spec sessions(Name :: server_name()) -> [pid()].
sessions(Name) ->
	ranch:procs(Name, connections).
