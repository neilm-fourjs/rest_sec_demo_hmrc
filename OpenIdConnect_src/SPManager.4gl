#
# FOURJS_START_COPYRIGHT(U,2015)
# Property of Four Js*
# (c) Copyright Four Js 2015, 2022. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#
IMPORT com
IMPORT xml
IMPORT util
IMPORT FGL Utils
IMPORT FGL Logs
IMPORT FGL Access
IMPORT FGL HTTPHelper
IMPORT FGL IdPManager
IMPORT FGL OIDConnect
IMPORT FGL RelayState
IMPORT FGL Session
IMPORT FGL WSHelper

PRIVATE CONSTANT C_XCF_AUTHORIZATION      = "AUTHORIZATION"
PRIVATE CONSTANT C_XCF_OAUTH              = "OAUTH"
PRIVATE CONSTANT C_XCF_IDP                = "IDP"
PRIVATE CONSTANT C_XCF_CLIENT_PUBLIC_ID   = "CLIENT_PUBLIC_ID"
PRIVATE CONSTANT C_XCF_CLIENT_SECRET_ID   = "CLIENT_SECRET_ID"
PRIVATE CONSTANT C_XCF_SCOPE              = "SCOPE"
PRIVATE CONSTANT C_XCF_SIGN_OFF           = "SIGN_OFF"
PRIVATE CONSTANT C_XCF_END_URL            = "END_URL"
PRIVATE CONSTANT C_XCF_IDP_LOGOUT_URL     = "IDP_LOGOUT_URL"
PRIVATE CONSTANT C_PROMPT_QUERY           = "PROMPT_QUERY"

PRIVATE CONSTANT C_LOCALHOST_URI        = "localhost"
PRIVATE CONSTANT C_LOCALHOST_IDP        = "/ws/r/services/GeneroIdentityProvider"

PRIVATE CONSTANT C_HTTPGetBody = "<html><head><title>Genero OIDC Redirection</title></head>\
                                  <body onload=\"document.getElementById('form').submit();\">\
                                  This page will automatically redirect you to your identity provider.\
                                  If you are not immediately redirected, click the submit button below.\
                                  <form id=\"form\" action=\"$(URL)\" method=\"get\">
                                  <input type=\"submit\" value=\"submit\" />\
                                  </form></body></html>"

PRIVATE CONSTANT C_HTTPPostBody = "<html><head><title>Genero OIDC Redirection</title></head>\
                                  <body onload=\"document.getElementById('form').submit();\">\
                                  This page will automatically redirect you to your identity provider.\
                                  If you are not immediately redirected, click the submit button below.\
                                  <form id=\"form\" action=\"$(URL)\" method=\"post\">
                                  <input type=\"submit\" value=\"submit\" />\
                                  </form></body></html>"

#
# Process OpenIDConnect authentication from callback request
#
PUBLIC
FUNCTION ProcessAuthenticationCallback(req, baseurl, query)
  DEFINE  req         com.HttpServiceRequest
  DEFINE  baseurl     STRING
  DEFINE  state       STRING
  DEFINE  code        STRING
  DEFINE  ind         INTEGER
  DEFINE  query       WSHelper.WSQueryType
  DEFINE  idp         IdPManager.IdPType
  DEFINE  sess_uuid   VARCHAR(36)
  DEFINE  sess        Session.SessionType
  DEFINE  app_url     STRING

  # Read response from IdP
  IF query.getLength()==0 THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthenticationResponse","No query string")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    RETURN
  END IF

  FOR ind = 1 TO query.getLength()
    CASE query[ind].name
      WHEN "error"
        CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthenticationResponse",query[ind].value)
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
        RETURN
      WHEN "code"
        LET code = query[ind].value
      WHEN "state"
        LET state = query[ind].value
    END CASE
  END FOR

  # Ensure code and state are present
  IF code IS NULL OR state IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthenticationResponse","code or state is missing")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
  END IF

  # Ensure state has been encountered previously
  CALL RelayState.CheckRelayState(state) RETURNING app_url, sess_uuid
  IF sess_uuid IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthenticationResponse","state error")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    RETURN
  END IF

  CALL Session.RetrieveByUUID(sess_uuid) RETURNING sess.*
  IF sess.provider_id IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthenticationResponse","authentication param error")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    FREE sess.id_token # BLOB must be released
    RETURN
  END IF

  # Retrieve IDP metadata
  CALL IdPManager.GetIdP(sess.provider_id) RETURNING idp.*
  IF idp.Issuer IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthenticationResponse","Issuer is missing")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    FREE sess.id_token # BLOB must be released
    RETURN
  END IF

  # Send OpenIdC code for a Bearer token
  IF NOT idp.is_oauth2 THEN
    CALL ProcessOpenIDCallback(req, baseURL, idp.*, sess.*, app_url, code)
  ELSE
    CALL ProcessOAuth2Callback(req, baseURL, idp.*, sess.*, app_url, code)
  END IF

  FREE sess.id_token # BLOB must be released

END FUNCTION

