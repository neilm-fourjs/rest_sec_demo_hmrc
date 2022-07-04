# This program will attempt to get an access tokem for an HMRC user
# It MUST be run via the GAS and uses the Delegation feature.
IMPORT os
IMPORT FGL hmrcRest
IMPORT FGL hmrcLib
IMPORT FGL OAuthAPI

&include "hmrcLib.inc"

DEFINE m_msg STRING
MAIN
	DEFINE l_hmrcToken t_hmrcAccessToken
	DEFINE l_expires   INTEGER
	DEFINE l_clientId  STRING
	DEFINE l_secretId  STRING
	DEFINE l_hmrc_url  STRING
	DEFINE l_scopes    STRING

	LET l_clientId = fgl_getEnv("CLIENT_PUBLIC_ID")
	LET l_secretId = fgl_getEnv("CLIENT_SECRET_ID")
	LET l_hmrc_url = fgl_getEnv("HMRC_URL")
	LET l_scopes   = fgl_getEnv("SCOPES")

	DISPLAY SFMT("Prog: %1 Dir: %2 Time: %3", base.Application.getProgramName(), os.path.pwd(), CURRENT)

	OPEN FORM hmrcGrant FROM "hmrcGrant"
	DISPLAY FORM hmrcGrant

	IF NOT connectToDB() THEN
		LET m_msg = hmrcLib.m_db_err
		CALL prog_finish()
		EXIT PROGRAM
	END IF

	LET l_hmrcToken.vrn = ARG_VAL(1)
	IF l_hmrcToken.vrn IS NULL OR LENGTH(l_hmrcToken.vrn) < 2 THEN
		CALL dumpEnv("*")
		LET m_msg = SFMT("Invalid Args! - %1", ARG_VAL(1))
		CALL prog_finish()
		EXIT PROGRAM
	END IF

-- Try and token info from the environment
	LET l_hmrcToken.token          = fgl_getEnv("OIDC_ACCESS_TOKEN")
	LET l_hmrcToken.refresh_token  = fgl_getEnv("OIDC_REFRESH_TOKEN")
	LET l_hmrcToken.token_endpoint = fgl_getEnv("OIDC_IDP_TOKEN_ENDPOINT")
	LET l_expires                  = fgl_getEnv("OIDC_TOKEN_EXPIRES_IN")
	LET l_hmrcToken.token_expires  = CURRENT + (l_expires UNITS SECOND)
	IF LENGTH(l_hmrcToken.token) < 2 THEN
		LET m_msg = "No Token in Environment!"
		DISPLAY m_msg
		CALL dumpEnv("*")
	ELSE
		CALL dumpEnv("OIDC*")
	END IF

-- Try and token info using the OAuthAPI library code
	IF LENGTH(l_hmrcToken.token) < 2 THEN
		CALL OAuthAPI.RetrieveServiceToken(5, l_hmrc_url || "/oauth/token", l_clientId, l_secretId, l_scopes)
				RETURNING l_hmrcToken.token, l_expires
		IF l_hmrcToken.token IS NULL THEN
			LET m_msg = "No Token from  OAuthAPI.RetrieveServiceToken!"
			DISPLAY m_msg
		ELSE
			DISPLAY "Access token value :", l_hmrcToken.token
			DISPLAY SFMT("Token expires in %1 seconds", l_expires)
			LET l_hmrcToken.token_expires = CURRENT + (l_expires UNITS SECOND)
		END IF
	END IF

	IF LENGTH(l_hmrcToken.token) > 2 THEN
-- Store the access tokein the DB.
		IF NOT hmrcLib.updateTokenInDB(l_hmrcToken.*) THEN
			LET m_msg = hmrcLib.m_db_err
		ELSE
			LET m_msg = "Token Registered"
		END IF
	END IF

	CALL prog_finish()
END MAIN
--------------------------------------------------------------------------------
FUNCTION prog_finish()
	DISPLAY BY NAME m_msg
	MENU
		ON ACTION close
			EXIT MENU
	END MENU
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION dumpEnv(l_match STRING)
	DEFINE c      base.channel
	DEFINE l_line STRING
	LET c = base.Channel.create()
	CALL disp("----------Environment---------")
	CALL c.openPipe("env | sort", "r")
	WHILE NOT c.isEof()
		LET l_line = c.readLine()
		IF l_line.getLength() > 1 THEN
			IF l_line MATCHES l_match THEN
				CALL disp("Env: " || l_line)
			END IF
		END IF
	END WHILE
	CALL c.close()
	CALL disp("------------------------------")
END FUNCTION
