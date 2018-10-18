#
# FOURJS_START_COPYRIGHT(U,2015)
# Property of Four Js*
# (c) Copyright Four Js 2015, 2018. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
#
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#

#
# Module implementing the OpenIDConnect protocol
#
IMPORT COM
IMPORT Util
IMPORT FGL Logs
IMPORT FGL IdPManager
IMPORT FGL Access
IMPORT FGL JWT
IMPORT FGL HTTPHelper
IMPORT FGL Utils

PUBLIC TYPE OpenIdCResponse RECORD
  access_token  STRING,
  token_type    STRING,
  expires_in    INTEGER,
  refresh_token STRING,
  id_token      STRING
END RECORD

PRIVATE CONSTANT C_IAT_ALLOWED  = INTERVAL(120) SECOND(3) TO SECOND  # IAT validity delta for time shifting
PRIVATE CONSTANT C_PROFILE_TIMEOUT = 3  # 3s before to break if userinfo doesn't respond

PRIVATE CONSTANT C_HTTPGetBody = "<html><head><title>Genero OIDC Redirection</title></head>\
                                  <body onload=\"document.getElementById('form').submit();\">\
                                  This page will automatically redirect you to your identity provider.\
                                  If you are not immediately redirected, click the submit button below.\
                                  <form id=\"form\" action=\"$(URL)\" method=\"get\">
                                  <input type=\"hidden\" name=\"client_id\"  value=\"$(CLIENT_ID)\" />\
                                  <input type=\"hidden\" name=\"response_type\"  value=\"code\" />\
                                  <input type=\"hidden\" name=\"scope\"  value=\"$(SCOPE)\" />\
                                  <input type=\"hidden\" name=\"redirect_uri\"  value=\"$(REDIRECT_URI)\" />\
                                  <input type=\"hidden\" name=\"state\"  value=\"$(STATE)\" />\
                                  <input type=\"submit\" value=\"submit\" />\
                                  </form></body></html>"

PRIVATE CONSTANT C_HTTPPostBody = "<html><head><title>Genero OIDC Redirection</title></head>\
                                  <body onload=\"document.getElementById('form').submit();\">\
                                  This page will automatically redirect you to your identity provider.\
                                  If you are not immediately redirected, click the submit button below.\
                                  <form id=\"form\" action=\"$(URL)\" method=\"post\">
                                  <input type=\"hidden\" name=\"client_id\"  value=\"$(CLIENT_ID)\" />\
                                  <input type=\"hidden\" name=\"response_type\"  value=\"code\" />\
                                  <input type=\"hidden\" name=\"scope\"  value=\"$(SCOPE)\" />\
                                  <input type=\"hidden\" name=\"redirect_uri\"  value=\"$(REDIRECT_URI)\" />\
                                  <input type=\"hidden\" name=\"state\"  value=\"$(STATE)\" />\
                                  <input type=\"submit\" value=\"submit\" />\
                                  </form></body></html>"

