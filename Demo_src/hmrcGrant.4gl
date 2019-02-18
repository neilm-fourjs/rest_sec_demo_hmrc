
# This program will attempt to get an access tokem for an HMRC user 
# It MUST be run via the GAS and uses the Delegation feature.

IMPORT FGL hmrcRest

&include "hmrcLib.inc"

CONSTANT C_CON_TIMEOUT = 5

TYPE t_hmrc_rec RECORD
		token STRING, 
		refresh_token STRING,
		token_endpoint STRING,
		token_expires INTEGER
	END RECORD
DEFINE m_hmrc_rec t_hmrc_rec
DEFINE m_secretId, m_clientId STRING
DEFINE m_msg STRING
MAIN
	DEFINE l_url STRING
	DEFINE l_dbName STRING

	OPEN FORM hmrcGrant FROM "hmrcGrant"
	DISPLAY FORM hmrcGrant

	LET l_dbName = fgl_getEnv("DBNAME")
	TRY
		CONNECT TO l_dbName
	CATCH
		LET m_msg = SFMT( "Error for DB '%1':%2", l_dbName ,SQLERRMESSAGE )
		CALL prog_finish()
		EXIT PROGRAM
	END TRY

	LET l_url = fgl_getEnv("HMRC_URL")
	LET l_url = NVL(l_url, "https://test-api.service.hmrc.gov.uk")

	LET m_clientId = fgl_getEnv("CLIENT_PUBLIC_ID")
	LET m_secretId = fgl_getEnv("CLIENT_SECRET_ID")

	LET m_hmrc_rec.token = fgl_getEnv("OIDC_ACCESS_TOKEN")
	LET m_hmrc_rec.refresh_token = fgl_getEnv("OIDC_REFRESH_TOKEN")
	LET m_hmrc_rec.token_endpoint = fgl_getEnv("OIDC_IDP_TOKEN_ENDPOINT")
	LET m_hmrc_rec.token_expires = fgl_getEnv("OIDC_TOKEN_EXPIRES_IN")

	IF m_hmrc_rec.token.getLength() > 0 THEN
		CALL dumpEnv("OIDC*")
-- Store the access tokein the DB.
		CALL upd_hmrcdb()
	ELSE
		LET m_msg = "No Token - Error!"
		CALL dumpEnv("*")
	END IF

	CALL prog_finish()
END MAIN
--------------------------------------------------------------------------------
FUNCTION prog_finish()
	DISPLAY BY NAME m_msg
	MENU
		ON ACTION close EXIT MENU
	END MENU
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION dumpEnv(l_match STRING)
	DEFINE c base.channel
	DEFINE l_line STRING
	LET c = base.Channel.create()
	CALL disp("----------Environment---------")
	CALL c.openPipe("env | sort", "r")
	WHILE NOT c.isEof()
		LET l_line = c.readLine()
		IF l_line.getLength() > 1 THEN
			IF l_line MATCHES l_match THEN
				CALL disp("Env: "||l_line)
			END IF
		END IF
	END WHILE
	CALL c.close()
	CALL disp("------------------------------")
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION upd_hmrcdb()
	DEFINE l_rec t_hmrcAccessTokens

	LET l_rec.vrn = ARG_VAL(1)
	LET l_rec.token =  m_hmrc_rec.token
	LET l_rec.refresh_token = m_hmrc_rec.refresh_token 
	LET l_rec.token_endpoint = m_hmrc_rec.token_endpoint
	LET l_rec.token_expires = CURRENT + (m_hmrc_rec.token_expires UNITS SECOND )

	SELECT * FROM hmrcAccessTokens WHERE vrn = l_rec.vrn
	IF STATUS = NOTFOUND THEN
		INSERT INTO hmrcAccessTokens VALUES( l_rec.* )
		IF STATUS = 0 THEN
			LET m_msg = "New Token Registered."
		ELSE
			LET m_msg = "New Token insert failed:",STATUS,":",SQLERRMESSAGE
		END IF
		
	ELSE
		UPDATE hmrcAccessTokens SET hmrcAccessTokens.* = l_rec.* WHERE vrn = l_rec.vrn
		IF STATUS = 0 THEN
			LET m_msg = "Token Updated."
		ELSE
			LET m_msg = "New Token update failed:",STATUS,":",SQLERRMESSAGE
		END IF
	END IF
ENd FUNCTION