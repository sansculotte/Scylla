module Scylla.Api exposing (..)
import Http exposing (Header, header)
import Json.Encode as Encode

type alias ApiToken = String
type alias ApiUrl = String

basicHeaders : List Header
basicHeaders =
    [ header "Content-Type" "application/json"
    ]

authenticatedHeaders : ApiToken -> List Header
authenticatedHeaders token =
    [ header "Authorization" ("Bearer " ++ token)] ++ basicHeaders