#
# Send OpenIdC request for authentication
#  by redirecting the browser
#  based on OAuth Client ID and shared secret
#  NOTE : handle Authorization Code Flow
#
FUNCTION SendAuthenticationRequest(req,idp,redirect,client_pub_id,is_oauth2,scope,uuid,do_prompt)
  DEFINE  req             com.HttpServiceRequest
  DEFINE  idp             IdPManager.IdPType
  DEFINE  redirect        STRING
  DEFINE  client_pub_id   STRING
  DEFINE  is_oauth2       BOOLEAN
  DEFINE  scope           STRING
  DEFINE  uuid            STRING
  DEFINE  do_prompt       BOOLEAN
  DEFINE  query           STRING
  DEFINE  body            STRING

  CASE base.Application.getResourceEntry("oidc.authenticate.redirect")
    WHEN "GET"
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"OIDConnect","SendAuthenticationRequest via html GET form",NULL)
      LET body = Utils.ReplaceString(C_HTTPGetBody,"URL",idp.authorization_endpoint)
      LET body = Utils.ReplaceString(body,"CLIENT_ID",client_pub_id)
      IF is_oauth2 THEN
        LET body = Utils.ReplaceString(body,"SCOPE",scope)
      ELSE
        IF scope IS NOT NULL THEN
          LET body = Utils.ReplaceString(body,"SCOPE","openid "||scope)
        ELSE
          LET body = Utils.ReplaceString(body,"SCOPE","openid")
        END IF
      END IF
      LET body = Utils.ReplaceString(body,"REDIRECT_URI",redirect)
      LET body = Utils.ReplaceString(body,"STATE",uuid)

      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)

      # Set no cache headers
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_PRAGMA,HTTPHelper.C_HTTP_NO_CACHE)
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_CACHE_CONTROL,HTTPHelper.C_HTTP_NO_CACHE||", "||HTTPHelper.C_HTTP_NO_STORE)

      # Send response
      CALL req.sendTextResponse(200,NULL,body)

    WHEN "POST"
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"OIDConnect","SendAuthenticationRequest via html POST form",NULL)
      LET body = Utils.ReplaceString(C_HTTPPostBody,"URL",idp.authorization_endpoint)
      LET body = Utils.ReplaceString(body,"CLIENT_ID",client_pub_id)
      IF is_oauth2 THEN
        LET body = Utils.ReplaceString(body,"SCOPE",scope)
      ELSE
        IF scope IS NOT NULL THEN
          LET body = Utils.ReplaceString(body,"SCOPE","openid "||scope)
        ELSE
          LET body = Utils.ReplaceString(body,"SCOPE","openid")
        END IF
      END IF
      LET body = Utils.ReplaceString(body,"REDIRECT_URI",redirect)
      LET body = Utils.ReplaceString(body,"STATE",uuid)

      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)

      # Set no cache headers
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_PRAGMA,HTTPHelper.C_HTTP_NO_CACHE)
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_CACHE_CONTROL,HTTPHelper.C_HTTP_NO_CACHE||", "||HTTPHelper.C_HTTP_NO_STORE)

      # Send response
      CALL req.sendTextResponse(200,NULL,body)


    WHEN "302"
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"OIDConnect","SendAuthenticationRequest via redirect",NULL)
      IF is_oauth2 THEN
        # OAuth2
        IF scope IS NULL THEN
          LET query = "?client_id="||Util.Strings.UrlEncode(client_pub_id)||"&response_type=code&redirect_uri="||Util.Strings.UrlEncode(redirect)||"&state="||uuid
        ELSE
          LET query = "?client_id="||Util.Strings.UrlEncode(client_pub_id)||"&response_type=code&scope="||Util.Strings.UrlEncode(scope)||"&redirect_uri="||Util.Strings.UrlEncode(redirect)||"&state="||uuid
        END IF
      ELSE
        IF scope IS NULL THEN
          # openid scope is mandatory
          LET query = "?client_id="||Util.Strings.UrlEncode(client_pub_id)||"&response_type=code&scope=openid&redirect_uri="||Util.Strings.UrlEncode(redirect)||"&state="||uuid
        ELSE
          LET query = "?client_id="||Util.Strings.UrlEncode(client_pub_id)||"&response_type=code&scope=openid%20"||Util.Strings.UrlEncode(scope)||"&redirect_uri="||Util.Strings.UrlEncode(redirect)||"&state="||uuid
        END IF
      END IF
      IF do_prompt THEN
        LET query = query || "&prompt=login"
      END IF
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_PRAGMA,HTTPHelper.C_HTTP_NO_CACHE)
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_CACHE_CONTROL,HTTPHelper.C_HTTP_NO_CACHE||", "||HTTPHelper.C_HTTP_NO_STORE)
      CALL req.setResponseHeader("X-Frame-Options","ALLOW-FROM "||idp.authorization_endpoint)
      CALL req.setResponseHeader("Location",idp.authorization_endpoint||query)
      CALL req.sendResponse(302,NULL)

  END CASE

END FUNCTION

#
# Send OAuth2 code to IdP
#  to get an access token
#
FUNCTION ClientSendCode(idp, redirect, code, client_pub_id, client_secret_id)
  DEFINE  idp                 IdPManager.IdPType
  DEFINE  redirect            STRING
  DEFINE  code                STRING
  DEFINE  client_pub_id       STRING
  DEFINE  client_secret_id    STRING
  DEFINE  query               STRING
  DEFINE  req                 com.HttpRequest
  DEFINE  resp                com.HttpResponse
  DEFINE  ret                 util.JSONObject
  DEFINE  str                 STRING
  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"OIDConnect","ClientSendCode",NULL)
  TRY
    LET query = "grant_type=authorization_code&code="||code||"&redirect_uri="||redirect||"&client_id="||client_pub_id
    IF client_secret_id IS NOT NULL THEN
      # NOTICE : client_secret should not be sent according to OAuth2, but google wants it otherwise it fails
      LET query = query || "&client_secret="||client_secret_id
    END IF
    LET req = com.HttpRequest.Create(idp.token_endpoint)
    CALL req.setMethod("POST")
    CALL req.doFormEncodedRequest(query,TRUE)
    LET resp = req.getResponse()
    IF resp.getStatusCode() == 200 THEN
      LET str = resp.getTextResponse()
      LET ret = util.JSONObject.parse(str)
      RETURN TRUE, ret
    ELSE
      LET str = resp.getTextResponse()
      IF str IS NULL THEN
        LET str = resp.getStatusDescription()
      END IF
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","ClientSendCode","HTTPCode("||resp.getStatusCode()||") : "||str)
    END IF
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","ClientSendCode","Connection error code "||STATUS)
  END TRY
  RETURN FALSE,NULL
