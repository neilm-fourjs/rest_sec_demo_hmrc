
# This is a test for calling an HMRC User web service.
# It MUST be run via the GAS and uses the Delegation feature.

IMPORT com
IMPORT util

IMPORT FGL demos_hmrc

CONSTANT C_SECRET = "xx"
CONSTANT C_CLIENTID = "xx"
CONSTANT C_CON_TIMEOUT = 5

TYPE t_hmrc_rec RECORD
		token STRING, 
		refresh_token STRING,
		token_endpoint STRING,
		token_expires INTEGER
	END RECORD
DEFINE m_txt STRING
DEFINE m_hmrc_rec t_hmrc_rec
MAIN
	DEFINE l_url STRING

	LET l_url = fgl_getEnv("HMRC_URL")
	LET l_url = NVL(l_url, "https://test-api.service.hmrc.gov.uk")

	OPEN FORM frm FROM "rest_sec_demo_hmrc"
	DISPLAY FORM frm

	LET m_hmrc_rec.token = fgl_getEnv("OIDC_ACCESS_TOKEN")
	LET m_hmrc_rec.refresh_token = fgl_getEnv("OIDC_REFRESH_TOKEN")
	LET m_hmrc_rec.token_endpoint = fgl_getEnv("OIDC_IDP_TOKEN_ENDPOINT")
	LET m_hmrc_rec.token_expires = fgl_getEnv("OIDC_TOKEN_EXPIRES_IN")
	DISPLAY BY NAME m_hmrc_rec.*

	IF m_hmrc_rec.token.getLength() > 0 THEN
		CALL dumpEnv("OIDC*")
	ELSE
		ERROR "No TOKEN !"
		CALL dumpEnv("*")
	END IF

	CALL disp( "Ready." )
	MENU "Tests"
		ON ACTION close EXIT MENU
		ON ACTION exit EXIT MENU

		ON ACTION refresh CALL refresh_token()

		ON ACTION hello CALL demos_hmrc.hello(l_url, m_hmrc_rec.token)

		ON ACTION obligations CALL demos_hmrc.obligations(l_url, m_hmrc_rec.token)

		ON ACTION returns CALL demos_hmrc.returns(l_url, m_hmrc_rec.token)
	END MENU
	CALL disp( "Finished." )
END MAIN
--------------------------------------------------------------------------------
FUNCTION refresh_token()
	DEFINE l_req_data, l_res_data STRING
	DEFINE l_stat SMALLINT
	DEFINE l_refresh_rec RECORD
			access_token STRING,
			refresh_token STRING,
			expires_in STRING,
			scope STRING,
			token_type STRING
		END RECORD

	LET l_req_data = 
		SFMT( "client_secret=%1&client_id=%2&grant_type=refresh_token&refresh_token=%3", C_SECRET, C_CLIENTID, m_hmrc_rec.refresh_token )
	CALL rest_hmrc_post( m_hmrc_rec.token_endpoint, l_req_data, NULL )
		 RETURNING l_stat, l_res_data
	TRY
		CALL util.JSON.parse(l_res_data, l_refresh_rec )
		CALL disp("Refresh New Token:"||l_refresh_rec.access_token)
		LET m_hmrc_rec.refresh_token = l_refresh_rec.refresh_token
		LET m_hmrc_rec.token = l_refresh_rec.access_token
	CATCH
		CALL disp("JSON Parse failed!")
	END TRY
