IMPORT com
IMPORT util
CONSTANT C_CON_TIMEOUT = 5

--------------------------------------------------------------------------------
-- Do a RESTFULL call.
FUNCTION request(l_url STRING, l_token STRING, l_data STRING) RETURNS(SMALLINT, STRING)
	DEFINE l_req  com.HttpRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_info RECORD
		status SMALLINT,
		header STRING
	END RECORD
	DEFINE l_reply_data STRING
    DEFINE l_meth STRING
    DEFINE l_cont_type STRING
    DEFINE l_bearer STRING

	CALL processing(SFMT("Processing: %1", l_url))
	LET l_req = com.HttpRequest.Create(l_url)

    LET l_meth = "GET"
    LET l_cont_type = "application/json"
	IF l_data IS NOT NULL THEN
        LET l_meth = "POST"
        LET l_cont_type = "application/x-www-form-urlencoded"
    END IF
    CALL l_req.setMethod(l_meth)
	CALL l_req.setHeader("Content-Type", l_cont_type )
    CALL processing(SFMT("%1 - %2", l_meth, l_cont_type ))

	CALL l_req.setHeader("Accept", "application/vnd.hmrc.1.0+json")
--	CALL l_req.setHeader("Gov-Test-Scenario", "-")

	CALL processing("Setting Time Out " || C_CON_TIMEOUT)
	CALL l_req.setConnectionTimeOut(C_CON_TIMEOUT)

	IF l_token IS NOT NULL THEN
        LET l_bearer = SFMT("Bearer %1", l_token)
	    CALL processing(SFMT("Authorization: %1", l_bearer))
		CALL l_req.setHeader("Authorization", l_bearer)
	END IF

	IF l_data IS NULL THEN
		CALL processing("doing doRequest ...")
		TRY
			CALL l_req.doRequest()
		CATCH
			LET l_info.status = STATUS
			LET l_reply_data  = SFMT("Failed to doRequest for %1 - %2 %3", l_url, l_info.status, ERR_GET(l_info.status))
			RETURN l_info.status, l_reply_data
		END TRY
	ELSE
		CALL processing(SFMT("doing doTextRequest (%1) ...",l_data))
		TRY
			CALL l_req.doTextRequest(l_data)
		CATCH
			LET l_info.status = STATUS
			LET l_reply_data  = SFMT("Failed to doTextRequest for %1 - %2 %3", l_url, l_info.status, ERR_GET(l_info.status))
			RETURN l_info.status, l_reply_data
		END TRY
	END IF

	CALL processing("doing getResponse ...")
	TRY
		LET l_resp = l_req.getResponse()
	CATCH
		LET l_info.status = STATUS
		LET l_reply_data  = "Failed to getResponse for %1 - %2 %3", l_url, l_info.status, ERR_GET(l_info.status)
		RETURN l_info.status, l_reply_data
	END TRY

	CALL processing("getting Status ...")
	LET l_info.status = l_resp.getStatusCode()
	IF l_info.status > 250 THEN
		CALL processing("Failed:" || l_info.status)
	ELSE
		CALL processing("Success:" || l_info.status)
	END IF

	LET l_info.header = l_resp.getHeader("Content-Type")
	CALL disp("Header:" || l_info.header)
	LET l_reply_data = l_resp.getTextResponse()
	RETURN l_info.status, l_reply_data
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION getLocalSecrets() RETURNS (STRING, STRING)
    DEFINE l_text TEXT
    DEFINE l_rec RECORD
        clientid STRING,
        secretid STRING
    END RECORD
    LOCATE l_text IN FILE "../secrets.json"
    CALL util.JSON.parse(l_text, l_rec)
    RETURN l_rec.clientid, l_rec.secretid
END FUNCTION