END FUNCTION

#
# Send openIDConnect code to IdP
#  to get a Bearer token
#
FUNCTION ClientSendCodeForBearerToken(idp,redirect,code,client_pub_id,client_secret_id)
  DEFINE  idp                 IdPManager.IdPType
  DEFINE  redirect            STRING
  DEFINE  code                STRING
  DEFINE  client_pub_id       STRING
  DEFINE  client_secret_id    STRING
  DEFINE  query               STRING
  DEFINE  req                 com.HttpRequest
  DEFINE  resp                com.HttpResponse
  DEFINE  ret                 OpenIdCResponse
  DEFINE  str                 STRING
  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"OIDConnect","ClientSendCodeForBearerToken",NULL)
  TRY
    LET query = "grant_type=authorization_code&code="||code||"&redirect_uri="||redirect||"&client_id="||client_pub_id
    IF client_secret_id IS NOT NULL THEN
      # NOTICE : client_secret should not be sent according to OAuth2, but google wants it otherwise it fails
      LET query = query || "&client_secret="||client_secret_id
    END IF
    LET req = com.HttpRequest.Create(idp.token_endpoint)
    CALL req.setMethod("POST")
    CALL req.doFormEncodedRequest(query,TRUE)
    LET resp = req.getResponse()
    IF resp.getStatusCode() == 200 THEN
      LET str = resp.getTextResponse()
      CALL util.json.parse(str,ret)
      IF ret.token_type IS NOT NULL THEN
        IF ret.token_type.equalsIgnoreCase("Bearer") THEN
          RETURN TRUE,ret.*
        END IF
      END IF
    ELSE
      LET str = resp.getTextResponse()
      IF str IS NULL THEN
        LET str = resp.getStatusDescription()
      END IF
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","ClientSendCodeForBearerToken","HTTPCode("||resp.getStatusCode()||") : "||str)
    END IF
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","ClientSendCodeForBearerToken","Connection error code "||STATUS)
  END TRY
  INITIALIZE ret TO NULL
  RETURN FALSE,ret.*
END FUNCTION

FUNCTION CheckTokenValidity(pub_id,idp,token)
  DEFINE pub_id   STRING
  DEFINE idp      IdPManager.IdPType
  DEFINE token    OpenIDCResponse
  DEFINE id_token JWT.JWTType
  DEFINE now      DATETIME YEAR TO SECOND
  DEFINE dt       DATETIME YEAR TO SECOND
  # Decode and validate id Token
  CALL JWT.DecodeAndValidateCompactJWT(idp.*,token.id_token) RETURNING id_token.*
  IF id_token.claims.iss IS NULL THEN
    RETURN FALSE, NULL, NULL # Token is invalid
  ELSE
    LET now = CURRENT
    # Ensure issuer is identical (REQUIRED)
    IF id_token.claims.iss != idp.Issuer THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","CheckTokenValidity","claimed issuer does not match")
      RETURN FALSE, NULL, NULL
    END IF
    # Ensure audience is CLIENT_PUBLIC_ID (REQUIRED)
    IF NOT pub_id.equals(id_token.claims.aud) THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","CheckTokenValidity","claimed audience does not match")
      RETURN FALSE, NULL, NULL
    END IF
    # Ensure Subject is present (REQUIRED)
    IF id_token.claims.sub IS NULL THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","CheckTokenValidity","claimed subject is missing")
      RETURN FALSE, NULL, NULL
    END IF
    # Ensure exp < now (REQUIRED)
    LET dt = util.Datetime.fromSecondsSinceEpoch(id_token.claims.exp)
    IF now > dt THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","CheckTokenValidity","Token has expired")
      RETURN FALSE, NULL, NULL
    END IF
    # Ensure now >= iat (REQUIRED)
    LET dt = util.Datetime.fromSecondsSinceEpoch(id_token.claims.iat)
    IF AbsoluteInterval(now-dt) > C_IAT_ALLOWED THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","CheckTokenValidity","Token generation too old")
      RETURN FALSE, NULL, NULL
    END IF
    # Check access token (if any) and if at_hash present
    IF token.access_token IS NOT NULL AND id_token.claims.at_hash IS NOT NULL THEN
      IF NOT JWT.ValidateAtHash(id_token.*,token.access_token) THEN
        CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","CheckTokenValidity","Access token is invalid")
        RETURN FALSE, NULL, NULL
      END IF
    END IF
  END IF
  IF id_token.claims.scopes IS NOT NULL THEN
    # Return scope names
    RETURN TRUE, id_token.claims.sub, id_token.claims.scopes.getKeys()
  ELSE
    RETURN TRUE, id_token.claims.sub, NULL
  END IF
