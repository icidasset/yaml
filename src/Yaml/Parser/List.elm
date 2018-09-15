module Yaml.Parser.List exposing (toplevel, inline)


import Parser as P exposing ((|=), (|.))
import Yaml.Parser.Util as U
import Yaml.Parser.Ast as Ast


type alias Config =
  { inline : List Char -> P.Parser Ast.Value
  , toplevel : P.Parser Ast.Value
  }



-- TOP LEVEL


{-| -}
toplevel : Config -> Int -> P.Parser Ast.Value
toplevel config indent =
  let
    withValue value =
      P.succeed Ast.List_
        |= P.loop [ value ] (toplevelEach config indent)
  in
  toplevelNewEntry config
    |> P.andThen withValue


toplevelEach : Config -> Int -> List Ast.Value -> P.Parser (P.Step (List Ast.Value) (List Ast.Value))
toplevelEach config indent values =
  let finish = P.Done (List.reverse values)
      next value = P.Loop (value :: values)
      continued = P.Loop
  in
  U.checkIndent indent
    { smaller = P.succeed finish
    , exactly = P.oneOf [ P.map next (toplevelNewEntry config), P.succeed finish ]
    , larger  = P.map continued << toplevelContinuedEntry config values
    , ending = P.succeed finish
    }


toplevelNewEntry : Config -> P.Parser Ast.Value
toplevelNewEntry config =
  P.succeed identity
    |. U.dash
    |= P.oneOf 
        [ P.succeed Ast.Null_
            |. U.newLine
        , P.succeed identity
            |. U.space
            |. U.spaces
            |= config.toplevel
        ]


toplevelContinuedEntry : Config -> List Ast.Value -> Int -> P.Parser (List Ast.Value)
toplevelContinuedEntry config values subIndent =
  let
    coalesce value =
      case ( values, value ) of
        ( Ast.Null_ :: rest, _ ) -> 
          P.succeed (value :: rest)

        ( Ast.String_ prev :: rest, Ast.String_ new ) -> 
          P.succeed (Ast.String_ (prev ++ " " ++ new) :: rest)

        ( _ :: rest, Ast.String_ _ ) -> -- TODO don't skip new lines
          P.problem "I was parsing a record, but I got more strings when expected a new property!"

        ( _, _ ) -> 
          P.succeed (value :: values)
  in
  P.andThen coalesce config.toplevel



-- INLINE


inline : Config -> P.Parser Ast.Value
inline config =
  P.succeed Ast.List_
    |. P.symbol "["
    |. U.spaces
    |= P.oneOf
        [ P.succeed []
            |. P.symbol "}"
        , P.loop [] (inlineEach config)
        ]


inlineEach : Config -> List Ast.Value -> P.Parser (P.Step (List Ast.Value) (List Ast.Value))
inlineEach config values =
  P.succeed (\v next -> next (v :: values))
    |= config.inline [',', ']']
    |. U.spaces
    |= P.oneOf
        [ P.succeed P.Loop |. P.symbol "," 
        , P.succeed (P.Done << List.reverse) |. P.symbol "]"
        ]
    |. U.spaces


