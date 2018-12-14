import Browser exposing (application, UrlRequest(..))
import Browser.Navigation as Nav
import Scylla.Sync exposing (..)
import Scylla.Login exposing (..)
import Scylla.Model exposing (..)
import Scylla.Http exposing (..)
import Scylla.Views exposing (viewFull)
import Scylla.Route exposing (Route(..))
import Scylla.UserData exposing (..)
import Scylla.Notification exposing (..)
import Url exposing (Url)
import Url.Parser exposing (parse)
import Url.Builder
import Html exposing (div, text)
import Http
import Dict

type alias Flags =
    { token : Maybe String
    }

init : Flags -> Url -> Nav.Key -> (Model, Cmd Msg)
init flags url key =
    let
        model =
            { key = key
            , route = Maybe.withDefault Unknown <| parse Scylla.Route.route url
            , token = flags.token
            , loginUsername = ""
            , loginPassword = ""
            , apiUrl = "https://matrix.org"
            , sync =
                { nextBatch = ""
                , rooms = Nothing
                , presence = Nothing
                , accountData = Nothing
                }
            , errors = []
            , roomText = Dict.empty
            , transactionId = 0
            , userData = Dict.empty
            }
        cmd = case flags.token of
            Just _ -> Cmd.none
            Nothing -> Nav.pushUrl key <| Url.Builder.absolute [ "login" ] []
    in
        (model, cmd)

view : Model -> Browser.Document Msg
view m =
    { title = "Scylla"
    , body = viewFull m
    }

update : Msg -> Model -> (Model, Cmd Msg)
update msg model = case msg of
    ChangeApiUrl u -> ({ model | apiUrl = u }, Cmd.none)
    ChangeLoginUsername u -> ({ model | loginUsername = u }, Cmd.none)
    ChangeLoginPassword p -> ({ model | loginPassword = p }, Cmd.none)
    AttemptLogin -> (model, Scylla.Http.login model.apiUrl model.loginUsername model.loginPassword) -- TODO 
    TryUrl urlRequest -> updateTryUrl model urlRequest
    OpenRoom s -> (model, Nav.pushUrl model.key <| roomUrl s)
    ChangeRoute r -> ({ model | route = r }, Cmd.none)
    ReceiveLoginResponse r -> updateLoginResponse model r
    ReceiveFirstSyncResponse r -> updateSyncResponse model r False
    ReceiveSyncResponse r -> updateSyncResponse model r True
    ReceiveUserData s r -> updateUserData model s r
    ChangeRoomText r t -> ({ model | roomText = Dict.insert r t model.roomText}, Cmd.none)
    SendRoomText r -> updateSendRoomText model r
    SendRoomTextResponse r -> (model, Cmd.none)

updateUserData : Model -> String -> Result Http.Error UserData -> (Model, Cmd Msg)
updateUserData m s r = case r of
    Ok ud -> ({ m | userData = Dict.insert s ud m.userData }, Cmd.none)
    Err e -> (m, userData m.apiUrl (Maybe.withDefault "" m.token) s)

updateSendRoomText : Model -> String -> (Model, Cmd Msg)
updateSendRoomText m r =
    let
        token = Maybe.withDefault "" m.token
        message = Maybe.andThen (\s -> if s == "" then Nothing else Just s)
            <| Dict.get r m.roomText
        command = Maybe.withDefault Cmd.none
            <| Maybe.map (sendTextMessage m.apiUrl token m.transactionId r) message
    in
        ({ m | roomText = Dict.insert r "" m.roomText, transactionId = m.transactionId + 1 }, command)

updateTryUrl : Model -> Browser.UrlRequest -> (Model, Cmd Msg)
updateTryUrl m ur = case ur of
    Internal u -> (m, Nav.pushUrl m.key (Url.toString u))
    _ -> (m, Cmd.none)

updateLoginResponse : Model -> Result Http.Error LoginResponse -> (Model, Cmd Msg)
updateLoginResponse model r = case r of
    Ok lr -> ( { model | token = Just lr.accessToken, loginUsername = lr.userId } , Cmd.batch
        [ firstSync model.apiUrl lr.accessToken
        , Nav.pushUrl model.key <| Url.Builder.absolute [] []
        ] )
    Err e  -> (model, Cmd.none)

updateSyncResponse : Model -> Result Http.Error SyncResponse -> Bool -> (Model, Cmd Msg)
updateSyncResponse model r notify =
    let
        token = Maybe.withDefault "" model.token
        nextBatch = Result.withDefault model.sync.nextBatch
            <| Result.map .nextBatch r
        syncCmd = sync nextBatch model.apiUrl token
        newUsers sr = List.filter (\s -> not <| Dict.member s model.userData) <| roomsUsers sr
        newUserCommands sr = Cmd.batch
            <| List.map (userData model.apiUrl
            <| Maybe.withDefault "" model.token)
            <| newUsers sr
        notification sr = findFirstBy
            (\(s, e) -> e.originServerTs)
            (\(s, e) -> e.sender /= model.loginUsername)
            <| notificationEvents sr
        notificationCommand sr = Maybe.withDefault Cmd.none
            <| Maybe.map (\(s, e) -> sendNotificationPort
                { name = displayName model e.sender
                , text = notificationText e
                , room = s
                })
            <| notification sr
    in
        case r of
            Ok sr -> ({ model | sync = mergeSyncResponse model.sync sr }, Cmd.batch
                [ syncCmd
                , newUserCommands sr
                , if notify then notificationCommand sr else Cmd.none
                ])
            _ -> (model, syncCmd)

subscriptions : Model -> Sub Msg
subscriptions m = onNotificationClickPort OpenRoom

onUrlRequest : Browser.UrlRequest -> Msg
onUrlRequest = TryUrl

onUrlChange : Url -> Msg
onUrlChange = ChangeRoute << Maybe.withDefault Unknown << parse Scylla.Route.route

main = application
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    , onUrlRequest = onUrlRequest
    , onUrlChange = onUrlChange
    }
