%% Copyright 2009, 2010, 2011 The Piqi Authors
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
%%
%% This module reuses some code from Protobuffs library. The original code was
%% taken from here:
%%      http://github.com/ngerakines/erlang_protobuffs
%%
%% Below is the original copyright notice and the license:
%%
%% Copyright (c) 2009 
%% Nick Gerakines <nick@gerakines.net>
%% Jacob Vorreuter <jacob.vorreuter@gmail.com>
%%
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%%
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.

%%
%% @doc Piqi runtime library
%%
%% Encoding rules follow this specification:
%%
%%      http://code.google.com/apis/protocolbuffers/docs/encoding.html


-module(piqirun).
-compile(export_all).

-include("piqirun.hrl").


%
% Initialize Piqirun input buffer from binary()
%
% NOTE: this function is no longer necessary, it remains here for backwards
% compatibility with previous Piqi versions.
-spec init_from_binary/1 :: (Bytes :: binary()) ->
    % NOTE: in fact, the return type should be piqirun_buffer(). Using specific
    % buffer's variant here to avoid Dialyzer warning.
    TopBlock :: binary().

init_from_binary(Bytes) when is_binary(Bytes) -> Bytes.


%
% The functions below are used by encoders/decoders generated by "piqic erlang"
% -- they are not meant to be used directly.
%

-define(TYPE_VARINT, 0).
-define(TYPE_64BIT, 1).
-define(TYPE_STRING, 2).
-define(TYPE_START_GROUP, 3).
-define(TYPE_END_GROUP, 4).
-define(TYPE_32BIT, 5).


-type field_type() ::
    ?TYPE_VARINT | ?TYPE_64BIT | ?TYPE_STRING |
    ?TYPE_START_GROUP | ?TYPE_END_GROUP | ?TYPE_32BIT.


%% @hidden
-spec encode_field_tag/2 :: (
    Code :: piqirun_code(),
    FieldType :: field_type()) -> binary().

