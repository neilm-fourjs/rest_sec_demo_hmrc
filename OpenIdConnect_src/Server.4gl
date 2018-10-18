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

IMPORT COM
IMPORT UTIL
IMPORT Security

IMPORT FGL Logs
IMPORT FGL DBase
IMPORT FGL JWT
IMPORT FGL JWK
IMPORT FGL Access
IMPORT FGL HTTPHelper
IMPORT FGL Utils
IMPORT FGL SPManager
IMPORT FGL RelayState
IMPORT FGL Session
IMPORT FGL WSHelper

PRIVATE CONSTANT C_CLEANUP_DELAY        =   3600 # Cleanup database every hour

#
# Server main
#
MAIN
  DEFINE  req       com.HttpServiceRequest
  DEFINE  ind       INTEGER
  DEFINE  path      STRING
  DEFINE  remoteip  STRING
  DEFINE  p_debug   STRING
  DEFINE  p_path    STRING
  DEFINE  baseurl   STRING
  DEFINE  httpson   STRING
  DEFINE  operation STRING

  # Parse arguments
  FOR ind = 1 TO num_args() STEP 2
    CASE arg_val(ind)
      WHEN "-debug"
        LET p_debug = arg_val(ind+1)
      WHEN "-logPath"
        LET p_path = arg_val(ind+1)
    END CASE
  END FOR

  # Initialize log
  CALL Logs.LOG_INIT(p_debug,p_path,"hmrcOIDC.log")
  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Main", SFMT("Started FGLWSDEBUG=%1 FGLSQLDEBUG=%2", fgl_getEnv("FGLWSDEBUG"),fgl_getEnv("FGLSQLDEBUG")))

  # Initialize DB
  IF NOT DBase.DBConnect() THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Database","unable to connect")
    EXIT PROGRAM (1)
  END IF

  # Detect JGAS and adapt BASE url accordingly
  IF fgl_getenv("FGLJGAS") IS NOT NULL THEN
    LET HTTPHelper.C_OIDC_PATH = "/ws/r/hmrcOpenIDConnectServiceProvider/"
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Main","JGAS detected")
  ELSE
    LET HTTPHelper.C_OIDC_PATH = "/ws/r/hmrcOpenIDConnectServiceProvider/"
  END IF

  # Initialize connection layer
  CALL com.WebServiceEngine.SetOption("readwritetimeout",60)
  CALL com.WebServiceEngine.SetOption("connectiontimeout",25)
  # Start server
  CALL com.WebServiceEngine.Start()

  WHILE TRUE
    TRY
      LET req = com.WebServiceEngine.GetHttpServiceRequest(C_CLEANUP_DELAY)
      IF req IS NULL THEN
        CALL Cleanup()
      ELSE
        LET path = req.getUrlPath()
        LET remoteip = req.getRequestHeader(C_X_FOURJS_REMOTE_ADDR)
        CALL Logs.LOG_EVENT(Logs.C_LOG_ACCESS,"Request",remoteip,"incoming request : "||path)
        LET ind = path.getIndexOf(HTTPHelper.C_OIDC_PATH,1)
        IF ind<1 THEN
          CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
          CALL req.sendTextResponse(400,NULL,GetErrorPage(C_HTTP_ERROR_BAD_REQUEST))
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Request",remoteip,"invalid request")
        ELSE

          #
          # Retrieve operation
          #
          LET operation = path.subString(ind+HTTPHelper.C_OIDC_PATH.getLength(),path.getLength())

          #
          # Build base URL
          #

          LET HTTPSON = req.getRequestHeader(HTTPHelper.C_X_FOURJS_HTTPS)
          IF HTTPSON IS NOT NULL THEN
            LET baseURL = "https://"
          ELSE
            LET baseURL = "http://"
          END IF

          # Host name
          LET baseURL = baseURL||req.getUrlHost()

          # Port (if any)
          IF req.getUrlPort() != 0 THEN
            LET baseURL = baseURL||":"||req.getUrlPort()
          END IF

          # Path
          LET path = path.subString(1,ind-1)
          IF path IS NOT NULL THEN
            LET baseURL = baseURL||path
          END IF

          CALL DispatchService(req, baseURL, operation)
        END IF
        CALL Logs.LOG_EVENT(Logs.C_LOG_ACCESS,"Request",remoteip,"response returned")
      END IF
    CATCH
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Request",STATUS)
      EXIT WHILE
    END TRY
  END WHILE

  # Handle expirations
  CALL Cleanup()

  # Close database
  CALL DBase.DBDisconnect()

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Main","Stopped")