#+
#+ Process OAuth2 token callback protocol
#+
PRIVATE
FUNCTION ProcessOAuth2Callback(req, baseURL, idp, sess, app_url, code)
  DEFINE  req         com.HTTPServiceRequest
  DEFINE  baseURL     STRING
  DEFINE  idp         IdPManager.IdPType
  DEFINE  sess        Session.SessionType
  DEFINE  code        STRING
  DEFINE  token       OIDConnect.OpenIdCResponse
  DEFINE  ok          BOOLEAN
  DEFINE  subject     STRING
  DEFINE  scopes      DYNAMIC ARRAY OF STRING
  DEFINE  app_url     STRING
  DEFINE  attrs       Access.AttributeType
  DEFINE  ind         INTEGER
  DEFINE  json,child  util.JSONObject
  DEFINE  n           STRING
  DEFINE  identifier  STRING
  DEFINE  token_type  STRING

  CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","ProcessOAuth2Callback",app_url)

  # Retrieve mandatory subject identifier
  LET identifier = base.Application.getResourceEntry("oidc.oauth.subject.identifier")
  IF identifier.equalsIgnoreCase("<none>") THEN
    # Skip subject
    LET identifier = NULL
  END IF

  # OAuth2
  CASE base.Application.getResourceEntry("oidc.oauth.request.format")
    WHEN "url-encoded"
        CALL OIDConnect.ClientSendCode(idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,code,sess.pub_id,sess.secret_id) RETURNING ok,json
    WHEN "json"
        CALL OIDConnect.ClientSendCodeJson(idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,code,sess.pub_id,sess.secret_id) RETURNING ok,json
    OTHERWISE
        CALL OIDConnect.ClientSendCode(idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,code,sess.pub_id,sess.secret_id) RETURNING ok,json
  END CASE
  IF NOT ok THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    RETURN
  END IF

  # Try to decode json token
  FOR ind = 1 TO json.getLength()
    LET n = json.name(ind)
    CASE n
      WHEN "token_type"
        LET token_type = json.get(n)
      WHEN "access_token"
        LET token.access_token = json.get(n)
      WHEN "expires_in"
        LET token.expires_in = json.get(n)
      WHEN "refresh_token"
        LET token.refresh_token = json.get(n)
      WHEN "id_token"
        LET token.id_token = json.get(n)
      OTHERWISE
        IF identifier IS NOT NULL THEN
          IF json.getType(n)=="OBJECT" THEN
            LET child = json.get(n)
            IF child.has(identifier) AND idp.userinfo_endpoint IS NULL THEN
              # Decode json token as attributes and to get user id from token
              CALL OIDConnect.JsonObjectToAttributes(child, attrs)
            END IF
          END  IF
        END IF
    END CASE
  END FOR

  IF idp.jwks_uri IS NOT NULL THEN
    # NOTE : do not need to check access_token expiration (token.expire)
    #         as it is used immediatly
    CALL OIDConnect.CheckTokenValidity(sess.pub_id,idp.*,token.*) RETURNING ok, subject, scopes
    IF NOT ok THEN
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_TOKEN,baseURL))
      RETURN
    END IF
  ELSE
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","ProcessOAuth2Callback","Warning no key to verify token signature")
  END IF

  # Ensure there is an access_token (otherwise fail)
  IF token.access_token IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","ProcessOAuth2Callback","No access_token found")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    RETURN
  END IF

  # Retrieve user info profile (if any)
  IF idp.userinfo_endpoint IS NOT NULL THEN
    CALL OIDConnect.RetrieveUserInfo(idp.*,token.*) RETURNING ok, attrs
    IF ok THEN
      # User info is available set OIDC_USERINFO_ENDPOINT
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "USERINFO_ENDPOINT"
      LET attrs[attrs.getLength()].value = idp.userinfo_endpoint
    END IF

  END IF

  # Handle user identifier
  IF identifier IS NULL THEN
    # skip identifier step
    LET subject = "<none>"
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","ProcessOAuth2Callback","Skip subject")
  ELSE
    # Retrieve user subject
    LET ind = attrs.search("name",identifier)
    IF ind>0 THEN
      LET subject = attrs[ind].value
    END IF
  END IF

  IF subject IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","ProcessOAuth2Callback","No id found")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    RETURN
  END IF

  IF app_url.getIndexOf(HTTPHelper.C_RESUME_URL,1)>1 THEN
    # Resume URL
    CALL GrantResume(req, baseurl, sess.*, subject, app_url)
  ELSE

    # Set OIDC_TOKEN_ENDPOINT
    IF idp.token_endpoint IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "IDP_TOKEN_ENDPOINT"
      LET attrs[attrs.getLength()].VALUE = idp.token_endpoint
    END IF

    # Set OIDC_ISSUER
    IF idp.Issuer IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "IDP_ISSUER"
      LET attrs[attrs.getLength()].VALUE = idp.Issuer
    END IF

    # GrantAccess
    CALL GrantAccess(req, baseURL, sess.*, subject, scopes,  attrs, token.*)
  END IF

END FUNCTION


#+
#+ Process OpenID connect callback protocol
#+
PRIVATE
FUNCTION ProcessOpenIDCallback(req, baseURL, idp, sess, app_url, code)
  DEFINE  req         com.HTTPServiceRequest
  DEFINE  baseURL     STRING
  DEFINE  token       OIDConnect.OpenIdCResponse
  DEFINE  idp         IdPManager.IdPType
  DEFINE  sess        Session.SessionType
  DEFINE  code        STRING
  DEFINE  ok          BOOLEAN
  DEFINE  subject     STRING
  DEFINE  scopes      DYNAMIC ARRAY OF STRING
  DEFINE  app_url     STRING
  DEFINE  attrs       Access.AttributeType

  CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","ProcessOpenIDCallback",app_url)

  # OpenID-Connect standard
  CALL OIDConnect.ClientSendCodeForBearerToken(idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,code,sess.pub_id,sess.secret_id) RETURNING ok,token.*
  IF NOT ok THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_PROTOCOL,baseurl))
    RETURN
  END IF

  # NOTE : do not need to check access_token expiration (token.expire)
  #         as it is used immediatly
  CALL OIDConnect.CheckTokenValidity(sess.pub_id,idp.*,token.*) RETURNING ok, subject, scopes
  IF NOT OK THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_TOKEN,baseurl))
    RETURN
  END IF


  IF app_url.getIndexOf(HTTPHelper.C_RESUME_URL,1)>1 THEN
    # Resume URL
    CALL GrantResume(req, baseurl, sess.*, subject, app_url)
  ELSE

    # OIDC: Retrieve user info if access token
    IF token.access_token IS NOT NULL THEN
      # retrieve USERINFO (may fail if user has not allowed user info API in Google console)
      CALL OIDConnect.RetrieveUserInfo(idp.*,token.*) RETURNING ok, attrs
      IF ok THEN
        # User info is available set OIDC_USERINFO_ENDPOINT
        CALL attrs.appendElement()
        LET attrs[attrs.getLength()].NAME = "USERINFO_ENDPOINT"
        LET attrs[attrs.getLength()].value = idp.userinfo_endpoint
      END IF
    END IF

    # Set OIDC_TOKEN_ENDPOINT
    IF idp.token_endpoint IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "IDP_TOKEN_ENDPOINT"
      LET attrs[attrs.getLength()].VALUE = idp.token_endpoint
    END IF

    # Set OIDC_ISSUER
    IF idp.Issuer IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "IDP_ISSUER"
      LET attrs[attrs.getLength()].VALUE = idp.Issuer
    END IF

    # GrantAccess
    CALL GrantAccess(req, baseURL, sess.*, subject, scopes,  attrs, token.*)
  END IF