END FUNCTION
--------------------------------------------------------------------------------
-- GET Request
FUNCTION rest_hmrc_get( l_url STRING, l_token STRING ) RETURNS (SMALLINT, STRING)
	DEFINE l_req com.HttpRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_info RECORD
		status SMALLINT,
		header STRING
	END RECORD
	DEFINE l_res_data STRING

	CALL disp("URL:"||l_url)
	LET l_req = com.HttpRequest.Create(l_url)
	CALL l_req.setMethod("GET")
	CALL l_req.setHeader("Content-Type", "application/json")
	CALL l_req.setHeader("Accept", "application/vnd.hmrc.1.0+json")
	CALL l_req.setHeader("Gov-Test-Scenario","-")

	IF l_token IS NOT NULL THEN
		CALL l_req.setHeader("Authorization", "Bearer "||l_token)
	END IF

	CALL disp("Setting Time Out "||C_CON_TIMEOUT)
	CALL l_req.setConnectionTimeOut( C_CON_TIMEOUT )

	CALL disp("doing doRequest ...")
	TRY
		CALL l_req.doRequest()
	CATCH
		LET l_res_data = "Failed to doRequest for "||l_url||" "||STATUS||" "||ERR_GET(STATUS)
		CALL disp( l_res_data )
		RETURN -1, l_res_data
	END TRY

	CALL disp("doing getResponse ...")
	TRY
		LET l_resp = l_req.getResponse()
	CATCH
		LET l_res_data = "Failed to getResponse for "||l_url||" "||STATUS||" "||ERR_GET(STATUS)
		CALL disp( l_res_data )
		RETURN -1, l_res_data
	END TRY

	CALL disp("getting Status ...")
	LET l_info.status = l_resp.getStatusCode()
	IF l_info.status != 200 THEN
		CALL disp( "Failed:"||l_info.status)
--		RETURN
	ELSE
		CALL disp( "Success!" )
	END IF

	LET l_info.header = l_resp.getHeader("Content-Type")
	CALL disp( "StatusCode:"||l_info.status )
	CALL disp( "Header:"||l_info.header )
	LET l_res_data = l_resp.getTextResponse()
	CALL disp( "Response:"||l_res_data )

	RETURN l_info.status, l_res_data

END FUNCTION
--------------------------------------------------------------------------------
-- POST Request
FUNCTION rest_hmrc_post(l_url STRING, l_data STRING, l_token STRING ) RETURNS (SMALLINT, STRING)
	DEFINE l_req com.HttpRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_info RECORD
		status SMALLINT,
		header STRING
	END RECORD
	DEFINE l_res_data STRING

	CALL disp("URL:"||l_url)
	LET l_req = com.HttpRequest.Create(l_url)
	CALL l_req.setMethod("POST")
	CALL l_req.setHeader("Content-Type", "application/x-www-form-urlencoded")
	CALL l_req.setHeader("Accept", "application/vnd.hmrc.1.0+json")
	CALL l_req.setHeader("Gov-Test-Scenario","-")

	IF l_token IS NOT NULL THEN
		CALL l_req.setHeader("Authorization", "Bearer "||l_token)
	END IF

	CALL disp("Setting Time Out "||C_CON_TIMEOUT)
	CALL l_req.setConnectionTimeOut( C_CON_TIMEOUT )

	CALL disp("Data:"||l_data)
	CALL disp("doing doTextRequest ...")
	TRY
		CALL l_req.doTextRequest(l_data)
	CATCH
		LET l_res_data = "Failed to doRequest for "||l_url||" "||STATUS||" "||ERR_GET(STATUS)
		CALL disp( l_res_data )
		RETURN -1, l_res_data
	END TRY

	CALL disp("doing getResponse ...")
	TRY
		LET l_resp = l_req.getResponse()
	CATCH
		LET l_res_data = "Failed to getResponse for "||l_url||" "||STATUS||" "||ERR_GET(STATUS)
		CALL disp( l_res_data )
		RETURN -1, l_res_data
	END TRY

	CALL disp("getting Status ...")
	LET l_info.status = l_resp.getStatusCode()
	IF l_info.status > 300 THEN
		CALL disp( "Failed:"|| l_info.status )
		--RETURN NULL
	ELSE
		CALL disp( "Success!" )
	END IF

	LET l_info.header = l_resp.getHeader("Content-Type")
	CALL disp( "StatusCode:"|| l_info.status )
	CALL disp( "Header:"|| l_info.header )
	LET l_res_data = l_resp.getTextResponse()
	CALL disp( "Response:"|| l_res_data )

	RETURN l_info.status, l_res_data

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION disp(l_txt STRING)
	LET m_txt = m_txt.append( CURRENT||":"||l_txt||"\n" )
	DISPLAY l_txt
	DISPLAY BY NAME m_txt
	CALL ui.Interface.refresh()
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