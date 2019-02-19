IMPORT com

CONSTANT C_CON_TIMEOUT = 5

--------------------------------------------------------------------------------
-- Do a RESTFULL call.
FUNCTION request( l_url STRING, l_token STRING, l_data STRING ) RETURNS (SMALLINT, STRING)
	DEFINE l_req com.HttpRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_info RECORD
		status SMALLINT,
		header STRING
	END RECORD
	DEFINE l_reply_data STRING

	LET l_url = fgl_getEnv("HMRC_URL")||l_url
	CALL disp("URL:"||l_url)
	LET l_req = com.HttpRequest.Create(l_url)
	IF l_data IS NULL THEN
		CALL l_req.setMethod("GET")
	ELSE
		CALL l_req.setMethod("POST")
	END IF
	CALL l_req.setHeader("Content-Type", "application/json")
	CALL l_req.setHeader("Accept", "application/vnd.hmrc.1.0+json")
	CALL l_req.setHeader("Gov-Test-Scenario","-")

	CALL disp("Setting Time Out "||C_CON_TIMEOUT)
	CALL l_req.setConnectionTimeOut( C_CON_TIMEOUT )

	IF l_token IS NOT NULL THEN
		CALL l_req.setHeader("Authorization", "Bearer "||l_token)
	END IF

	IF l_data IS NULL THEN
		CALL disp("doing doRequest ...")
		TRY
			CALL l_req.doRequest()
		CATCH
			LET l_info.status = STATUS
			LET l_reply_data = SFMT( "Failed to doRequest for %1 - %2 %3", l_url, l_info.status, ERR_GET(l_info.status))
			RETURN l_info.status, l_reply_data
		END TRY
	ELSE
		CALL disp("doing doTextRequest ...")
		TRY
			CALL l_req.doTextRequest(l_data)
		CATCH
			LET l_info.status = STATUS
			LET l_reply_data = SFMT( "Failed to doTextRequest for %1 - %2 %3", l_url, l_info.status,ERR_GET(l_info.status) )
			RETURN l_info.status, l_reply_data
		END TRY
	END IF

	CALL disp("doing getResponse ...")
	TRY
		LET l_resp = l_req.getResponse()
	CATCH
		LET l_info.status = STATUS
		LET l_reply_data = "Failed to getResponse for %1 - %2 %3", l_url, l_info.status,ERR_GET(l_info.status) 
		RETURN l_info.status, l_reply_data
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
	CALL disp( "Header:"||l_info.header )
	LET l_reply_data = l_resp.getTextResponse()
	RETURN l_info.status, l_reply_data
END FUNCTION
--------------------------------------------------------------------------------