#
# FOURJS_START_COPYRIGHT(U,2018)
# Property of Four Js*
# (c) Copyright Four Js 2018, 2022. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#
IMPORT FGL getopt
IMPORT FGL DBase

# fglrun ImportOAuth -import https://www.facebook.com -authz https://www.facebook.com/v3.0/dialog/oauth -token https://graph.facebook.com/v3.0/oauth/access_token -logout https://www.facebook.com/logout.php -profile https://graph.facebook.com/me
# fglrun ImportOAuth -import https://www.instagram.com -authz https://api.instagram.com/oauth/authorize -token https://api.instagram.com/oauth/access_token -logout https://instagram.com/accounts/logout -profile https://api.instagram.com/v1/users/self?
CONSTANT cmd_line = "<IdP>\n    IdP    OAuth2 identity provider URL"

MAIN
  DEFINE p_authz    STRING
  DEFINE p_token    STRING
  DEFINE p_profile  STRING
  DEFINE p_logout   STRING
  DEFINE p_remove   BOOLEAN
  DEFINE p_import   BOOLEAN
  DEFINE p_keys     STRING

  DEFINE _options   getopt.GetoptOptions = [
    (name:"help",description:"Display this help.",opt_char:'h',arg_type:getopt.NONE),
    (name:"list",description:"List all imported IDPs.",opt_char:'l',arg_type:getopt.NONE),
    (name:"remove",description:"Remove IdP.",opt_char:'r',arg_type:getopt.NONE),
    (name:"import",description:"Import IdP as OAuth2.",opt_char:'i',arg_type:getopt.NONE),
    (name:"authz",description:"OAuth2 authorization end point URL (mandatory).",opt_char:'a',arg_type:getopt.REQUIRED),
    (name:"token",description:"OAuth2 token end point URL (mandatory).",opt_char:'t',arg_type:getopt.REQUIRED),
    (name:"profile",description:"OAuth2 user profile end point URL (optional).",opt_char:'p',arg_type:getopt.REQUIRED),
    (name:"logout",description:"OAuth2 logout end point URL (optional).",opt_char:'o',arg_type:getopt.REQUIRED),
    (name:"keys",description:"OAuth2 public JWK keys URL (recommended).",opt_char:'k',arg_type:getopt.REQUIRED)
    ]
  DEFINE g  getopt.Getopt

  IF NOT DBase.DBConnect() THEN
    DISPLAY "ERROR: unable to connect to database"
    EXIT PROGRAM(1)
  END IF

  CALL g.initDefault(_options)
  WHILE g.getopt() == getopt.SUCCESS
    CASE g.opt_char
      WHEN 'h'
        CALL g.displayUsage(cmd_line)
        EXIT PROGRAM 0
      WHEN 'l'
        CALL DoList()
        EXIT PROGRAM 0
      WHEN 'r'
        IF p_import THEN
          DISPLAY "Error: options 'r' and 'i' are exclusives"
          EXIT PROGRAM 1
        ELSE
          LET p_remove = TRUE
        END IF
      WHEN 'i'
        IF p_remove THEN
          DISPLAY "Error: options 'r' and 'i' are exclusives"
          EXIT PROGRAM 1
        ELSE
          LET p_import = TRUE
        END IF
      WHEN 'a'
        LET p_authz = g.opt_arg
      WHEN 't'
        LET p_token = g.opt_arg
      WHEN 'p'
        LET p_profile = g.opt_arg
      WHEN 'o'
        LET p_logout = g.opt_arg
      WHEN 'k'
        LET p_keys = g.opt_arg
    END CASE
  END WHILE

  IF g.invalidOptionSeen() THEN
    CALL g.displayUsage(cmd_line)
    EXIT PROGRAM 1
  END IF

  IF g.getMoreArgumentCount()!=1 THEN
    DISPLAY "Error: IdP is missing"
    EXIT PROGRAM 1
  END IF

  IF p_remove THEN
    CALL DoRemove(g.argv[g.opt_ind])
  ELSE
    IF p_import THEN
      IF p_authz IS NULL OR p_token IS NULL THEN
        DISPLAY "Error : OAuth2 import requires authorization and token url"
        EXIT PROGRAM 1
      ELSE
        CALL DoImport(g.argv[g.opt_ind],p_authz, p_token, p_profile, p_logout, p_keys)
      END IF
    ELSE
      CALL g.displayUsage(cmd_line)
    END IF
  END IF


  CALL DBase.DBDisconnect()


END MAIN

FUNCTION DoList()
  DEFINE p_myID     INTEGER
  DEFINE p_issuer   VARCHAR(255)
  DEFINE p_oauth2   BOOLEAN
  DECLARE c1 CURSOR FOR
      SELECT id, issuer, is_oauth2
      FROM fjs_oidc_provider
  DISPLAY "Listing identity providers:"
  FOREACH c1 INTO p_myID, p_issuer, p_oauth2
    IF p_oauth2 THEN
      DISPLAY "  #"||p_myID||"(OAuth2) : ",p_issuer
    ELSE
      DISPLAY "  #"||p_myID||"(OpenID) : ",p_issuer
    END IF
  END FOREACH
  DISPLAY "Done..."
END FUNCTION

FUNCTION DoImport(p_issuer, p_authz, p_token, p_userinfo, p_logout, p_keys)
  DEFINE p_issuer   VARCHAR(255)
  DEFINE p_authz    VARCHAR(255)
  DEFINE p_token    VARCHAR(255)
  DEFINE p_userinfo VARCHAR(255)
  DEFINE p_logout   VARCHAR(255)
  DEFINE p_keys     VARCHAR(255)
  TRY
    DISPLAY "Importing "||p_issuer||" as OAuth2"
    INSERT INTO fjs_oidc_provider ( issuer, authorization_endpoint, token_endpoint, userinfo_endpoint, jwks_uri, end_session_endpoint, is_oauth2)
      VALUES (p_issuer, p_authz, p_token, p_userinfo, p_keys, p_logout, TRUE)
    DISPLAY "...Done"
    IF p_keys IS NULL THEN
      DISPLAY "Warning: no signature keys"
    END IF
  CATCH
    DISPLAY "...Failed"
  END TRY
END FUNCTION

FUNCTION DoRemove(p_issuer)
  DEFINE p_issuer VARCHAR(255)
  DEFINE p_id     INTEGER
  DEFINE p_certs  VARCHAR(255)
  TRY
    SELECT id, jwks_uri
    INTO p_id, p_certs
    FROM fjs_oidc_provider
    WHERE issuer == p_issuer
  CATCH
    DISPLAY "No identity provider found"
    RETURN
  END TRY

  TRY
    DISPLAY "Removing identity provider :",p_issuer
    DELETE FROM fjs_oidc_provider
      WHERE id == p_id
    IF p_certs IS NOT NULL THEN
      DELETE FROM fjs_oidc_keys
      WHERE provider_id == p_id
    END IF
    DISPLAY "...Done"
  CATCH
    DISPLAY "...Failed"
  END TRY
END FUNCTION