END FUNCTION

PUBLIC
FUNCTION GrantResume(req, baseurl, session, sub, resume_url)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseurl     STRING
  DEFINE  session     Session.SessionType
  DEFINE  resume_url  STRING
  DEFINE  sub         STRING
  DEFINE  uuid        STRING
  DEFINE  path        STRING
  DEFINE  domain      STRING
  DEFINE  scheme      STRING
  DEFINE  port        STRING
  DEFINE  query       STRING
  DEFINE  ua_session  STRING
  DEFINE  ind         INTEGER
  DEFINE  redirectURL STRING
  DEFINE  cookies     WSHelper.WSServerCookiesType

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantResume",resume_url)
  CALL WSHelper.SplitURL(Util.Strings.urlDecode(resume_url)) RETURNING scheme,domain,port,path,query

  # Retrieve ua session from resume url
  LET ind = path.getIndexOf(HTTPHelper.C_RESUME_URL,1)
  IF ind<1 THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","GrantResume","Cannot extract session from "||path)
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
    RETURN
  ELSE
    LET ua_session = path.subString(ind+HTTPHelper.C_RESUME_URL.getLength(),path.getLength())
  END IF

  IF session.subject != sub THEN
    # compare sub with auth_id subject
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
    RETURN
  END IF

  CALL req.setResponseHeader(HTTPHelper.C_HTTP_PRAGMA,HTTPHelper.C_HTTP_NO_CACHE)
  CALL req.setResponseHeader(HTTPHelper.C_HTTP_CACHE_CONTROL,HTTPHelper.C_HTTP_NO_CACHE||", "||HTTPHelper.C_HTTP_NO_STORE)

  # Set Access cookie and HTTP redirection
  LET uuid = Access.CreateToken(resume_url,NULL,req.getRequestHeader(HTTPHelper.C_X_FOURJS_REMOTE_ADDR))

  CASE base.Application.getResourceEntry("oidc.app.start.mode")
    WHEN "cookie"
      LET cookies[1].name = HTTPHelper.C_COOKIE_OIDC
      LET cookies[1].value = uuid
      LET cookies[1].path = path
      LET cookies[1].domain = domain
      LET cookies[1].httpOnly = TRUE
      LET cookies[1].sameSite = HTTPHelper.C_COOKIE_LAX
      CALL req.setResponseCookies(cookies)
    WHEN "gnonce"
      # Append gnonce to redirect url
      IF query IS NULL THEN
        LET query = "gnonce=",uuid
      ELSE
        LET query = query,"&gnonce=",uuid
      END IF
    OTHERWISE
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","GrantAccess",SFMT("ACCESS DENIED : unknown 'oidc.app.start.mode' value : '%1'",base.Application.getResourceEntry("oidc.app.start.mode")))
      RETURN
  END CASE

  # Build Redirect URL (without query as it depends on redirect method)
  IF port IS NOT NULL THEN
    LET redirectURL = SFMT("%1://%2:%3%4",scheme,domain,port,path)
  ELSE
    LET redirectURL = SFMT("%1://%2%3",scheme,domain,path)
  END IF

  IF query IS NOT NULL THEN
    CALL req.setResponseHeader(HTTPHelper.C_HTTP_LOCATION,redirectURL||"?"||query)
  ELSE
    CALL req.setResponseHeader(HTTPHelper.C_HTTP_LOCATION,redirectURL)
  END IF
  CALL req.sendResponse(302,NULL)
  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantResume","ACCESS GRANTED")

END FUNCTION

