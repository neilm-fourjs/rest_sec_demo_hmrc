#
# FOURJS_START_COPYRIGHT(U,2018)
# Property of Four Js*
# (c) Copyright Four Js 2018, 2018. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#
IMPORT FGL DBase

# fglrun ImportOAuth -import https://www.facebook.com -authz https://www.facebook.com/v3.0/dialog/oauth -token https://graph.facebook.com/v3.0/oauth/access_token -logout https://www.facebook.com/logout.php -profile https://graph.facebook.com/me
# fglrun ImportOAuth -import https://www.instagram.com -authz https://api.instagram.com/oauth/authorize -token https://api.instagram.com/oauth/access_token -logout https://instagram.com/accounts/logout -profile https://api.instagram.com/v1/users/self?

MAIN
  DEFINE ind        INTEGER
  DEFINE p_authz    STRING
  DEFINE p_token    STRING
  DEFINE p_profile  STRING
  DEFINE p_logout   STRING

  IF NOT DBase.DBConnect() THEN
    DISPLAY "ERROR: unable to connect to database"
    EXIT PROGRAM(1)
  END IF

  IF num_args()<1 THEN
    CALL ShowUsage()
  ELSE
    CASE arg_val(1)
      WHEN "-import"
        IF num_args()>=6 THEN
          FOR ind = 3 TO num_args() STEP 2
            CASE arg_val(ind)
              WHEN "-authz"
                LET p_authz = arg_val(ind+1)
              WHEN "-token"
                LET p_token = arg_val(ind+1)
              WHEN "-profile"
                LET p_profile = arg_val(ind+1)
              WHEN "-logout"
                LET p_logout = arg_val(ind+1)
              OTHERWISE
                CALL ShowUsage()
            END CASE
          END FOR
          CALL DoImport(arg_val(2),p_authz, p_token, p_profile, p_logout)
        ELSE
          CALL ShowUsage()
        END IF
      WHEN "-list"
        CALL DoList()
      WHEN "-remove"
        CALL DoRemove(arg_val(2))
      OTHERWISE
        CALL ShowUsage()
    END CASE

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

FUNCTION DoImport(p_issuer, p_authz, p_token, p_userinfo, p_logout)
  DEFINE p_issuer   VARCHAR(255)
  DEFINE p_authz    VARCHAR(255)
  DEFINE p_token    VARCHAR(255)
  DEFINE p_userinfo VARCHAR(255)
  DEFINE p_logout   VARCHAR(255)
  IF p_issuer IS NULL OR p_authz IS NULL OR p_token IS NULL THEN
    DISPLAY "Error : OAuth requires IDP, authorization and token url"
    CALL ShowUsage()
  END IF
  TRY
    DISPLAY "Importing "||p_issuer||" as OAuth2"
    INSERT INTO fjs_oidc_provider ( issuer, authorization_endpoint, token_endpoint, userinfo_endpoint, end_session_endpoint, is_oauth2)
      VALUES (p_issuer, p_authz, p_token, p_userinfo, p_logout, true)
    DISPLAY "...Done"
  CATCH
    DISPLAY "...Failed"
  END TRY
END FUNCTION

FUNCTION DoRemove(p_issuer)
  DEFINE p_issuer VARCHAR(255)
  DEFINE p_id     INTEGER
  DEFINE p_certs  VARCHAR(255)
  IF p_issuer IS NULL THEN
    CALL ShowUsage()
  END IF
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

FUNCTION ShowUsage()
  DISPLAY "Usage :"||arg_val(0)||" [options] <IdP> <-authz url> <-token url> [-profile url] [-logout url]"
  DISPLAY "  options:"
  DISPLAY "    -list            : List all imported IdPs"
  DISPLAY "    -remove          : Remove IdP"
  DISPLAY "    -import          : Import IdP as OAuth2"
  DISPLAY "       Requires following parameters:"
  DISPLAY "       -authz   URL     : Mandatory authorization end point URL"
  DISPLAY "       -token   URL     : Mandatory token end point URL"
  DISPLAY "       -profile URL     : Optional user profile end point URL"
  DISPLAY "       -logout  URL     : Optional logout end point URL"
  EXIT PROGRAM (1)
END FUNCTION