END MAIN

FUNCTION Cleanup()
   CALL Access.CleanupToken()
   CALL RelayState.CleanupRelayState()
   CALL Session.CleanupUUID()
END FUNCTION

#
# Dispatch request according to path after baseURL
#
FUNCTION DispatchService(req, baseURL, operation)
  DEFINE  req       com.HttpServiceRequest
  DEFINE  baseURL   STRING
  DEFINE  operation STRING
  DEFINE  ind       INTEGER
  DEFINE  query     WSHelper.WSQueryType
  LET ind = operation.getIndexOf("/",1)
  IF ind>0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","DispatchService","invalid path")
  ELSE
    # Retrieve decoded URL query string
    CALL req.getURLQuery(query)
    # Dispatch according to operation
    CASE operation
      WHEN HTTPHelper.C_LOGOUT
        IF req.getMethod()=="POST" THEN
          CALL DoLogoutPost(req, baseURL, query)
        ELSE
          CALL DoLogoutGet(req, baseURL, query)
        END IF
      WHEN HTTPHelper.C_PROMPT
        CALL DoPrompt(req, baseURL, query)
      WHEN HTTPHelper.C_DELEGATE
        CALL Delegate(req, baseURL, query)
      WHEN HTTPHelper.C_OIDC_REDIRECT
        CALL SPManager.ProcessAuthenticationCallback(req, baseURL, query)
      OTHERWISE
        CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
        CALL req.sendTextResponse(501,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_NOT_IMPLEMENTED))
        CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","DispatchService","unknown service '"||operation||"'")
    END CASE
  END IF
END FUNCTION

#
# Handle dispatcher delegate service
#
FUNCTION Delegate(req, baseURL, query)
  DEFINE  req         com.HttpServiceRequest
  DEFINE  baseURL     STRING        # Delegate service URL
  DEFINE  attrs       Access.AttributeType
  DEFINE  ok          BOOLEAN
  DEFINE  _found      BOOLEAN
  DEFINE  query       WSHelper.WSQueryType
  DEFINE  originalURL STRING

  IF query.getLength()==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Delegate","Query is missing")
    RETURN
  END IF
  IF query[1].name!="url" OR query[1].VALUE IS NULL THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Delegate","Query URL is missing")
  ELSE

    LET originalURL = query[1].VALUE

    # Remove url param
    CALL query.deleteElement(1)

    IF originalURL.getIndexOf(C_RESUME_URL,1)>1 THEN
      # Resume URL
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Delegate Resume URL",originalURL)
      CALL SPManager.HasAccess(req, originalURL, query) RETURNING ok, _found, attrs
      IF ok THEN
        CALL SPManager.Resume(req)
      ELSE
        CALL SPManager.Forbid(req)
      END IF

    ELSE

      CALL SPManager.HasAccess(req, originalURL, query) RETURNING ok, _found, attrs
      IF ok THEN
        # ACCESS IS GRANTED
    	  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Delegate URL OK",originalURL)
        CALL SPManager.StartProxy(req, HTTPHelper.BuildQueryEncodedURL(originalURL, query) , attrs)
      ELSE
        # ACCESS DENIED
        IF NOT _found THEN
          # NOT COOKIE FOUND
    	  	CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Delegate URL DENIED StartAuthentication",originalURL)
          CALL SPManager.StartAuthentication(req, baseURL, HTTPHelper.BuildQueryEncodedURL(originalURL, query) )
        ELSE
    	  	CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Server","Delegate URL DENIED FORBID",originalURL)
          CALL SPManager.ForbidAccess(req)
        END IF
      END IF
    END IF
  END IF