PUBLIC
FUNCTION GrantAccess(req, baseURL, sess, sub, scopes, attrs, token)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  sess      Session.SessionType
  DEFINE  token     OIDConnect.OpenIdCResponse
  DEFINE  sub       STRING
  DEFINE  scopes    DYNAMIC ARRAY OF STRING
  DEFINE  attrs     Access.AttributeType
  DEFINE  uuid      STRING
  DEFINE  path      STRING
  DEFINE  domain    STRING
  DEFINE  port      STRING
  DEFINE  scheme    STRING
  DEFINE  query     STRING
  DEFINE  str       STRING
  DEFINE  ind       INTEGER
  DEFINE  redirectURL STRING

  DEFINE  cookies   WSHelper.WSServerCookiesType

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess",sess.url)
  CALL WSHelper.SplitURL(Util.Strings.urlDecode(sess.url)) RETURNING scheme,domain,port,path,query

  IF domain.equalsIgnoreCase("localhost") THEN
    # We need to setup http cookies thus requires a valid domain name
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_LOCALHOST_UNALLOWED,baseurl))
    RETURN
  END IF

  # Check AccessProgram
  IF CheckAuthorizationProgram(sess.authz, sub, path, attrs) THEN

    # Set subject
    IF NOT Session.DoValidate(sess.uuid, sub, token.id_token) THEN
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_INTERNAL_ERROR,baseurl))
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess","ACCESS DENIED ,INTERNAL ERROR")
    END IF

    # (if any) Build DELEGATE END_URL intended to uaproxy
    IF sess.sign_off IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = HTTPHelper.C_X_FOURJS_FGL_VMPROXY_END_URL
      LET attrs[attrs.getLength()].VALUE = SFMT("%1%2%3?gid=%4",baseURL, HTTPHelper.C_OIDC_PATH, HTTPHelper.C_LOGOUT, sess.uuid)
    END IF

    # Provide UAProxy the prompt ID (legacy)
    CALL attrs.appendElement()
    LET attrs[attrs.getLength()].NAME = C_PROMPT_QUERY
    LET attrs[attrs.getLength()].VALUE = sess.uuid

    # Provide START_URL (without gnonce=xxx)
    IF base.Application.getResourceEntry("oidc.app.start.mode")=="gnonce" THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].name = HTTPHelper.C_X_FOURJS_FGL_VMPROXY_START_URL
      LET attrs[attrs.getLength()].value = util.Strings.urlDecode(sess.url)
    END IF

    # Append Subject ID to attributes
    LET ind = attrs.search("name","SUB")
    IF ind==0 THEN
      LET ind = attrs.search("name","sub")
    END IF
    IF ind==0 THEN
      # Not sub defined, add from ID token
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "SUB"
      LET attrs[attrs.getLength()].VALUE = sub
    ELSE
      # Ensure they have same value
      IF attrs[ind].value!= sub THEN
        CALL Session.DoInvalidate(sess.uuid)
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
        CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess","ACCESS DENIED : different SUB values")
        RETURN
      END IF
    END IF
    # Append list of authorization scopes separated by comma to attributes
    IF scopes.getLength() >0 THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "SCOPES"
      LET attrs[attrs.getLength()].VALUE = scopes[1]
      FOR ind = 2 TO scopes.getLength()
        LET attrs[attrs.getLength()].VALUE = attrs[attrs.getLength()].VALUE ||","||scopes[ind]
      END FOR
    END IF

    # Append access token (if any)
    IF token.access_token IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "ACCESS_TOKEN"
      LET attrs[attrs.getLength()].VALUE = token.access_token
    END IF

    # Append refresh token (if any)
    IF token.refresh_token IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "REFRESH_TOKEN"
      LET attrs[attrs.getLength()].VALUE = token.refresh_token
    END IF

    IF token.expires_in IS NOT NULL THEN
      CALL attrs.appendElement()
      LET attrs[attrs.getLength()].NAME = "TOKEN_EXPIRES_IN"
      LET attrs[attrs.getLength()].VALUE = token.expires_in
    END IF

    CALL req.setResponseHeader(HTTPHelper.C_HTTP_PRAGMA,HTTPHelper.C_HTTP_NO_CACHE)
    CALL req.setResponseHeader(HTTPHelper.C_HTTP_CACHE_CONTROL,HTTPHelper.C_HTTP_NO_CACHE||", "||HTTPHelper.C_HTTP_NO_STORE)

    # Set Access cookie and HTTP redirection
    LET uuid = Access.CreateToken(sess.url, attrs, req.getRequestHeader(HTTPHelper.C_X_FOURJS_REMOTE_ADDR))
    CASE base.Application.getResourceEntry("oidc.app.start.mode")
      WHEN "cookie"
        LET cookies[1].name = HTTPHelper.C_COOKIE_OIDC
        LET cookies[1].value = uuid
        LET cookies[1].path = path
        LET cookies[1].domain = domain
        LET cookies[1].httpOnly = TRUE
        LET cookies[1].sameSite = HTTPHelper.C_COOKIE_LAX
        CALL req.setResponseCookies(cookies)
      WHEN "gnonce"
        # Append gnonce to redirect url
        IF query IS NULL THEN
          LET query = "gnonce=",uuid
        ELSE
          LET query = query,"&gnonce=",uuid
        END IF
      OTHERWISE
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseURL))
        CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","GrantAccess",SFMT("ACCESS DENIED : unknown 'oidc.app.start.mode' value : '%1'",base.Application.getResourceEntry("oidc.app.start.mode")))
        RETURN
    END CASE

    # Build Redirect URL (without query as it depends on redirect method)
    IF port IS NOT NULL THEN
      LET redirectURL = SFMT("%1://%2:%3%4",scheme,domain,port,path)
    ELSE
      LET redirectURL = SFMT("%1://%2%3",scheme,domain,path)
    END IF

    CASE base.Application.getResourceEntry("oidc.app.start.redirect")
    WHEN "GET"
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        LET str = Utils.BuildHTMLSubmit(C_HTTPGetBody,redirectURL,query)
        IF str IS NOT NULL THEN
          CALL req.sendTextResponse(200,NULL,str)
          CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess","ACCESS GRANTED")
        ELSE
          CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseURL))
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","GrantAccess","ACCESS DENIED : unable to build HTMLGet formular")
          RETURN
        END IF
    WHEN "POST"
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        IF  base.Application.getResourceEntry("oidc.app.start.mode")=="gnonce" THEN
          # Only set gnonce as POST in order to not appear in browser
          LET str = Utils.BuildHTMLSubmit(C_HTTPPostBody,sess.url,"gnonce="||uuid)
        ELSE
          LET str = Utils.BuildHTMLSubmit(C_HTTPPostBody,sess.url,NULL)
        END IF
        IF str IS NOT NULL THEN
          CALL req.sendTextResponse(200,NULL,str)
          CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess","ACCESS GRANTED")
        ELSE
          CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseURL))
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","GrantAccess","ACCESS DENIED : unable to build HTMLPost formular")
          RETURN
        END IF
    WHEN "302"
        IF query IS NOT NULL THEN
          CALL req.setResponseHeader(HTTPHelper.C_HTTP_LOCATION,redirectURL||"?"||query)
        ELSE
          CALL req.setResponseHeader(HTTPHelper.C_HTTP_LOCATION,redirectURL)
        END IF
        CALL req.sendResponse(302,NULL)
        CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess","ACCESS GRANTED")
    OTHERWISE
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseURL))
        CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","GrantAccess","ACCESS DENIED : unknown 'oidc.app.start.redirect' value")
        RETURN
    END CASE
  ELSE
    CALL Session.DoInvalidate(sess.uuid)
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","GrantAccess","ACCESS DENIED")
  END IF