encode_field_tag(Code, FieldType)
        when is_integer(Code) andalso (Code band 16#3fffffff =:= Code) ->
    encode_varint_value((Code bsl 3) bor FieldType);

encode_field_tag('undefined', FieldType) ->
    % 1 is the default code for top-level primitive types
    encode_field_tag(1, FieldType).


%% @hidden
%% NOTE: `Integer` MUST be >= 0
-spec encode_varint_field/2 :: (
    Code :: piqirun_code(),
    Integer :: non_neg_integer()) -> iolist().

encode_varint_field(Code, Integer) ->
    [
        encode_field_tag(Code, ?TYPE_VARINT),
        encode_varint_value(Integer)
    ].


%% @hidden
%% NOTE: `I` MUST be >= 0
-spec encode_varint_value/1 :: (
    I :: non_neg_integer()) -> binary().

encode_varint_value(I) when I >= 0 ->
    encode_varint_1(I, 0, 1).

%% @hidden
-spec encode_varint_value(non_neg_integer(), binary()) -> binary().
encode_varint_value(I, Acc) ->
    <<Acc/binary, (encode_varint_1(I, 0, 1))/binary>>.

-spec encode_varint_1(
        non_neg_integer(),
        non_neg_integer(),
        pos_integer()) -> binary().
encode_varint_1(I, Acc, Pos) when I > 16#7f ->
    Val = I band 16#7f bor 16#80,
    encode_varint_1(I bsr 7, Acc bsl 8 bor Val, Pos + 1);
encode_varint_1(I, Acc, Pos) ->
    <<(Acc bsl 8 bor I):(Pos * 8)>>.

%% @hidden
-spec decode_varint(binary()) ->
    {I :: non_neg_integer(), Remainder :: binary()}.
decode_varint(Bytes) ->
    case decode_varint_1(Bytes) of
        {cont, _, _, _} ->
            % Return the same error as returned by
            % my_split_binary/2 when parsing fields (see
            % below). This way, when there's not enough data for
            % parsing a field, the returned error is the same
            % regardless of where it occured.
            throw_error('not_enough_data');
        I when is_integer(I) -> {I, <<>>};
        Value -> Value
    end.

-type decode_varint_1_cont() :: {cont,
                        non_neg_integer(),
                        non_neg_integer(),
                        non_neg_integer()}.
-type decode_varint_1_ret() :: non_neg_integer()
                      | {non_neg_integer(), binary()}
                      | decode_varint_1_cont().
-spec decode_varint_1(binary()) -> decode_varint_1_ret().
decode_varint_1(<<0:1, A:7>>) -> A;
decode_varint_1(<<0:1, A:7, Rest/binary>>) -> {A, Rest};
decode_varint_1(<<1:1, A:7, 0:1, B:7>>) -> B bsl 7 bor A;
decode_varint_1(<<1:1, A:7, 0:1, B:7, Rest/binary>>) ->
    {B bsl 7 bor A, Rest};
decode_varint_1(<<1:1, A:7, 1:1, B:7, 0:1, C:7>>) ->
    (C bsl 14) bor (B bsl 7) bor A;
decode_varint_1(<<1:1, A:7, 1:1, B:7, 0:1, C:7, Rest/binary>>) ->
    {(C bsl 14) bor (B bsl 7) bor A, Rest};
decode_varint_1(<<1:1, A:7, 1:1, B:7, 1:1, C:7, 0:1, D:7>>) ->
    (D bsl 21) bor (C bsl 14) bor (B bsl 7) bor A;
decode_varint_1(<<1:1, A:7, 1:1, B:7, 1:1, C:7, 0:1, D:7, Rest/binary>>) ->
    {(D bsl 21) bor (C bsl 14) bor (B bsl 7) bor A, Rest};
decode_varint_1(<<1:1, A:7, 1:1, B:7, 1:1, C:7, 1:1, D:7, _/binary>> = Bin) ->
    Acc = (D bsl 21) bor (C bsl 14) bor (B bsl 7) bor A,
    decode_varint_1(Bin, {cont, Acc, 4, 4});
decode_varint_1(Bin) ->
    decode_varint_1(Bin, {cont, 0, 0, 0}).

-spec decode_varint_1(binary(), decode_varint_1_cont()) -> decode_varint_1_ret().
decode_varint_1(Bin, {cont, Acc, X, Offset}) ->
    case Bin of
        <<_:Offset/bytes, 0:1, I:7>> ->
            Acc bor (I bsl (X * 7));
        <<_:Offset/bytes, 0:1, I:7, Rest/binary>> ->
            Result = Acc bor (I bsl (X * 7)),
            {Result, Rest};
        <<_:Offset/bytes, 1:1, I:7>> ->
            {cont, Acc bor (I bsl (X * 7)), X + 1, 0};
        <<_:Offset/bytes, 1:1, I:7, _/binary>> ->
            Acc1 = Acc bor (I bsl (X * 7)),
            decode_varint_1(Bin, {cont, Acc1, X + 1, Offset + 1})
    end.

-spec gen_block/1 :: (Data :: iodata()) -> iolist().

% get length-delimited block, where length is encoded using varint encoding.
gen_block(Data) ->
    [ encode_varint_value(iolist_size(Data)), Data ].


-spec parse_block/1 :: (Bytes :: binary()) ->
    {TopBlock :: binary(), Rest :: binary()}.

% parse length-delimited block, rases 'not_enough_data' if there's less data in
% the actual block than the "length" bytes.
parse_block(Bytes) ->
    {Length, Rest_1} = decode_varint(Bytes),
    my_split_binary(Rest_1, Length).


-spec gen_record/2 :: (
    Code :: piqirun_code(),
    Fields :: [iolist()] ) -> iolist().

-spec gen_variant/2 :: (
    Code :: piqirun_code(),
    X :: iolist() ) -> iolist().

-spec gen_list/3 :: (
    Code :: piqirun_code(),
    GenValue :: encode_fun(),
    L :: [any()] ) -> iolist().

-spec gen_packed_list/3 :: (
    Code :: piqirun_code(),
    GenValue :: packed_encode_fun(),
    L :: [any()] ) -> iolist().


gen_record(Code, Fields) ->
    Header =
        case Code of
            'undefined' -> []; % do not generate record header
            _ ->
                [ encode_field_tag(Code, ?TYPE_STRING),
                  encode_varint_value(iolist_size(Fields)) ]
        end,
    [ Header, Fields ].


gen_variant(Code, X) ->
    gen_record(Code, [X]).


gen_list(Code, GenValue, L) ->
    % NOTE: using "1" as list element's code
    gen_record(Code, [GenValue(1, X) || X <- L]).


gen_packed_list(Code, GenValue, L) ->
    % NOTE: using "1" as list element's code
    Field = gen_packed_repeated_field(1, GenValue, L),
    gen_record(Code, [Field]).


-type encode_fun() ::
     fun( (Code :: piqirun_code(), Value :: any()) -> iolist() ).

-type packed_encode_fun() ::
     fun( (Value :: any()) -> iolist() ).

-spec gen_required_field/3 :: (
    Code :: piqirun_code(),
    GenValue :: encode_fun(),
    X :: any() ) -> iolist().

-spec gen_optional_field/3 :: (
    Code :: piqirun_code(),
    GenValue :: encode_fun(),
    X :: 'undefined' | any() ) -> iolist().

-spec gen_repeated_field/3 :: (
    Code :: piqirun_code(),
    GenValue :: encode_fun(),
    X :: [any()] ) -> iolist().

-spec gen_packed_repeated_field/3 :: (
    Code :: pos_integer(),
    GenValue :: packed_encode_fun(),
    X :: [any()] ) -> iolist().


gen_required_field(Code, GenValue, X) ->
    GenValue(Code, X).


gen_optional_field(_Code, _GenValue, 'undefined') -> [];
gen_optional_field(Code, GenValue, X) ->
    GenValue(Code, X).


gen_repeated_field(Code, GenValue, L) ->
    [GenValue(Code, X) || X <- L].


gen_packed_repeated_field(_Code, _GenValue, []) ->
    % don't generate anything for empty repeated packed field
    [];
gen_packed_repeated_field(Code, GenValue, L) ->
    Contents = [GenValue(X) || X <- L],
    gen_record(Code, Contents).


-spec gen_flag/2 :: (
    Code :: piqirun_code(),
    X :: boolean()) -> iolist().

gen_flag(_Code, false) -> []; % no flag
gen_flag(Code, true) -> gen_bool_field(Code, true).


-spec non_neg_integer_to_varint/2 :: (
    Code :: piqirun_code(),
    X :: non_neg_integer()) -> iolist().

-spec integer_to_signed_varint/2 :: (
    Code :: piqirun_code(),
    X :: integer()) -> iolist().

-spec integer_to_zigzag_varint/2 :: (
    Code :: piqirun_code(),
    X :: integer()) -> iolist().

-spec boolean_to_varint/2 :: (
    Code :: piqirun_code(),
    X :: boolean()) -> iolist().

-spec gen_bool_field/2 :: (
    Code :: piqirun_code(),
    X :: boolean()) -> iolist().

-spec non_neg_integer_to_fixed32/2 :: (
    Code :: piqirun_code(),
    X :: non_neg_integer()) -> iolist().

-spec integer_to_signed_fixed32/2 :: (
    Code :: piqirun_code(),
    X :: integer()) -> iolist().

-spec non_neg_integer_to_fixed64/2 :: (
    Code :: piqirun_code(),
    X :: non_neg_integer()) -> iolist().

-spec integer_to_signed_fixed64/2 :: (
    Code :: piqirun_code(),
    X :: non_neg_integer()) -> iolist().

-spec float_to_fixed64/2 :: (
    Code :: piqirun_code(),
    X :: number() ) -> iolist().

-spec float_to_fixed32/2 :: (
    Code :: piqirun_code(),
    X :: number() ) -> iolist().

-spec binary_to_block/2 :: (
    Code :: piqirun_code(),
    X :: binary() ) -> iolist().


% NOTE, XXX: in fact, accepting chardata() defined in unicode(3erl) manpage as
% follows:
%
% unicode_binary() = binary() with characters encoded in UTF-8 coding standard
% unicode_char() = integer() representing valid unicode codepoint
%
% chardata() = charlist() | unicode_binary()
% charlist() = [unicode_char() | unicode_binary() | charlist()]
%
-spec string_to_block/2 :: (
    Code :: piqirun_code(),
    X :: string() | binary() ) -> iolist().


non_neg_integer_to_varint(Code, X) when X >= 0 ->
    encode_varint_field(Code, X).

integer_to_signed_varint(Code, X) ->
    encode_varint_field(Code, integer_to_non_neg_integer(X)).

integer_to_zigzag_varint(Code, X) ->
    encode_varint_field(Code, integer_to_zigzag_integer(X)).

boolean_to_varint(Code, X) ->
    encode_varint_field(Code, boolean_to_non_neg_integer(X)).


%% @hidden
-spec integer_to_non_neg_integer/1 :: (
    X :: integer()) -> non_neg_integer().

integer_to_non_neg_integer(X) when X >= 0 ->
    X;
integer_to_non_neg_integer(X) ->  % when X < 0
    X + (1 bsl 64).


%% @hidden
-spec integer_to_zigzag_integer/1 :: (
    X :: integer()) -> non_neg_integer().

integer_to_zigzag_integer(X) when X >= 0 ->
    X bsl 1;
integer_to_zigzag_integer(X) ->  % when X < 0
    bnot (X bsl 1).


boolean_to_non_neg_integer(true) -> 1;
boolean_to_non_neg_integer(false) -> 0.


% helper function
gen_bool_field(Code, X) -> boolean_to_varint(Code, X).


non_neg_integer_to_fixed32(Code, X) when X >= 0 ->
    integer_to_signed_fixed32(Code, X).

integer_to_signed_fixed32(Code, X) ->
    [encode_field_tag(Code, ?TYPE_32BIT), <<X:32/little-integer>>].


non_neg_integer_to_fixed64(Code, X) when X >= 0 ->
    integer_to_signed_fixed64(Code, X).

integer_to_signed_fixed64(Code, X) ->
    [encode_field_tag(Code, ?TYPE_64BIT), <<X:64/little-integer>>].


float_to_fixed64(Code, X) ->
    F = to_float(X),
    [encode_field_tag(Code, ?TYPE_64BIT), <<F:64/little-float>>].


float_to_fixed32(Code, X) ->
    F = to_float(X),
    [encode_field_tag(Code, ?TYPE_32BIT), <<F:32/little-float>>].


to_float(X) when is_float(X) -> X;
to_float(X) when is_integer(X) -> X + 0.0.


binary_to_block(Code, X) when is_binary(X) ->
    [
        encode_field_tag(Code, ?TYPE_STRING),
        encode_varint_value(size(X)),
        X
    ].


string_to_block(Code, X) when is_list(X); is_binary(X) ->
    Utf8_bytes =
        case unicode:characters_to_binary(X) of
            Res when is_binary(Res) -> Res;
            Error -> throw_error({'error_encoding_utf8_string', Error})
        end,
    binary_to_block(Code, Utf8_bytes).


%
% Generating packed fields (packed encoding is used only for primitive numeric
% types)
%

-spec non_neg_integer_to_packed_varint/1 :: (non_neg_integer()) -> binary().
-spec integer_to_packed_signed_varint/1 :: (integer()) -> binary().
-spec integer_to_packed_zigzag_varint/1 :: (integer()) -> binary().
-spec boolean_to_packed_varint/1 :: (boolean()) -> binary().

-spec non_neg_integer_to_packed_fixed32/1 :: (non_neg_integer()) -> binary().
-spec integer_to_packed_signed_fixed32/1 :: (integer()) -> binary().
-spec non_neg_integer_to_packed_fixed64/1 :: (non_neg_integer()) -> binary().
-spec integer_to_packed_signed_fixed64/1 :: (non_neg_integer()) -> binary().
-spec float_to_packed_fixed64/1 :: (number() ) -> binary().
-spec float_to_packed_fixed32/1 :: (number() ) -> binary().


non_neg_integer_to_packed_varint(X) when X >= 0 ->
    encode_varint_value(X).

integer_to_packed_signed_varint(X) ->
    encode_varint_value(integer_to_non_neg_integer(X)).

integer_to_packed_zigzag_varint(X) ->
    encode_varint_value(integer_to_zigzag_integer(X)).

boolean_to_packed_varint(X) ->
    encode_varint_value(boolean_to_non_neg_integer(X)).


non_neg_integer_to_packed_fixed32(X) when X >= 0 ->
    integer_to_packed_signed_fixed32(X).

integer_to_packed_signed_fixed32(X) ->
    <<X:32/little-integer>>.


non_neg_integer_to_packed_fixed64(X) when X >= 0 ->
    integer_to_packed_signed_fixed64(X).

integer_to_packed_signed_fixed64(X) ->
    <<X:64/little-integer>>.


float_to_packed_fixed64(X) ->
    F = to_float(X),
    <<F:64/little-float>>.


float_to_packed_fixed32(X) ->
    F = to_float(X),
    <<F:32/little-float>>.


%
% Decoders and parsers
%

-type parsed_field() ::
    {FieldCode :: pos_integer(), FieldValue :: piqirun_return_buffer()}.

-spec parse_field_header/1 :: ( Bytes :: binary() ) ->
    {Code :: pos_integer(), WireType :: field_type(), Rest :: binary()}.

parse_field_header(Bytes) ->
    {Tag, Rest} = decode_varint(Bytes),
    Code = Tag bsr 3,
    WireType = Tag band 7,
    {Code, WireType, Rest}.


-spec parse_field/1 :: (
    Bytes :: binary() ) -> {parsed_field(), Rest :: binary()}.

parse_field(Bytes) ->
    {FieldCode, WireType, Content} = parse_field_header(Bytes),
    {FieldValue, Rest} =
        case WireType of
            ?TYPE_VARINT -> decode_varint(Content);
            ?TYPE_STRING ->
                {Length, R1} = decode_varint(Content),
                {Value, R2} = my_split_binary(R1, Length),
                {{'block', Value}, R2};
            ?TYPE_64BIT ->
                {Value, R1} = my_split_binary(Content, 8),
                {{'fixed64', Value}, R1};
            ?TYPE_32BIT ->
                {Value, R1} = my_split_binary(Content, 4),
                {{'fixed32', Value}, R1}
        end,
    {{FieldCode, FieldValue}, Rest}.


my_split_binary(X, Pos) when byte_size(X) >= Pos ->
    split_binary(X, Pos);
my_split_binary(_X, _Pos) ->
    throw_error('not_enough_data').


-spec parse_field_part/1 :: (
    Bytes :: binary() ) -> 'undefined' | {parsed_field(), Rest :: binary()}.

% Similar to parse_field/1, but if there's not enough data, 'undefined' is
% returned as the result.
parse_field_part(Bytes) ->
    try
        parse_field(Bytes)
    catch
        % raised in either parse_field_header/1 or in parse_field/1 meaning that
        % there's not enough data
        {'piqirun_error', 'not_enough_data'} -> 'undefined'
    end.


-spec parse_record/1 :: (
    piqirun_buffer() ) -> [ parsed_field() ].

-spec parse_record_buf/1 :: (
    Bytes :: binary() ) -> [ parsed_field() ].

-spec parse_variant/1 :: (
    piqirun_buffer() ) -> parsed_field().

-spec parse_list/2 :: (
    ParseValue :: decode_fun(),
    piqirun_buffer() ) -> [ any() ].

-spec parse_packed_list/3 :: (
    ParsePackedValue :: packed_decode_fun(),
    ParseValue :: decode_fun(),
    piqirun_buffer() ) -> [ any() ].


parse_record({'block', Bytes}) ->
    parse_record_buf(Bytes);
parse_record(TopBlock) when is_binary(TopBlock) ->
    parse_record_buf(TopBlock).


parse_record_buf(Bytes) ->
    parse_record_buf_ordered(Bytes, []).

parse_record_buf_ordered(<<>>, Accu) ->
    lists:reverse(Accu);
parse_record_buf_ordered(Bytes, Accu) ->
    {Field, Rest} = parse_field(Bytes),
    {Code, _Value} = Field,
    % check if the fields appear in order
    case Accu of
        [{PrevCode, _}|_] when PrevCode > Code ->
            % the field is out of order
            parse_record_buf_unordered(Rest, [Field | Accu]);
        _ ->
            parse_record_buf_ordered(Rest, [Field | Accu])
    end.

parse_record_buf_unordered(<<>>, Accu) ->
    Res = lists:reverse(Accu),
    % stable-sort the obtained fields by codes
    lists:keysort(1, Res);
parse_record_buf_unordered(Bytes, Accu) ->
    {Field, Rest} = parse_field(Bytes),
    parse_record_buf_unordered(Rest, [Field | Accu]).


parse_variant(X) ->
    [Res] = parse_record(X),
    Res.


parse_list(ParseValue, X) ->
    Fields = parse_record(X),
    [ parse_list_elem(ParseValue, F) || F <- Fields ].


% NOTE: expecting "1" as list element's code
parse_list_elem(ParseValue, {1, X}) ->
    ParseValue(X).


parse_packed_list(ParsePackedValue, ParseValue, X) ->
    Fields = parse_record(X),
    L = [ parse_packed_list_elem(ParsePackedValue, ParseValue, F) || F <- Fields ],
    lists:append(L).


% NOTE: expecting "1" as list element's code
parse_packed_list_elem(ParsePackedValue, ParseValue, {1, X}) ->
    parse_packed_field(ParsePackedValue, ParseValue, X).


-spec find_fields/2 :: (
        Code :: pos_integer(),
        L :: [ parsed_field() ] ) ->
    { Found ::[ piqirun_return_buffer() ], Rest :: [ parsed_field() ]}.

% find all fields with the given code in the list of fields sorted by codes
find_fields(Code, L) ->
    find_fields(Code, L, _Accu = []).


find_fields(Code, [{Code, Value} | T], Accu) ->
    find_fields(Code, T, [Value | Accu]);
find_fields(Code, [{NextCode, _} | T], Accu) when NextCode < Code ->
    % skipping the field which code is less than the requested one
    find_fields(Code, T, Accu);
find_fields(_Code, Rest, Accu) ->
    {lists:reverse(Accu), Rest}.


-spec find_field/2 :: (
        Code :: pos_integer(),
        L :: [ parsed_field() ] ) ->
    { Found :: 'undefined' | piqirun_return_buffer(), Rest :: [ parsed_field() ]}.

% find the last instance of a field given its code in the list of fields sorted
% by codes
find_field(Code, [{Code, Value} | T]) ->
    % check if this is the last instance of it, if not, continue iterating
    % through the list
    try_find_next_field(Code, Value, T);
find_field(Code, [{NextCode, _Value} | T]) when NextCode < Code ->
    % skipping the field which code is less than the requested one
    find_field(Code, T);
find_field(_Code, Rest) -> % not found
    {'undefined', Rest}.


try_find_next_field(Code, _PrevValue, [{Code, Value} | T]) ->
    % field is found again
    try_find_next_field(Code, Value, T);
try_find_next_field(_Code, PrevValue, Rest) ->
    % previous field was the last one
    {PrevValue, Rest}.


-spec throw_error/1 :: (any()) -> no_return().

throw_error(X) ->
    throw({'piqirun_error', X}).


-type decode_fun() :: fun( (piqirun_buffer()) -> any() ).

-type packed_decode_fun() :: fun( (binary()) -> {any(), binary()} ).

-spec parse_required_field/3 :: (
    Code :: pos_integer(),
    ParseValue :: decode_fun(),
    L :: [parsed_field()] ) -> { Res :: any(), Rest :: [parsed_field()] }.

-spec parse_optional_field/3 :: (
    Code :: pos_integer(),
    ParseValue :: decode_fun(),
    L :: [parsed_field()] ) -> { Res :: 'undefined' | any(), Rest :: [parsed_field()] }.

-spec parse_optional_field/4 :: (
    Code :: pos_integer(),
    ParseValue :: decode_fun(),
    L :: [parsed_field()],
    Default :: binary() ) -> { Res :: any(), Rest :: [parsed_field()] }.

-spec parse_repeated_field/3 :: (
    Code :: pos_integer(),
    ParseValue :: decode_fun(),
    L :: [parsed_field()] ) -> { Res :: [any()], Rest :: [parsed_field()] }.

-spec parse_packed_repeated_field/4 :: (
    Code :: pos_integer(),
    ParsePackedValue :: packed_decode_fun(),
    ParseValue :: decode_fun(),
    L :: [parsed_field()] ) -> { Res :: [any()], Rest :: [parsed_field()] }.

-spec parse_flag/2 :: (
    Code :: pos_integer(),
    L :: [parsed_field()] ) -> { Res :: boolean(), Rest :: [parsed_field()] }.


parse_required_field(Code, ParseValue, L) ->
    case parse_optional_field(Code, ParseValue, L) of
        {'undefined', _Rest} -> throw_error({'missing_field', Code});
        X -> X
    end.


parse_optional_field(Code, ParseValue, L, Default) ->
    case parse_optional_field(Code, ParseValue, L) of
        {'undefined', Rest} ->
            Res = ParseValue(Default),
            {Res, Rest};
        X -> X
    end.


parse_optional_field(Code, ParseValue, L) ->
    {Field, Rest} = find_field(Code, L),
    Res = 
        case Field of
            'undefined' -> 'undefined';
            X ->
                % NOTE: handling field duplicates without failure
                % XXX, TODO: produce a warning
                ParseValue(X)
        end,
    {Res, Rest}.


parse_flag(Code, L) ->
    % flags are represeted as booleans
    case parse_optional_field(Code, fun parse_bool/1, L) of
        {'undefined', Rest} -> {false, Rest};
        X = {true, _Rest} -> X;
        {false, _} -> throw_error({'invalid_flag_encoding', Code})
    end.


parse_repeated_field(Code, ParseValue, L) ->
    {Fields, Rest} = find_fields(Code, L),
    Res = [ ParseValue(X) || X <- Fields ],
    {Res, Rest}.


parse_packed_repeated_field(Code, ParsePackedValue, ParseValue, L) ->
    {Fields, Rest} = find_fields(Code, L),
    Res = [ parse_packed_field(ParsePackedValue, ParseValue, X) || X <- Fields ],
    {lists:append(Res), Rest}.


parse_packed_field(ParsePackedValue, _ParseValue, {'block', Bytes}) ->
    parse_packed_values(ParsePackedValue, Bytes, _Accu = []);
% sometimes packed repeated feilds come in as unpacked; we need to support this
% mode -- Google's Protobuf implementation behaves this way
parse_packed_field(_ParsePackedValue, ParseValue, X) ->
    [ParseValue(X)].


parse_packed_values(_ParseValue, <<>>, Accu) ->
    lists:reverse(Accu);
parse_packed_values(ParseValue, Bytes, Accu) ->
    {X, Rest} = ParseValue(Bytes),
    parse_packed_values(ParseValue, Rest, [X|Accu]).


% XXX, TODO: print warnings on unrecognized fields
check_unparsed_fields(_L) -> ok.


-spec error_enum_const/1 :: (X :: any()) -> no_return().

error_enum_const(X) -> throw_error({'unknown_enum_const', X}).


-spec error_option/2 :: (
    _X :: any(),
    Code :: piqirun_code()) -> no_return().

error_option(_X, Code) -> throw_error({'unknown_option', Code}).


-spec non_neg_integer_of_varint/1 :: (piqirun_buffer()) -> non_neg_integer().
-spec integer_of_signed_varint/1 :: (piqirun_buffer()) -> integer().
-spec integer_of_zigzag_varint/1 :: (piqirun_buffer()) -> integer().
-spec boolean_of_varint/1 :: (piqirun_buffer()) -> boolean().
-spec parse_bool/1 :: (piqirun_buffer()) -> boolean().

-spec non_neg_integer_of_fixed32/1 :: (piqirun_buffer()) -> non_neg_integer().
-spec integer_of_signed_fixed32/1 :: (piqirun_buffer()) -> integer().
-spec non_neg_integer_of_fixed64/1 :: (piqirun_buffer()) -> non_neg_integer().
-spec integer_of_signed_fixed64/1 :: (piqirun_buffer()) -> integer().
-spec float_of_fixed64/1 :: (piqirun_buffer()) -> float().
-spec float_of_fixed32/1 :: (piqirun_buffer()) -> float().
-spec binary_of_block/1 :: (piqirun_buffer()) -> binary().
-spec binary_string_of_block/1 :: (piqirun_buffer()) -> binary().
-spec list_string_of_block/1 :: (piqirun_buffer()) -> string().


parse_toplevel_header(Bytes) ->
    {{FieldCode, FieldValue}, _Rest} = parse_field(Bytes),
    case FieldCode of
        1 -> FieldValue;
        _ -> throw_error('invalid_toplevel_header')
    end.


-define(top_block_parser(Name),
    Name(TopBlock) when is_binary(TopBlock) ->
        Name(parse_toplevel_header(TopBlock))).


non_neg_integer_of_varint(X) when is_integer(X) -> X; ?top_block_parser(
non_neg_integer_of_varint).


integer_of_signed_varint(X)
        when is_integer(X) andalso (X band 16#8000000000000000 =/= 0) ->
    X - 16#10000000000000000;
integer_of_signed_varint(X) when is_integer(X) -> X; ?top_block_parser(
integer_of_signed_varint).


integer_of_zigzag_varint(X) when is_integer(X) ->
    (X bsr 1) bxor (-(X band 1)); ?top_block_parser(
integer_of_zigzag_varint).


boolean_of_varint(1) -> true;
boolean_of_varint(0) -> false; ?top_block_parser(
boolean_of_varint).


parse_bool(X) -> boolean_of_varint(X).


non_neg_integer_of_fixed32({'fixed32', <<X:32/little-unsigned-integer>>}) -> X; ?top_block_parser(
non_neg_integer_of_fixed32).

integer_of_signed_fixed32({'fixed32', <<X:32/little-signed-integer>>}) -> X; ?top_block_parser(
integer_of_signed_fixed32).


non_neg_integer_of_fixed64({'fixed64', <<X:64/little-unsigned-integer>>}) -> X; ?top_block_parser(
non_neg_integer_of_fixed64).

integer_of_signed_fixed64({'fixed64', <<X:64/little-signed-integer>>}) -> X; ?top_block_parser(
integer_of_signed_fixed64).


float_of_fixed64({'fixed64', <<X:64/little-float>>}) -> X;
float_of_fixed64({'fixed64', X}) -> parse_ieee754_64(X); ?top_block_parser(
float_of_fixed64).

float_of_fixed32({'fixed32', <<X:32/little-float>>}) -> X;
float_of_fixed32({'fixed32', X}) -> parse_ieee754_32(X); ?top_block_parser(
float_of_fixed32).


binary_of_block({'block', X}) -> X; ?top_block_parser(
binary_of_block).


% NOTE: this function is left for backward compatibility and will be removed in
% future versions
-spec string_of_block/1 :: (piqirun_buffer()) -> binary().
string_of_block(X) -> binary_of_block(X).


% utf8 string represented as Erlang binary
binary_string_of_block(X) ->
    % NOTE, XXX: not validating utf8 on input
    binary_of_block(X).


% list containing utf8 string
list_string_of_block(X) ->
    Bin = binary_of_block(X),
    case unicode:characters_to_list(Bin) of
        Res when is_list(Res) -> Res;
        Error -> throw_error({'error_decoding_utf8_string', Error})
    end.


%
% Parsing packed fields (packed encoding is used only for primitive numeric
% types)
%

-spec non_neg_integer_of_packed_varint/1 :: (binary()) ->
    {non_neg_integer(), Rest :: binary()}.
-spec integer_of_packed_signed_varint/1 :: (binary()) ->
    {integer(), Rest :: binary()}.
-spec integer_of_packed_zigzag_varint/1 :: ( binary()) ->
    {integer(), Rest :: binary()}.
-spec boolean_of_packed_varint/1 :: (binary()) ->
    {boolean(), Rest :: binary()}.

-spec non_neg_integer_of_packed_fixed32/1 :: (binary()) ->
    {non_neg_integer(), Rest :: binary()}.
-spec integer_of_packed_signed_fixed32/1 :: (binary()) ->
    {integer(), Rest :: binary()}.
-spec non_neg_integer_of_packed_fixed64/1 :: (binary()) ->
    {non_neg_integer(), Rest :: binary()}.
-spec integer_of_packed_signed_fixed64/1 :: (binary()) ->
    {integer(), Rest :: binary()}.
-spec float_of_packed_fixed64/1 :: (binary()) ->
    {float(), Rest :: binary()}.
-spec float_of_packed_fixed32/1 :: (binary()) ->
    {float(), Rest :: binary()}.


non_neg_integer_of_packed_varint(Bin) ->
    decode_varint(Bin).

integer_of_packed_signed_varint(Bin) ->
    {X, Rest} = decode_varint(Bin),
    {integer_of_signed_varint(X), Rest}.

integer_of_packed_zigzag_varint(Bin) ->
    {X, Rest} = decode_varint(Bin),
    {integer_of_zigzag_varint(X), Rest}.

boolean_of_packed_varint(Bin) ->
    {X, Rest} = decode_varint(Bin),
    {boolean_of_varint(X), Rest}.


non_neg_integer_of_packed_fixed32(<<X:32/little-unsigned-integer, Rest/binary>>) ->
    {X, Rest};
non_neg_integer_of_packed_fixed32(_) -> throw_error('not_enough_data').


integer_of_packed_signed_fixed32(<<X:32/little-signed-integer, Rest/binary>>) ->
    {X, Rest};
integer_of_packed_signed_fixed32(_) -> throw_error('not_enough_data').


non_neg_integer_of_packed_fixed64(<<X:64/little-unsigned-integer, Rest/binary>>) ->
    {X, Rest};
non_neg_integer_of_packed_fixed64(_) -> throw_error('not_enough_data').


integer_of_packed_signed_fixed64(<<X:64/little-signed-integer, Rest/binary>>) ->
    {X, Rest};
integer_of_packed_signed_fixed64(_) -> throw_error('not_enough_data').


float_of_packed_fixed64(<<X:64/little-float, Rest/binary>>) ->
    {X, Rest};
float_of_packed_fixed64(<<X:8/binary, Rest/binary>>) ->
    {parse_ieee754_64(X), Rest};
float_of_packed_fixed64(_) ->
    throw_error('not_enough_data').


float_of_packed_fixed32(<<X:32/little-float, Rest/binary>>) ->
    {X, Rest};
float_of_packed_fixed32(<<X:4/binary, Rest/binary>>) ->
    {parse_ieee754_32(X), Rest};
float_of_packed_fixed32(_) ->
    throw_error('not_enough_data').


% parse special IEEE 754 values: infinities and NaN
%
% TODO: first, need to modify types and extend returned and accepted floating
% point type to be:
%
%       -type piqi_float() :: float() | '-infinity' | 'infinity' | 'nan'.
%
-spec parse_ieee754_64/1 :: (<<_:64>>) -> no_return().
-spec parse_ieee754_32/1 :: (<<_:32>>) -> no_return().

parse_ieee754_64(_) -> throw_error('ieee754_infinities_NaN_not_supported_yet').
parse_ieee754_32(_) -> throw_error('ieee754_infinities_NaN_not_supported_yet').