END FUNCTION

#
# Handle AUTO LOGOUT Prompt service
#
FUNCTION DoPrompt(req, baseURL, query)
  DEFINE  req         com.HttpServiceRequest
  DEFINE  baseURL     STRING
  DEFINE  query       WSHelper.WSQueryType
  DEFINE  ind         INTEGER
  DEFINE  did_uuid    STRING
  DEFINE  session_id  STRING
  DEFINE  timeout     STRING

  IF query.getLength()==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Prompt","Query is missing")
    RETURN
  END IF

  # Retrieve mandatory query parts
  LET ind = query.search("name","prompt")
  IF ind==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Prompt","prompt is missing")
    RETURN
  ELSE
    LET did_uuid = query[ind].value
  END IF

  # Retrieve mandatory query parts
  LET ind = query.search("name","session")
  IF ind==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Prompt","session is missing")
    RETURN
  ELSE
    LET session_id = query[ind].value
  END IF

  # Retrieve mandatory query parts
  LET ind = query.search("name","timeout")
  IF ind==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Prompt","timeout is missing")
    RETURN
  ELSE
    LET timeout = query[ind].value
  END IF

  # Start reauthentication
  CALL SPManager.StartReauthentication(req, baseURL, did_uuid, session_id, timeout)

END FUNCTION

#
# Handle LOGOUT service
#
FUNCTION DoLogoutGet(req, baseURL, query)
  DEFINE  req         com.HttpServiceRequest
  DEFINE  baseURL     STRING
  DEFINE  query       WSHelper.WSQueryType
  DEFINE  ind         INTEGER

  IF query.getLength()==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Logout","Query is missing")
    RETURN
  END IF


  # Retrieve mandatory did parts
  LET ind = query.search("name","gid")
  IF ind==0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","Logout","gid is missing")
  ELSE
    CALL SPManager.DoLogout(req, baseURL, query[ind].value)
  END IF


END FUNCTION

#
# Handle LOGOUT POST service
#
FUNCTION DoLogoutPost(req, baseURL, query)
  DEFINE  req         com.HttpServiceRequest
  DEFINE  baseURL     STRING
  DEFINE  query       WSHelper.WSQueryType
  DEFINE  ind         INTEGER
  DEFINE  uuid        STRING
  DEFINE  data        STRING
  DEFINE  formdata    WSHelper.WSQueryType

  IF query.getLength()!=0 THEN
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","DoLogoutPost","Error: No query string expected")
    RETURN
  END IF

  TRY
    LET data = req.readFormEncodedRequest(TRUE)
    CALL WSHelper.SplitQueryString(data) RETURNING formdata
    # Retrieve mandatory did value
    LET ind = formdata.search("name","gid")
    IF ind==0 THEN
      CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
      CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","DoLogoutPost","Error : gid is missing")
      RETURN
    ELSE
      LET uuid = formdata[ind].VALUE
      # Retrieve mandatory logout value
      LET ind = formdata.search("name","logout")
      IF ind>0 THEN
        CASE formdata[ind].VALUE
          WHEN "yes"
            CALL SPManager.DoQueryLogout(req, uuid, TRUE)
            RETURN
          WHEN "no"
            CALL SPManager.DoQueryLogout(req, uuid, FALSE)
            RETURN
        END CASE
      END IF
    END IF

    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(400,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_BAD_REQUEST))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","DoLogoutPost","Bad request")

  CATCH
    CALL req.setResponseHeader(HTTPHelper.C_CONTENT_TYPE,HTTPHelper.C_TEXT_HTML)
    CALL req.sendTextResponse(500,NULL,GetErrorPage(HTTPHelper.C_HTTP_ERROR_INTERNAL_ERROR))
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Server","DoLogoutPost","Internal error")
  END TRY


END FUNCTION
