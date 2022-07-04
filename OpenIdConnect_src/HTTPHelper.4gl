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

IMPORT FGL WSHelper

PUBLIC CONSTANT C_X_FOURJS_HTTPS                        = "X-FourJs-Environment-Variable-HTTPS"
PUBLIC CONSTANT C_X_FOURJS_REMOTE_ADDR                  = "X-FourJs-Environment-Variable-REMOTE_ADDR"
PUBLIC CONSTANT C_X_FOURJS_ENVIRONEMENT_                = "X-FourJs-Environment-"
PUBLIC CONSTANT C_X_FOURJS_ENVIRONEMENT_PARAMETER_      = "X-FourJs-Environment-Parameter-"
PUBLIC CONSTANT C_X_FOURJS_ENVIRONEMENT_PARAMETER_EXTRA = "X-FourJs-Environment-Parameter-Extra-"
PUBLIC CONSTANT C_X_FOURJS_BOOTSTRAP                    = "X-FourJs-Environment-Parameter-Extra-BOOTSTRAP"
PUBLIC CONSTANT C_X_FOURJS_FGL_AUTO_LOGOUT_PROMPT_QUERY = "X-FourJs-Environment-FGL_AUTO_LOGOUT_PROMPT_QUERY"
PUBLIC CONSTANT C_X_FOURJS_FGL_VMPROXY_END_URL          = "X-FourJs-Environment-FGL_VMPROXY_END_URL"
PUBLIC CONSTANT C_X_FOURJS_FGL_VMPROXY_START_URL        = "X-FourJs-Environment-FGL_VMPROXY_START_URL"

PUBLIC CONSTANT C_GENERO_INTERNAL_DELEGATE              = "_GENERO_INTERNAL_DELEGATE_"

PUBLIC CONSTANT C_DELEGATE = "Delegate"
PUBLIC CONSTANT C_PROMPT = "Prompt"
PUBLIC CONSTANT C_LOGOUT = "Logout"
PUBLIC CONSTANT C_RESUME_URL = "/ua/resume/"

PUBLIC CONSTANT C_OIDC_REDIRECT = "oauth2callback"
PUBLIC DEFINE C_OIDC_PATH STRING                  # Base URL of service 

PUBLIC CONSTANT C_HTTP_ERROR_INTERNAL_ERROR       = 0
PUBLIC CONSTANT C_HTTP_ERROR_BAD_REQUEST          = 1
PUBLIC CONSTANT C_HTTP_ERROR_NOT_IMPLEMENTED      = 2
PUBLIC CONSTANT C_HTTP_ERROR_PROTOCOL             = 3
PUBLIC CONSTANT C_HTTP_ERROR_INVALID_TOKEN        = 4
PUBLIC CONSTANT C_HTTP_ERROR_ACCESS_FORBIDDEN     = 5
PUBLIC CONSTANT C_HTTP_ERROR_ACCESS_DENIED        = 6
PUBLIC CONSTANT C_HTTP_ERROR_UNSECURED_CHANNEL    = 7
PUBLIC CONSTANT C_HTTP_ERROR_INVALID_PARAMETER    = 8
PUBLIC CONSTANT C_HTTP_ERROR_LOCALHOST_UNALLOWED  = 9
PUBLIC CONSTANT C_HTTP_ERROR_RELOGIN_DENIED       = 10
PUBLIC CONSTANT C_HTTP_ERROR_LOGOUT_ERROR         = 11

PRIVATE
CONSTANT C_HTTP_DefaultBody = "<html><head><title>Genero OpenID Connect error</title></head>\
  <body><div> \
  <div>ERROR: Unexpected error</div>\
  </div></body></html>"
  

PUBLIC
CONSTANT C_HTTP_PRAGMA          =   "Pragma"

PUBLIC
CONSTANT C_HTTP_CACHE_CONTROL   =   "Cache-Control"

PUBLIC
CONSTANT C_HTTP_LOCATION        =   "Location"

PUBLIC
CONSTANT C_HTTP_NO_CACHE        =   "no-cache"

PUBLIC 
CONSTANT C_HTTP_NO_STORE        =   "no-store"

PUBLIC 
CONSTANT C_COOKIE_OIDC          =   "GeneroOIDC"

PUBLIC
CONSTANT C_COOKIE_LAX           =   "Lax"

PUBLIC
CONSTANT C_CONTENT_TYPE = "Content-Type"

PUBLIC
CONSTANT C_TEXT_HTML = "text/html"

PUBLIC
FUNCTION RetrieveQueryIndexByName(query,NAME)
  DEFINE query  WSHelper.WSQueryType
  DEFINE NAME   STRING
  DEFINE ind    INTEGER
  FOR ind = 1 TO query.getLength()
    IF query[ind].NAME == NAME THEN
      RETURN ind
    END IF
  END FOR
  RETURN 0