END FUNCTION

PUBLIC
FUNCTION StartProxy(req, url, attrs)
  DEFINE  req   com.HttpServiceRequest
  DEFINE  url   STRING
  DEFINE  attrs Access.AttributeType
  DEFINE  ind   INTEGER

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","StartProxy",url)

  # Set attributes
  FOR ind = 1 TO attrs.getLength()
    CASE attrs[ind].NAME
      WHEN C_PROMPT_QUERY
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","Prompt query UUID",attrs[ind].VALUE)
        CALL req.setResponseHeader(HTTPHelper.C_X_FOURJS_FGL_AUTO_LOGOUT_PROMPT_QUERY,attrs[ind].VALUE)

      WHEN HTTPHelper.C_X_FOURJS_FGL_VMPROXY_END_URL
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","Delegate PROXY END URL",attrs[ind].VALUE)
        CALL req.setResponseHeader(HTTPHelper.C_X_FOURJS_FGL_VMPROXY_END_URL,attrs[ind].VALUE)

      WHEN HTTPHelper.C_X_FOURJS_FGL_VMPROXY_START_URL
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","Delegate PROXY START URL",attrs[ind].value)
        CALL req.setResponseHeader(HTTPHelper.C_X_FOURJS_FGL_VMPROXY_START_URL,attrs[ind].value)

      OTHERWISE
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","Attribute Name",attrs[ind].name)
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","Attribute Value",attrs[ind].VALUE)
        IF attrs[ind].NAME IS NOT NULL AND attrs[ind].VALUE IS NOT NULL THEN
          CALL req.setResponseHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_||"OIDC_"||attrs[ind].name,attrs[ind].VALUE)
        END IF

    END CASE
  END FOR
  # Start proxy
  CALL req.sendResponse(307,C_GENERO_INTERNAL_DELEGATE)

END FUNCTION

PRIVATE
FUNCTION CreateOAuth2SessionFromParameters(req, baseURL, idp, url, pub_id, sec_id, scope, authz_prg)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  idp       IdPManager.IdPType
  DEFINE  url       STRING
  DEFINE  pub_id    STRING
  DEFINE  sec_id    STRING
  DEFINE  scope     STRING
  DEFINE  authz_prg STRING
  DEFINE  end_url   STRING
  DEFINE  sessID    Session.SessionType
  DEFINE  sign_off  STRING

  # Retrieve end_url from xcf (if any)
  LET end_url = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_EXTRA||C_XCF_END_URL)
  IF end_url IS NULL AND base.Application.getResourceEntry("oidc.logout.default.end_url") IS NOT NULL THEN
    LET end_url = SFMT("%1%2", baseURL, base.Application.getResourceEntry("oidc.logout.default.end_url"))
  END IF

  LET sign_off = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_SIGN_OFF)
  IF sign_off IS NULL AND idp.end_session_endpoint IS NULL THEN
    # No logout at all
    CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, NULL, NULL, NULL) RETURNING sessID.*
  ELSE
    IF idp.end_session_endpoint IS NULL THEN
      # No logout possible return error page
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CreateOAuth2StartSession","Error : SIGN_OFF cannot be set if there is no end_session end point set")
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    ELSE
      IF sign_off IS NULL THEN
        LET sign_off = "QUERY" # Default OAuth2 logout parameter
      END IF
      CASE sign_off
        WHEN "FALSE" # No logout requested
         CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, NULL, NULL, NULL) RETURNING sessID.*

        WHEN "TRUE" # Logout requested
          CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, "TRUE", end_url, idp.end_session_endpoint) RETURNING sessID.*

        WHEN "QUERY" # Logout requested
          CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, "QUERY", end_url, idp.end_session_endpoint) RETURNING sessID.*

        OTHERWISE
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartAuthentication","Error : invalid SIGN_OFF value")
          CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
          CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))

      END CASE
    END IF
  END IF

  RETURN sessID.*

END FUNCTION

PRIVATE
FUNCTION CreateOpenIDSessionFromParameters(req, baseURL, idp, url, pub_id, sec_id, scope, authz_prg)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  idp       IdPManager.IdPType
  DEFINE  url       STRING
  DEFINE  pub_id    STRING
  DEFINE  sec_id    STRING
  DEFINE  scope     STRING
  DEFINE  authz_prg STRING
  DEFINE  end_url   STRING
  DEFINE  sessID    Session.SessionType
  DEFINE  sign_off  STRING
  DEFINE idp_logout_url STRING

  # Retrieve end_url from xcf (if any)
  LET end_url = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_EXTRA||C_XCF_END_URL)
  IF end_url IS NULL AND base.Application.getResourceEntry("oidc.logout.default.end_url") IS NOT NULL THEN
    LET end_url = SFMT("%1%2", baseURL, base.Application.getResourceEntry("oidc.logout.default.end_url"))
  END IF

  # Parse logout parameters
  LET sign_off = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_SIGN_OFF)
  IF sign_off IS NULL AND idp.end_session_endpoint IS NULL THEN
    # No logout at all
    CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, NULL, NULL, NULL) RETURNING sessID.*
  ELSE

    IF sign_off IS NULL THEN
      # OpenIDConnect Logout default parameters
      # IDP supports end_session => perform always logout in charge of IDP to query for logout
      CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, "TRUE", end_url, idp.end_session_endpoint) RETURNING sessID.*

    ELSE
      # Fetch requiered IDP_LOGOUT param
      LET idp_logout_url = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_IDP_LOGOUT_URL)
      IF idp_logout_url IS NOT NULL THEN
        CASE sign_off
          WHEN "FALSE" # No logout requested
           CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, NULL, NULL, NULL) RETURNING sessID.*

          WHEN "TRUE" # Logout requested
            CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, "TRUE", end_url, idp_logout_url) RETURNING sessID.*

          WHEN "QUERY" # Logout requested
            CALL Session.CreateUUID(idp.ID, url, pub_id, sec_id, scope, authz_prg, "QUERY", end_url, idp_logout_url) RETURNING sessID.*

          OTHERWISE
            CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartAuthentication","Error : invalid SIGN_OFF value")
            CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
            CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))

         END CASE
      ELSE
        CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartAuthentication","Error : IDP_LOGOUT_URL parameter requiered with SIGN_OFF")
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
      END IF
    END IF
  END IF

  RETURN sessID.*