END FUNCTION

#+
#+ Retrieve user info data
#+  and returns whether the service is available
#+  and a dynamic array of user info (or NULL)
#+
FUNCTION RetrieveUserInfo(idp,token)
  DEFINE  idp           IdPManager.IdPType
  DEFINE  token         OpenIdCResponse
  DEFINE  req           com.HttpRequest
  DEFINE  resp          com.HttpResponse
  DEFINE  attrs         Access.AttributeType
  DEFINE  ret           STRING
  DEFINE  url           STRING
  IF idp.userinfo_endpoint IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"OIDConnect","RetrieveUserInfo",idp.issuer||" has no userinfo end point")
    RETURN FALSE, NULL
  ELSE
    TRY
      LET url = idp.userinfo_endpoint
      IF url.getCharAt(url.getLength())=="?" THEN
        # Determine where to put access_token (query)
        LET req = com.HttpRequest.Create(SFMT("%1access_token=%2",idp.userinfo_endpoint,token.access_token))
      ELSE
        LET req = com.HttpRequest.Create(idp.userinfo_endpoint)
        CALL req.setHeader("Authorization","Bearer "||token.access_token)
      END IF
      CALL req.setConnectionTimeOut(C_PROFILE_TIMEOUT)
      CALL req.doRequest()
      LET resp = req.getResponse()
      IF resp.getStatusCode() == 200 THEN
        LET ret = resp.getTextResponse()
        CALL UserInfoToAttributes(ret) RETURNING  attrs
        RETURN TRUE, attrs
      ELSE
        IF resp.getStatusCode() == 403 THEN
          LET ret = resp.getTextResponse()
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","RetrieveUserInfo","Forbidden : "||ret)
        ELSE
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","RetrieveUserInfo","ERROR : "||resp.getStatusDescription())
        END IF
        RETURN TRUE, NULL
      END IF
    CATCH
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","RetrieveUserInfo","ERROR : "||STATUS)
      RETURN FALSE, NULL
    END TRY
  END IF

END FUNCTION

#
# Converts a json object to an array of attributes
#
PRIVATE
FUNCTION UserInfoToAttributes(src)
  DEFINE  src     STRING
  DEFINE  attrs   Access.AttributeType
  DEFINE  json    util.JSONObject
  TRY
    LET json = util.JSONObject.parse(src)
    CALL JsonObjectToAttributes(json, attrs)
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","UserInfoToAttributes","ERROR : "||STATUS)
  END TRY
  RETURN attrs
END FUNCTION

#
# Converts a json object to an array of attributes
#
PUBLIC
FUNCTION JsonObjectToAttributes(json, attrs)
  DEFINE  attrs   Access.AttributeType
  DEFINE  json    util.JSONObject
  DEFINE  ind     INTEGER
  DEFINE n,v      STRING
  TRY
    FOR ind = 1 TO json.getLength()
      LET n = json.name(ind)
      CASE json.getType(n)
        WHEN "OBJECT"
          CALL JsonObjectToAttributes(json.get(n), attrs)

        WHEN "STRING"
          LET v = json.get(n)
          IF v IS NOT NULL THEN
            IF v.getLength()>0 THEN
              CALL attrs.appendElement()
              LET attrs[attrs.getLength()].NAME = n
              LET attrs[attrs.getLength()].VALUE = v
            END IF
          END IF

        WHEN "NUMBER"
          LET v = json.get(n)
          IF v IS NOT NULL THEN
            IF v.getLength()>0 THEN
              CALL attrs.appendElement()
              LET attrs[attrs.getLength()].NAME = n
              LET attrs[attrs.getLength()].VALUE = v
            END IF
          END IF

      END CASE
    END FOR
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"OIDConnect","JsonObjectToAttributes","ERROR : "||STATUS)
  END TRY
END FUNCTION

PRIVATE
FUNCTION AbsoluteInterval(d)
   DEFINE d INTERVAL SECOND TO SECOND

   IF d<INTERVAL(0) SECOND TO SECOND THEN
       RETURN -d
   ELSE
       RETURN d
   END IF
END FUNCTION
