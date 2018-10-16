IMPORT com

CONSTANT C_CON_TIMEOUT = 5

--------------------------------------------------------------------------------
-- GET Request
FUNCTION get( l_url STRING, l_token STRING ) RETURNS (SMALLINT, STRING)
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
FUNCTION post(l_url STRING, l_data STRING, l_token STRING ) RETURNS (SMALLINT, STRING)
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