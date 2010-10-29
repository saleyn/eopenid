%%%-------------------------------------------------------------------
%%% Copyright (c) 2008-2009 Torbjorn Tornkvist
%%% See the (MIT) LICENSE file for licensing information.
%%%
%%% Created   :  3 Apr 2008 by Torbjorn Tornkvist <tobbe@tornkvist.org>
%%% Re-worked :  7 Feb 2009 by Torbjorn Tornkvist <tobbe@tornkvist.org>
%%% Desc.     :  Implementation of OpenID v1.1 
%%%
%%%-------------------------------------------------------------------
-module(eopenid_lib).

-export([http_get/1
         ,http_get/2
         ,http_post/4
         ,http_path_norm/1
         ,new/0
         ,out/2
         ,in/2
         ,in/3
         ,foldf/2
         ,add/3
         ,b2l/1
         ,i2l/1
         ,l2i/1
         %%,gen_DHa/0
         %%,gen_DHb/0
         %%,gen_DHp/0
         %%,gen_DHg/0
         ,mk_dh/0
         ,urlenc/1
         ,parseq/1
         ,content_type/0
         ,implode/2
         ,roll/1
         ,unroll/1
         ,decrypt_mac_key/1
         ,compute_K/1
         ,compute_B/1
         ,gnow/0
        ]).

-ignore_xref([{http_get,2}
              ,{add,3}
              ,{implode,2}
              ,{unroll,1}
             ]).


%%%
%%% DICT API
%%%
new() ->
    orddict:new(). 

%%% Should crash if no value is found
out(Key, DB) ->
    {ok, Value} = orddict:find(Key, DB),
    Value.

%%% 
in(Key, Value) ->
    fun(Data) -> in(Key, Value, Data) end.

in(Key, Value, DB) ->
    orddict:store(Key, Value, DB).

%%% 
foldf([], DB)    -> DB;
foldf([H|T], DB) -> foldf(T, H(DB)).

%%% Add value to a list of values.
add(Key, Value, Data) ->
    try out(Key, Data) of
        L when is_list(L) -> in(Key, [Value|L], Data)
    catch
        _:_ -> in(Key, [Value], Data)
    end.                                              
            

%%%
%%%@doc Perform an HTTP GET request.
%%%@end
http_get(Url) ->    
    http_get(Url, []).

http_get(Url, Hdrs) ->    
    http:request(get, {Url, Hdrs}, [], []).

%%% 
%%%@doc Perform an HTTP POST request.
%%%@end
http_post(Url, Hdrs, ContentType, Body) ->
    http:request(post, {Url,Hdrs,ContentType,Body}, [], []).
    

%%%
%%%@doc Parse an nomalize the OpenID path.
%%%     FIXME: Should be done according to ch.6 in RFC 3986.
%%%@end
http_path_norm("http://"++_ = Path)  -> Path;
http_path_norm("https://"++_ = Path) -> Path;
http_path_norm(Path)                 -> "http://"++Path.

%%% btwoc() in Spec
roll(N) when is_integer(N) ->
    <<_Size:32, Bin/binary>> = crypto:mpint(N),
    Bin.

%%% The inverse to btwoc()
unroll(Bin) when is_binary(Bin) ->
    Size = size(Bin),
    crypto:erlint(<<Size:32, Bin/binary>>).


decrypt_mac_key(Dict) ->
    EncMacKey = base64:decode(out("enc_mac_key",Dict)),
    Kbin = roll(out("K",Dict)),
    in("mac_key", crypto:exor(EncMacKey, crypto:sha(Kbin)), Dict).

compute_K(Dict) ->
    B   = out("B",Dict),
    DHa = out("a",Dict),
    P   = out("p",Dict),
    K   = crypto:mod_exp(B,DHa,P),
    in("K",K,Dict).

compute_B(Dict) ->
    C = base64:decode(out("dh_server_public",Dict)),
    Size = size(C),
    in("B", crypto:erlint(<<Size:32,C/binary>>), Dict).
    

    

b2l(B) when is_binary(B) -> binary_to_list(B);
b2l(L) when is_list(L)   -> L.

i2l(I) when is_integer(I) -> integer_to_list(I);
i2l(L) when is_list(L)    -> L.

l2i(L) when is_list(L)    -> list_to_integer(L);
l2i(I) when is_integer(I) -> I.

urlenc(X) -> 
    try mochiweb_util:urlencode(X)
    catch _:_ -> 
            S = [K++"="++url_encode(V) || {K,V} <- X],
            string:join(S,"&") 
    end.

