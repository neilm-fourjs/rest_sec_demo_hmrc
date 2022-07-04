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
IMPORT util

CONSTANT GOOGLE_ACCOUNTS = "https://accounts.google.com"

TYPE RegistrationRequestType RECORD
  redirect_uris DYNAMIC ARRAY OF STRING,
  client_name STRING,
  logo_uri STRING
END RECORD

MAIN

  DEFINE  req   com.HttpRequest
  DEFINE  resp  com.HttpResponse
  DEFINE  regReq RegistrationRequestType
  LET regReq.redirect_uris[1] = "https://cube.strasbourg.4js.com/gas/ws/r/services/OpenIDConnectService_Frank/oauth2callback"
  LET regReq.client_name = "My Gas test Application"
  LET regReq.logo_uri = "http://www.4js.com/templates/fourjs/images/fourjs_logo.png"
  LET req = com.HttpRequest.Create(GOOGLE_ACCOUNTS||"/register")
  CALL req.setMethod("POST")
  CALL req.setHeader("Content-Type","application/json")
  CALL req.doTextRequest(Util.JSON.stringify(regReq))
  LET resp = req.getResponse()
  IF resp.getStatusCode() == 200 THEN
    DISPLAY "OK :",resp.getTextResponse()
  ELSE
    DISPLAY "KO :",resp.getTextResponse()
  END IF
END MAIN