END FUNCTION

PUBLIC
FUNCTION StartAuthentication(req, baseURL, url)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  idp       IdPManager.IdPType
  DEFINE  authz_prg STRING
  DEFINE  scope     STRING
  DEFINE  pub_id    STRING
  DEFINE  sec_id    STRING
  DEFINE  url       STRING
  DEFINE  uuid      STRING
  DEFINE  sessID    Session.SessionType
  DEFINE  genEnd    STRING
  DEFINE  oauth     STRING
  DEFINE  idp_url   STRING

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","StartAuthentication",url)
  LET oauth = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_OAUTH)
  LET idp_url = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_IDP)
  IF oauth IS NOT NULL AND idp_url IS NOT NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartAuthentication","IDP and OAuth are exclusiv")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    RETURN
  ELSE
    IF oauth IS NOT NULL THEN
      # Handle OAuth config
      CALL IdPManager.GetOAuthFromIssuer(oauth) RETURNING idp.*
    ELSE
      # Handle IDP config
      IF idp_url.equalsIgnoreCase(C_LOCALHOST_URI) THEN
        # Compute localhost IDP
        LET idp_url = baseURL || C_LOCALHOST_IDP
      END IF
      CALL IdPManager.GetIdPFromIssuer(idp_url) RETURNING idp.*
    END IF
  END IF

  IF idp.Issuer IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartAuthentication","Issuer is missing")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
  ELSE
    # Retrieve XCF configuration
    LET pub_id = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_CLIENT_PUBLIC_ID)
    LET sec_id = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_CLIENT_SECRET_ID)
    IF pub_id IS NULL THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartAuthentication","Public ID is missing")
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    ELSE
      # Retrieve optional parameters
      LET authz_prg = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_AUTHORIZATION)
      LET scope = req.getRequestHeader(HTTPHelper.C_X_FOURJS_ENVIRONEMENT_PARAMETER_||C_XCF_SCOPE)

      IF idp.is_oauth2 THEN
        CALL CreateOAuth2SessionFromParameters(req, baseurl, idp.*, url, pub_id, sec_id, scope, authz_prg) RETURNING sessID.*
      ELSE
        CALL CreateOpenIDSessionFromParameters(req, baseurl, idp.*, url, pub_id, sec_id, scope, authz_prg) RETURNING sessID.*
      END IF

      IF sessID.uuid IS NOT NULL THEN
        LET uuid = RelayState.CreateRelayState(url,sessID.uuid)
        LET genEnd = req.findRequestCookie("Genero-END")
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","StartAuthentication","Genero-END :"||genEnd)
        IF genEnd IS NULL THEN
          CALL OIDConnect.SendAuthenticationRequest(req,idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,pub_id,idp.is_oauth2,scope,uuid, FALSE)
        ELSE
          CASE genEnd
            WHEN "Closed"
              CALL OIDConnect.SendAuthenticationRequest(req,idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,pub_id,idp.is_oauth2,scope,uuid, FALSE)
            WHEN "Disconnected"
              CALL OIDConnect.SendAuthenticationRequest(req,idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,pub_id,idp.is_oauth2,scope,uuid, TRUE)
            OTHERWISE
              CALL OIDConnect.SendAuthenticationRequest(req,idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT,pub_id,idp.is_oauth2,scope,uuid, TRUE)
          END CASE
        END IF
      END IF
    END IF
  END IF
END FUNCTION


PUBLIC
FUNCTION StartReauthentication(req, baseURL, session_uuid, ua_session, timeout)
  DEFINE  req           com.HttpServiceRequest
  DEFINE  baseURL       STRING
  DEFINE  ua_session    STRING
  DEFINE  session_uuid  STRING
  DEFINE  uuid          STRING
  DEFINE  timeout       INTERVAL SECOND(9) TO SECOND
  DEFINE  idp           IdPManager.IdPType
  DEFINE  scope         STRING
  DEFINE  resumeURL     STRING
  DEFINE  sess         SessionType

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","StartReauthentication",session_uuid)

  CALL RetrieveByUUID(session_uuid) RETURNING sess.*
  IF sess.uuid IS NULL OR sess.subject IS NULL OR sess.provider_id IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartReauthentication","Prompt UUID error")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    RETURN
  END IF

  IF sess.pub_id IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartReauthentication","Public and shared secret are missing")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    RETURN
  END IF

  CALL IdPManager.GetIdP(sess.provider_id) RETURNING idp.*
  IF idp.Issuer IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartReauthentication","Issuer is missing")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    RETURN
  END IF

  # Start re authentication for resume URL (need ua session)
  IF NOT Session.SetUASession(session_uuid, ua_session) THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","StartReauthentication","Cannot associate session to prompt ID")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
  ELSE
    # Build ua/resume URL
    LET resumeURL = baseURL || HTTPHelper.C_RESUME_URL || ua_session
    # Create relay state for resume URL
    LET uuid = RelayState.CreateRelayState(resumeURL, session_uuid)
    CALL OIDConnect.SendAuthenticationRequest(req,idp.*,baseURL||HTTPHelper.C_OIDC_PATH||HTTPHelper.C_OIDC_REDIRECT, sess.pub_id, idp.is_oauth2, scope,uuid, TRUE)
  END IF

  FREE sess.id_token

END FUNCTION


PUBLIC
FUNCTION Resume(req)
  DEFINE  req   com.HttpServiceRequest
  CALL req.sendResponse(307,C_GENERO_INTERNAL_DELEGATE)
  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","Resume URL","Granted")