END FUNCTION

PRIVATE
FUNCTION URLEncodeQueryPart(part)
  DEFINE part STRING
  DEFINE sb base.StringBuffer
  LET sb = base.StringBuffer.create()
  CALL sb.append(part)
  CALL sb.replace("=","%3D",0)
  CALL sb.replace("&","%26",0)
  CALL sb.replace("+","%2B",0)
  CALL sb.replace(" ","+",0)
  RETURN sb.toString()
END FUNCTION

#
# Build URL with query part encoded in a unambigous manner
#
PUBLIC
FUNCTION BuildQueryEncodedURL(url,query)
  DEFINE url  STRING
  DEFINE query  WSHelper.WSQueryType
  DEFINE ind  INTEGER
  DEFINE ret  STRING
  IF query.getLength()>0 THEN
    LET ret = url || "?"
  ELSE
    LET ret = url
  END IF
  FOR ind=1 TO query.getLength()
    LET ret = ret || URLEncodeQueryPart(query[ind].NAME)
    IF query[ind].VALUE IS NOT NULL THEN
      LET ret = ret || "=" || URLEncodeQueryPart(query[ind].VALUE)
    END IF
    IF ind<query.getLength() THEN
      LET ret = ret || "&"
    END IF
  END FOR

  RETURN ret
END FUNCTION

PUBLIC
FUNCTION GetErrorPage(code, baseURL)
  DEFINE  code    INTEGER
  DEFINE  doc     xml.DomDocument
  DEFINE  baseURL STRING
  DEFINE  list    xml.DomNodeList
  DEFINE  node    xml.DomNode
  DEFINE  css     STRING
  LET doc = xml.DomDocument.Create()
  TRY
    CASE code
      WHEN C_HTTP_ERROR_BAD_REQUEST
        CALL doc.load(base.Application.getResourceEntry("oidc.error.bad_request"))
      WHEN C_HTTP_ERROR_NOT_IMPLEMENTED
        CALL doc.load(base.Application.getResourceEntry("oidc.error.not_implemented"))
      WHEN C_HTTP_ERROR_PROTOCOL
        CALL doc.load(base.Application.getResourceEntry("oidc.error.protocol"))
      WHEN C_HTTP_ERROR_INVALID_TOKEN
        CALL doc.load(base.Application.getResourceEntry("oidc.error.invalid_token"))
      WHEN C_HTTP_ERROR_ACCESS_FORBIDDEN
        CALL doc.load(base.Application.getResourceEntry("oidc.error.access_forbidden"))
      WHEN C_HTTP_ERROR_ACCESS_DENIED
        CALL doc.load(base.Application.getResourceEntry("oidc.error.access_denied"))
      WHEN C_HTTP_ERROR_UNSECURED_CHANNEL
        CALL doc.load(base.Application.getResourceEntry("oidc.error.unsecured_channel"))
      WHEN C_HTTP_ERROR_INVALID_PARAMETER
        CALL doc.load(base.Application.getResourceEntry("oidc.error.invalid_xcf_parameter"))
      WHEN C_HTTP_ERROR_LOCALHOST_UNALLOWED
        CALL doc.load(base.Application.getResourceEntry("oidc.error.localhost_unallowed"))
      WHEN C_HTTP_ERROR_RELOGIN_DENIED
        CALL doc.load(base.Application.getResourceEntry("oidc.error.relogin_denied"))
      WHEN C_HTTP_ERROR_LOGOUT_ERROR
        CALL doc.load(base.Application.getResourceEntry("oidc.error.logout"))
      OTHERWISE
        CALL doc.load(base.Application.getResourceEntry("oidc.error.default"))
    END CASE 
    # Update ccs link with baseURL
    LET list = doc.selectByXPath("/pre:html/pre:head/pre:link[@type='text/css']","pre","http://www.w3.org/1999/xhtml")
    IF list.getCount()==1 THEN
      LET node = list.getItem(1)
      LET css = node.getAttribute("href")
      LET css = SFMT("%1%2",baseURL,css)
      CALL node.setAttribute("href",css)
    END IF    
    RETURN doc.saveToString()
  CATCH
    RETURN C_HTTP_DefaultBody
  END TRY
END FUNCTION
  
PUBLIC FUNCTION RemoveDefaultPortFromURL(url STRING)
  DEFINE sb base.StringBuffer
  LET sb = base.StringBuffer.create()
  CALL sb.append(url)
  IF sb.getIndexOf("https://",1)==1 THEN
    CALL sb.replace(":443/","/",1)
  ELSE
    IF url.getIndexOf("http://",1)==1 THEN
      CALL sb.replace(":80/","/",1)
    END IF
  END IF
  RETURN sb.toString()
END FUNCTION