url_encode(X) ->
    try yaws_api:url_encode(X)
    catch _:_ -> wf:url_encode(X) end.
            
url_decode(X) ->
    try yaws_api:url_decode(X)
    catch _:_ -> wf:url_decode(X) end.
            
parseq(X) -> 
    try mochiweb_util:parse_qs(X)
    catch _:_ -> 
            Filter = fun(S,Acc) -> 
                             case string:tokens(S,"=") of
                                 [K,V] -> [{K,url_decode(V)}|Acc];
                                 _     -> Acc
                             end
                     end,
            lists:foldr(Filter, [], string:tokens(X,"&"))
    end.
            

content_type() -> 
    "application/x-www-form-urlencoded; charset=UTF-8".
    

%%%
%%% http://blog.diginux.net/2006/11/15/adding-aes-encryption-to-erlang-chat/
%%% "For the curious, 2^127+1 = 170141183460469231731687303715884105729,
%%%  and 2^128-1 = 340282366920938463463374607431768211455. Generating a 
%%%  number in this range assures us we get a number that is at least 128 bits."
%%%
gen_DHa() -> gen_DHb().
gen_DHb() -> crypto:rand_uniform(170141183460469231731687303715884105729,
                                 340282366920938463463374607431768211455).  

%%%
%%% http://en.wikipedia.org/wiki/Diffie-Hellman
%%% "If p were a prime of at least 300 digits, and a and b were at least 
%%%  100 digits long, then even the best algorithms known today could not 
%%%  find a given only g, p, and ga mod p, even using all of mankind's 
%%%  computing power. The problem is known as the discrete logarithm problem. 
%%%  Note that g need not be large at all, and in practice is usually either 
%%%  2 or 5."
%%%
gen_DHp() -> p().
gen_DHg() -> 5.


mk_dh() ->
    G = gen_DHg(),
    P = gen_DHp(),
    DHa = gen_DHa(),
    A = crypto:mod_exp(G,DHa,P),
    {A,DHa,G,P}.

%%% Defalt value according to spec.
p() ->
    155172898181473697471232257763715539915724801966915404479707795314057629378541917580651227423698188993727816152646631438561595825688188889951272158842675419950341258706556549803580104870537681476726513255747040765857479291291572334510643245094715007229621094194349783925984760375594985848253359305585439638443.

  
%%% EXAMPLE:
%%% 1> {A,DHa,G,P}=eopenid_lib:mk_dh().
%%% {122853789384187683848765515687406992317195195379210246248249528906262062558698454381704560318138363447157621886531163473895500059730348383436552592928717969605439170164176202910156515388021808920783507671731768469935544404107320294257115518720650677818420142116770827892909529448348315136286952085451114076092,
%%%  272938908062893175391734597494701817682,5,
%%%  155172898181473697471232257763715539915724801966915404479707795314057629378541917580651227423698188993727816152646631438561595825688188889951272158842675419950341258706556549803580104870537681476726513255747040765857479291291572334510643245094715007229621094194349783925984760375594985848253359305585439638443}
%%% 2> DHb=eopenid_lib:gen_DHb().
%%% 281073998798190491382520986202640214379
%%% 4> B=crypto:mod_exp(G,DHb,P).
%%% 46103594184219076656730110575249308175112849247975656625328538376460365110272984538974587787971943875392856424599448387057161824549010916835668205276541804159971615413655143287789806492873307405833277226513845983839035236064705103149244589003312130879926213213593045273518109004943970999395656955047297475070
%%% 5> K=crypto:mod_exp(B,DHa,P).
%%% 2680186779371140946069037367882924481890279803204930827121754220815926662427921632082164526298218063708806403044343777863750108681745997252113244260112303007432673298935000286117061767177828213646738712947513030779601431300311893791839068275142763720433026054072614543357686345603964348527688543335284385690
%%% 6> K=crypto:mod_exp(A,DHb,P). 
%%% 2680186779371140946069037367882924481890279803204930827121754220815926662427921632082164526298218063708806403044343777863750108681745997252113244260112303007432673298935000286117061767177828213646738712947513030779601431300311893791839068275142763720433026054072614543357686345603964348527688543335284385690


implode(Data, Seperator) when is_list(Data) andalso is_list(Seperator) ->
    lists:foldr(fun(X,[]) -> X; (X,Acc) -> X++Seperator++Acc end, "", Data).

gnow() ->
    calendar:datetime_to_gregorian_seconds(calendar:local_time()).