END FUNCTION

PUBLIC
FUNCTION Forbid(req,baseurl)
  DEFINE  req   com.HttpServiceRequest
  DEFINE  baseurl STRING
  CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
  CALL req.setResponseHeader(C_HTTP_CACHE_CONTROL, C_HTTP_NO_STORE || ", " || C_HTTP_NO_CACHE)
  CALL req.setResponseHeader(C_HTTP_PRAGMA, C_HTTP_NO_CACHE)
  CALL req.sendTextResponse(403,NULL,GetErrorPage(C_HTTP_ERROR_ACCESS_DENIED,baseurl))
END FUNCTION


PUBLIC
FUNCTION HasAccess(req, url, query)
  DEFINE  req     com.HttpServiceRequest
  DEFINE  url     STRING
  DEFINE  cookie  STRING
  DEFINE  attrs   Access.AttributeType
  DEFINE  _found  BOOLEAN
  DEFINE _valid   BOOLEAN
  DEFINE query    WSHelper.WSQueryType
  DEFINE  ind     INTEGER

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","HasAccess",url)

  CASE base.Application.getResourceEntry("oidc.app.start.mode")
    WHEN "cookie"
      LET cookie = req.findRequestCookie(HTTPHelper.C_COOKIE_OIDC)
      CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","HasAccess",cookie)
    WHEN "gnonce"
      LET ind = HTTPHelper.RetrieveQueryIndexByName(query,"gnonce")
      IF ind>0 THEN
        LET cookie = query[ind].value
        CALL query.deleteElement(ind)
      END IF
      CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","HasAccess via gnonce",cookie)
    OTHERWISE
  END CASE

  # Ignore Bootstrap=done from URL othewise Access will fail
  LET ind = HTTPHelper.RetrieveQueryIndexByName(query,"Bootstrap")
  IF ind>0 THEN
    CALL query.deleteElement(ind)
  END IF

  LET url = HTTPHelper.BuildQueryEncodedURL(url,query)

  # Check Access token
  CALL Access.ValidateToken(cookie, url, req.getRequestHeader(HTTPHelper.C_X_FOURJS_REMOTE_ADDR), req.getRequestHeader(HTTPHelper.C_X_FOURJS_BOOTSTRAP))
    RETURNING _found, _valid, attrs

  IF _valid THEN
    RETURN TRUE, TRUE, attrs
  END IF

  RETURN FALSE, _found, NULL

END FUNCTION

PUBLIC
FUNCTION ForbidAccess(req, baseurl)
  DEFINE  req     com.HttpServiceRequest
  DEFINE  baseurl STRING
  # FORBID ACCESS
  CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
  CALL req.sendTextResponse(403,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_ACCESS_FORBIDDEN,baseurl))
  CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","ForbidAccess","ACCESS FORBIDDEN")
END FUNCTION

#
# Execute given 4GL program to check authorization
#  and passes the attributes as arguments to FGLRUN in following format
#  FGLRUN prg ID path attr1 value1 attr2 value2
#
PRIVATE
FUNCTION CheckAuthorizationProgram(authz_prg,id,path,attrs)
  DEFINE  authz_prg STRING
  DEFINE  id        STRING
  DEFINE  path      STRING
  DEFINE  attrs     Access.AttributeType
  DEFINE  res       SMALLINT
  DEFINE  cmdline   STRING
  DEFINE  ind       INTEGER
  DEFINE  ret       BOOLEAN
  IF authz_prg IS NOT NULL THEN
    # Build command line from id, path and user attributes
    LET cmdline = authz_prg|| " " || id || " \"" || path || "\""
    FOR ind=1 TO attrs.getLength()
      LET cmdline = cmdline || " \"" || attrs[ind].name || "\" \"" || attrs[ind].value || "\""
    END FOR
    IF cmdline IS NOT NULL THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","CheckAuthorizationProgram",cmdline)
      # Execute access control program
      RUN cmdline IN FORM MODE RETURNING res
      IF res==0 THEN
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","CheckAuthorizationProgram","ACCESS AUTHORIZED")
        LET ret =  TRUE
      ELSE
        CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"SPManager","CheckAuthorizationProgram","ACCESS DENIED")
        LET ret =  FALSE
      END IF
    ELSE
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","CheckAuthorizationProgram","Invalid command line")
      LET ret =  FALSE
    END IF
  ELSE
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","CheckAuthorizationProgram","NO AUTHORIZATION CONTROL")
    LET ret = TRUE
  END IF
  RETURN ret
END FUNCTION

#+
#+ Starts logout dance
#+
PUBLIC
FUNCTION DoLogout(req, baseURL, uuid)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  uuid      STRING
  DEFINE  sess      SessionType
  DEFINE  idp       IdPManager.IdPType

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","DoLogout",uuid)

  CALL RetrieveByUUID(uuid) RETURNING sess.*
  IF sess.uuid IS NULL OR sess.subject IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","DoLogout","Logout UUID error")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
    RETURN
  END IF

  CALL IdPManager.GetIdP(sess.provider_id) RETURNING idp.*
  IF idp.Issuer IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","DoLogout","Issuer not found")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_LOGOUT_ERROR,baseurl))
    RETURN
  END IF


  CASE sess.sign_off

    WHEN "QUERY"
      CALL Session.DoInvalidateSoon(sess.uuid) # Invalidate in 3 minutes (time to query for logout or not)
      CALL LogoutQuery(req, baseURL, sess.*, idp.*)

    WHEN "TRUE"
      CALL StartLogout(req, sess.*, idp.*)

    OTHERWISE
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","DoLogout","Logout invalid sign_off")
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_INVALID_PARAMETER,baseurl))
  END CASE

  FREE sess.id_token

END FUNCTION

PRIVATE
FUNCTION LogoutQuery(req, baseURL, sess, idp)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  idp       IdPManager.IdPType
  DEFINE  sess      SessionType
  DEFINE  doc       xml.DomDocument
  DEFINE  root      xml.DomNode

  LET doc = xml.DomDocument.Create()
  TRY
    CALL doc.load(base.Application.getResourceEntry("oidc.form.logout.query"))
    LET root = doc.getDocumentElement()
    IF idp.Issuer IS NOT NULL THEN
      CALL Utils.ReplaceXML(root,"IDP_ISSUER",idp.Issuer)
    ELSE
      CALL Utils.ReplaceXML(root,"IDP_ISSUER","SSO")
    END IF
    CALL Utils.ReplaceXML(root,"POST_LOGOUT",SFMT("%1%2Logout", baseurl, HTTPHelper.C_OIDC_PATH))
    CALL Utils.ReplaceXML(root,"GID",sess.uuid)
    CALL Utils.ReplaceXML(root,"LOGO",SFMT("%1%2",baseurl,base.Application.getResourceEntry("oidc.form.logo.suffix")))
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.setResponseHeader(C_HTTP_CACHE_CONTROL, C_HTTP_NO_STORE||", "||C_HTTP_NO_CACHE)
    CALL req.setResponseHeader(C_HTTP_PRAGMA, C_HTTP_NO_CACHE)
    CALL req.sendTextResponse(200,NULL,doc.saveToString())
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","LogoutQuery","Cannot load logout query form")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_LOGOUT_ERROR,baseurl))
  END TRY

END FUNCTION

#+
#+ Process logout query response
#+
PUBLIC
FUNCTION DoQueryLogout(req, baseurl, uuid, logout)
  DEFINE  req         com.HttpServiceRequest
  DEFINE  baseurl     STRING
  DEFINE  uuid        STRING
  DEFINE  logout      BOOLEAN
  DEFINE  sess        SessionType
  DEFINE  idp         IdPManager.IdPType

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","DoQueryLogout",uuid)

  CALL RetrieveByUUID(uuid) RETURNING sess.*
  IF sess.uuid IS NULL OR sess.subject IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","DoQueryLogout","Logout UUID error")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_LOGOUT_ERROR,baseurl))
    RETURN
  END IF

  CALL IdPManager.GetIdP(sess.provider_id) RETURNING idp.*
  IF idp.Issuer IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"SPManager","DoQueryLogout","Issuer not found")
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(C_HTTP_ERROR_LOGOUT_ERROR,baseurl))
    RETURN
  END IF

  IF logout THEN
    # Start logout dance
    CALL StartLogout(req, sess.*, idp.*)
  ELSE
    # No logout, release local session
    CALL Session.DeleteUUID(sess.uuid)
    # Set no cache headers
    CALL req.setResponseHeader(C_HTTP_CACHE_CONTROL, C_HTTP_NO_STORE || ", " || C_HTTP_NO_CACHE)
    CALL req.setResponseHeader(C_HTTP_PRAGMA, C_HTTP_NO_CACHE)

    IF sess.end_url IS NOT NULL THEN
      # Redirect to end_url
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","DoQueryLogout",SFMT("Redirected to %1",sess.end_url))
      CALL req.setResponseHeader(HTTPHelper.C_HTTP_LOCATION, sess.end_url)
      CALL req.sendResponse(302, NULL)
    ELSE
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","DoQueryLogout","done")
      CALL req.sendTextResponse(200, NULL, "Application ended")
    END IF
  END IF

  FREE sess.id_token

END FUNCTION

#+
#+ Perform logout protocol
#+  and remove session id
#+
PRIVATE
FUNCTION StartLogout(req, sess, idp)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  logoutURL STRING
  DEFINE  idp       IdPManager.IdPType
  DEFINE  sess      SessionType

  CALL DeleteUUID(sess.uuid)

  IF idp.end_session_endpoint IS NULL THEN
    LET logoutURL = sess.idp_logout_url
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","Logout","end_session endpoint not found, fallback to configured IDP")
  ELSE
    LET logoutURL = idp.end_session_endpoint
  END IF

  IF logoutURL.getCharAt(logoutURL.getLength())=='=' THEN
    # If logout URL ends with a query value, simply add end url at it
    # required in case IDP don't follow RP-Initiated Logout
    # or OAuth2
    IF sess.end_url IS NOT NULL THEN
      LET logoutURL = logoutURL || sess.end_url
    ELSE
      LET logoutURL = logoutURL
    END IF
  ELSE
    IF NOT idp.is_oauth2 THEN
      # Build OpenID logout url according to configuration
      IF base.Application.getResourceEntry("oidc.logout.id_token_hint") AND base.Application.getResourceEntry("oidc.logout.post_redirect") THEN
        IF sess.end_url IS NOT NULL THEN
          LET logoutURL = SFMT("%1?id_token_hint=%2&post_logout_redirect_uri=%3",logoutURL, sess.id_token, sess.end_url)
        ELSE
          LET logoutURL = SFMT("%1?id_token_hint=%2",logoutURL, sess.id_token)
        END IF
      ELSE
        IF base.Application.getResourceEntry("oidc.logout.id_token_hint") THEN
          LET logoutURL = SFMT("%1?id_token_hint=%2",logoutURL, sess.id_token)
        ELSE
          IF base.Application.getResourceEntry("oidc.logout.post_redirect") AND sess.end_url IS NOT NULL THEN
            LET logoutURL = SFMT("%1?post_logout_redirect_uri=%2",logoutURL, sess.end_url)
          ELSE
            LET logoutURL = logoutURL
          END IF
        END IF
      END IF
    END IF
  END IF

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"SPManager","Logout",SFMT("Redirected to %1",logoutURL))

  CALL req.setResponseHeader(C_HTTP_CACHE_CONTROL, C_HTTP_NO_STORE || ", " || C_HTTP_NO_CACHE)
  CALL req.setResponseHeader(C_HTTP_PRAGMA, C_HTTP_NO_CACHE)
  CALL req.setResponseHeader(HTTPHelper.C_HTTP_LOCATION, logoutURL)
  CALL req.sendResponse(302,NULL)
END FUNCTION

